import { getPendingProposals, isContractOurs, LIQUID_TOKEN_ADDRESS, AVS_ADDRESS } from '../utils/forge'
import { type NodeAllocation, stakeAssetsToNodes } from '../tasks/stakeAssetsToNodes'

interface LATResponse {
    address: string
    assets: { asset: string; balance: string }[]
}

interface TokensResponse {
    data: {
        address: string
        strategyAddress: string
        decimals: number
        pricePerUnit: string
    }[]
}

interface StakerNodesResponse {
    stakerNodes: {
        nodeId: number
        operatorDelegation: string
    }[]
}

interface OperatorInsightsResponse {
    data: {
        id: number
        operatorStrategyId: number
        operatorProspectId: number
        purity: number
        fees: number
        daysInPreference: number
        daysInWarning: number
        warningSev: number | null
        createdAt: Date
        updatedAt: Date
        operatorProspect: {
            id: number
            liquidTokenAddress: string
            operatorAddress: string
            isDelegated: boolean
            bias: number
            daysInPreference: number
            daysInWarning: number
            warningSev: number | null
            createdAt: Date
            updatedAt: Date
        }
        operatorStrategy: {
            id: number
            operatorAddress: string
            strategyAddress: string
            variableApy: number
            constantApy: number
            createdAt: Date
            updatedAt: Date
        }
    }[]
    meta: {
        count: number
    }
}

interface AvsResponse {
    address: string
    tvl: {
        tvl: number
        tvlBeaconChain: number
        tvlWETH: number
        tvlRestaking: number
        tvlStrategies: Record<string, number>
        tvlStrategiesEth: Record<string, number>
    }
}

interface StrategyOperator {
    strategyAddress: string
    operatorAddress: string
    purity: number
    fees: number
    variableApy: number
    constantApy: number
    bias: number
    daysInPreference: number
    warningSev: number | null
    isDelegated: boolean
}

interface AllocationResult {
    strategyAddress: string
    operatorAddress: string
    aTvlEth: bigint
}

interface ApiUpdate {
    operatorProspectId: number
    daysInPreference: number
    daysInWarning: number
    warningSev: number | null
}

interface StrategyCategories {
    sev1Strategies: string[]
    sev2Strategies: string[]
    sev3Strategies: string[]
}

const LAT_API_URL = process.env.LAT_API_URL
const EE_API_URL = process.env.EE_API_URL
const EE_API_TOKEN = process.env.EE_API_TOKEN

const MIN_DAYS_IN_PREF = 3
const MAX_DAYS_IN_WARN_SEV3 = 7
const MAX_DAYS_IN_WARN_SEV2 = MAX_DAYS_IN_WARN_SEV3 + 7
const MAX_DAYS_IN_WARN_SEV1 = MAX_DAYS_IN_WARN_SEV2 + 7

// Fetch all Operator prospects + Operator Prospect Strategy (from /lat/operator-insights)
// Fetch the AVS with tvl for each strategy
// Fetch TVL ETH deposits (dTvlEth)
// Fetch TVL ETH withdrawals (wTvlEth)
// Calc restakeable TVL ETH as rTvlEth = dTvlEth - wTvlEth
//
// Create strategyOperators <strategy, operator[]>[]
// Create currently possible allocations (cpsa)
//     - check for first ever run: if lat's stakedTvl = 0, genesis = true
//     - in each record of strategyOperators, filter
//          - operators: (delegated === true) && (warningSev === null/0 || bias === true)
//          - strategies: (genesis) || ((warningSev === null/0) && (daysInPreference >= MIN_DAYS_IN_PREF) && (operators.length > 0))
//     - for the set of (strategy, operator)[] find allocation TVLs aTvlEth[] = r(rTvlEth, strategyOperator[]) such that
//          - aggregate P (WP) is maximised where WP = w(P[], aTvlEth[]) ie, simple weighting algorithm, where P = p(purity, variableApy, constantApy, bias, fees)
//          - the main consideration here is that the variableApy value reduces when tvl gets allocated to the strategy because ΔAPY = APY₀ × (TVL₀/(TVL₀ + ΔTVL) - 1) ie, there is dilution of apy for every $1 more tvl allocated to the strategy
//     - now we have cpsa = (strategyAddress, operatorAddress, aTvlEth)[] ordered by aTvlEth desc
//
// Create best case scenario allocations (bcsa) so that we can signal warn/pref to the OperatorProspectStrategy table
//     - in each record, filter
//          - operators: (delegated === true) && (warningSev === null/0 || bias === true)
//          - strategies: operators.length > 0
//     - follow same logic as above
//     - now we have bcsa = (strategyAddress, operatorAddress, aTvlEth)[] ordered by aTvlEth desc
//
// Construct pref/warn action set from bcsa
//     - in each record, if the strategy
//          - has aTvlEth === 0 [reset the pref and increase warn]
//              - if (daysInWarning >= MAX_DAYS_IN_WARN_SEV2) then (daysInWarning++ && warningSev = 1 && daysInPreference = 0 && sev1Strategies.push(strategy))
//              - else if (daysInWarning >= MAX_DAYS_IN_WARN_SEV3) then (daysInWarning++ && warningSev = 2 && daysInPreference = 0 && sev2Strategies.push(strategy))
//              - else if (daysInWarning || 0 < MAX_DAYS_IN_WARN_SEV3)) then (daysInWarning++ && warningSev = 3 && daysInPreference = 0 && sev3Strategies.push(strategy))
//          - has aTvlEth > 0 [reduce warn until zero then begin pref]
//              - if (daysInWarning - 1 >= MAX_DAYS_IN_WARN_SEV2) then (--daysInWarning && warningSev = 1)
//              - else if (daysInWarning - 1 >= MAX_DAYS_IN_WARN_SEV3) then (--daysInWarning && warningSev = 2)
//              - else if (daysInWarning - 1 < MAX_DAYS_IN_WARN_SEV3) then (--daysInWarning && warningSev = 3)
//              - else if (daysInWarning - 1 === 0 && warningSev != null) then (--daysInWarning && warningSev = null)
//              - else if (genesis) then (daysInPreference = MIN_DAYS_IN_PREF)
//              - else if (daysInPreference < MIN_DAYS_IN_PREF) then (daysInPreference++)
//      - now we have dbTransactions: any[]
//
// Construct withdrawals if wTvlEth > 0
//     - re-order cpsa such that we first reverse the list then move all sev1Strategies on top and then sev2Strategies after that (sev3Strategies will naturally fall next as they have 0 aTvl). note that we do not add any new strategies that are not alrady in cpsa
//     - now we have wPref = (strategyAddress, operator.nodeId)[]
//     - create dAvl = (depositStrategyAddress, tvl)[]
//     - create sAvl = (strategyAddress, operator.nodeId, tvl)[]
//     - create wR = (withdrawStrategyAddress, tvl)[]
//     - calc swaps
//         - allocate swaps from dAvl, SD = sd(wPref, dAvl, min(wTvlEth, dTvlEth))
//         - if rTvlEth < 0, allocate swaps from sAvl, SS = sd(wPref, sAvl, rTvlEth)
//             - sd() and ss() allocates such that we first spread all tvl equally amongst sev1Strategies, if filled -> sev2Strategies, if filled -> sev3Strategies, if filled -> each single strategy in order
//     - now we have
//         - SD = (ltAssetsToSwap[], ltAmountsToSwap[], ltAssetsToWithdraw[])
//         - SS = (nodeIds[], elAssetsToSwap[][], elAmountsToSwap[][], elAssetsToWithdraw[][])
//     - create W = w(SS, SD) such that W = (requestIds[], ltAssetsToSwap[], ltAmountsToSwap[], ltAssetsToWithdraw[], nodeIds[], elAssetsToSwap[][], elAmountsToSwap[][], elAssetsToWithdraw[][])
//
// Construct deposits if rTvlEth > 0
//     - create D = d(cpsa) such that D = (nodeIds[], assetsToSwap[][], amountsToSwap[][], assetsToStake[][])
//     - note: if there are not enough staked funds for withdrawals, it is because some funds are still under withdrawal or node undelegation
//
// Construct node withdrawals
//     - for each strategy in sev1Strategies, check (strategy.daysInWarning >= MAX_DAYS_IN_WARN_SEV1)
//         - if yes, push <nodeId, (asset, strategyTvl)> to nwList
//     - create NW = nw(nwList) such that NW = (nodeIds[], assets[][], amounts[][])
//
// if (dbTransactions) send updates via API
// if (wTvlEth > 0) propose withdrawals via swapAndSettleUserWithdrawals(W)
// if (rTvlEth > 0) propose deposits via swapAndStakeAssetsToNode(D)
// if (NW) propose node withdrawals via withdrawNodeAssets(NW)

/**
 * Workflow for staking unstaked assets in the `LiquidToken` contract across nodes
 * Policy: Split every asset across all Operators that restake it
 *
 * @returns
 */
export async function stakeUnstakedAssets() {
    try {
        // Check if the multisig has any pending proposals for this LAT
        const pendingProposals = await getPendingProposals()
        for (const proposal of pendingProposals) {
            if (isContractOurs(proposal.to.toLowerCase())) {
                throw new Error(
                    `Cannot execute workflow due to existing pending tx for this LAT at nonce ${proposal.nonce}`
                )
            }
        }

        // Gather and structure required data
        const result = await fetchRequiredData()
        if (!result) {
            console.log('[Manager][Warning] No delegated nodes found. Skipping workflow...')
            return []
        }
        const { nodesData, tokensData, operatorInsights, avsData, latData } = result
        const delegatedNodes = nodesData.stakerNodes.filter(
            (node) => node.operatorDelegation !== '0x0000000000000000000000000000000000000000'
        )
        const tokenInfoMap = new Map(tokensData.data.map((token) => [token.address.toLowerCase(), token]))
        const unstakedAssets = latData.assets
        const unstakedTvlEth = await calcTvlEthFromNative(
            unstakedAssets.map((ua) => ua.asset.toLowerCase()),
            unstakedAssets.map((ua) => ua.balance)
        )

        // LATER: Fetch withdrawals and calc TVL ETH withdrawals (wTvlEth)
        // LATER: Calc restakeable TVL ETH as rTvlEth = dTvlEth - wTvlEth

        const strategyOperators: StrategyOperator[] = []

        for (const insight of operatorInsights.data) {
            const strategyOperator: StrategyOperator = {
                strategyAddress: insight.operatorStrategy.strategyAddress,
                operatorAddress: insight.operatorStrategy.operatorAddress,
                purity: insight.purity,
                fees: insight.fees,
                variableApy: insight.operatorStrategy.variableApy,
                constantApy: insight.operatorStrategy.constantApy,
                bias: insight.operatorProspect.bias,
                daysInPreference: insight.operatorProspect.daysInPreference,
                warningSev: insight.operatorProspect.warningSev,
                isDelegated: insight.operatorProspect.isDelegated
            }
            strategyOperators.push(strategyOperator)
        }

        const stakedTvl = latData.assets.reduce((sum, asset) => sum + Number(asset.balance), 0)
        const genesis = stakedTvl === 0 // True if this is the first run for a LAT

        const filteredStrategyOperators = strategyOperators.filter((so) => {
            const operatorQualified = so.isDelegated && (so.warningSev === null || so.warningSev === 0 || so.bias > 0)
            const strategyQualified =
                genesis || ((so.warningSev === null || so.warningSev === 0) && so.daysInPreference >= MIN_DAYS_IN_PREF)

            return operatorQualified && strategyQualified
        })

        const cpsaAllocations = r(unstakedTvlEth, filteredStrategyOperators)
        const cpsa: AllocationResult[] = filteredStrategyOperators
            .map((so, index) => ({
                strategyAddress: so.strategyAddress,
                operatorAddress: so.operatorAddress,
                aTvlEth: cpsaAllocations[index]
            }))
            .filter((allocation) => allocation.aTvlEth > 0n)
            .sort((a, b) => {
                if (a.aTvlEth > b.aTvlEth) return -1
                if (a.aTvlEth < b.aTvlEth) return 1
                return 0
            })

        const bcsaFilteredStrategyOperators = strategyOperators.filter((so) => {
            const operatorQualified = so.isDelegated && (so.warningSev === null || so.warningSev === 0 || so.bias > 0)
            const strategyQualified = operatorQualified // If operator is qualified, strategy is qualified

            return operatorQualified && strategyQualified
        })

        // Follow same allocation logic as above
        const bcsaAllocations = r(unstakedTvlEth, bcsaFilteredStrategyOperators)
        const bcsa: AllocationResult[] = bcsaFilteredStrategyOperators
            .map((so, index) => ({
                strategyAddress: so.strategyAddress,
                operatorAddress: so.operatorAddress,
                aTvlEth: bcsaAllocations[index]
            }))
            .filter((allocation) => allocation.aTvlEth > 0n)
            .sort((a, b) => {
                if (a.aTvlEth > b.aTvlEth) return -1
                if (a.aTvlEth < b.aTvlEth) return 1
                return 0
            })

        const { apiUpdates, strategyCategories } = constructPrefWarnActions(bcsa, operatorInsights, genesis)

        // LATER: Construct withdrawals
        // LATER: Construct deposits
        // LATER: Construct node withdrawals

        if (apiUpdates.length > 0) {
            await sendApiUpdates(apiUpdates)
        }
        // LATER: All multisig tx proposals

        console.log('[Manager] Stake unstaked assets complete')
    } catch (error) {
        console.log('[Manager] Error: ', error.message)
        throw error
    }
}

// --- Helper functions ---

async function fetchRequiredData(): Promise<{
    nodesData: StakerNodesResponse
    tokensData: TokensResponse
    operatorInsights: OperatorInsightsResponse
    avsData: AvsResponse
    latData: LATResponse
} | null> {
    // Fetch staker nodes and their delegations
    const nodesResponse = await fetch(`${LAT_API_URL}/lat/${LIQUID_TOKEN_ADDRESS}/staker-nodes`)
    if (!nodesResponse.ok) {
        throw new Error(`Failed to fetch staker nodes: ${nodesResponse.status} ${nodesResponse.statusText}`)
    }
    const nodesData = (await nodesResponse.json()) as StakerNodesResponse

    // Check for delegated nodes
    const nodes = nodesData.stakerNodes
    if (nodes.filter((node) => node.operatorDelegation !== '0x0000000000000000000000000000000000000000').length === 0) {
        return null
    }

    // Fetch remaining data
    const tokenPromise = fetch(`${LAT_API_URL}/lat/${LIQUID_TOKEN_ADDRESS}/tokens`).then((response) => {
        if (!response.ok) {
            throw new Error(`Failed to fetch token data: ${response.status} ${response.statusText}`)
        }
        return response.json()
    })

    const operatorInsightsPromise = fetch(`${LAT_API_URL}/lat/${LIQUID_TOKEN_ADDRESS}/operator-insights`).then(
        (response) => {
            if (!response.ok) {
                throw new Error(`Failed to fetch Operator Insights data: ${response.status} ${response.statusText}`)
            }
            return response.json()
        }
    )

    const avsPromise = fetch(`${EE_API_URL}/avs/${AVS_ADDRESS}?withTvl=true`, {
        headers: {
            'X-API-Token': `${EE_API_TOKEN}`
        }
    }).then((response) => {
        if (!response.ok) {
            throw new Error(`Failed to fetch AVS data: ${response.status} ${response.statusText}`)
        }
        return response.json()
    })

    const latPromise = fetch(`${LAT_API_URL}/lat/${LIQUID_TOKEN_ADDRESS}`).then((response) => {
        if (!response.ok) {
            throw new Error(`Failed to fetch LAT data: ${response.status} ${response.statusText}`)
        }
        return response.json()
    })

    const [tokensData, operatorInsights, avsData, latData] = await Promise.all([
        tokenPromise,
        operatorInsightsPromise,
        avsPromise,
        latPromise
    ])

    return {
        nodesData,
        tokensData,
        operatorInsights,
        avsData,
        latData
    }
}

async function calcTvlEthFromNative(assets: string[], amounts: string[]) {
    return 1n
}

// Performance score calculation
function p(purity: number, variableApy: number, constantApy: number, bias: number, fees: number): number {
    // Normalize inputs to 0-1 range for consistent weighting
    const normalizedPurity = Math.min(purity / 100, 1) // Assuming purity is 0-100
    const normalizedVariableApy = Math.min(variableApy / 100, 1) // Assuming APY is percentage
    const normalizedConstantApy = Math.min(constantApy / 100, 1)
    const normalizedBias = bias > 0 ? 1 : 0 // Binary: biased operators get bonus
    const normalizedFees = Math.max(0, 1 - fees / 100) // Lower fees = higher score

    // Weighted performance score (adjust weights based on importance)
    const weights = {
        purity: 0.25, // Strategy reliability/track record
        variableApy: 0.3, // Current yield potential
        constantApy: 0.2, // Base yield guarantee
        bias: 0.15, // Preference for biased operators
        fees: 0.1 // Fee efficiency
    }

    return (
        normalizedPurity * weights.purity +
        normalizedVariableApy * weights.variableApy +
        normalizedConstantApy * weights.constantApy +
        normalizedBias * weights.bias +
        normalizedFees * weights.fees
    )
}

// Weighted performance calculation
function w(performances: number[], allocations: bigint[]): number {
    if (performances.length !== allocations.length || performances.length === 0) {
        return 0
    }

    // Convert allocations to numbers for calculation
    const allocationNumbers = allocations.map((a) => Number(a))
    const totalAllocation = allocationNumbers.reduce((sum, a) => sum + a, 0)

    if (totalAllocation === 0) {
        return 0
    }

    // Calculate weighted average performance
    let weightedSum = 0
    for (let i = 0; i < performances.length; i++) {
        const weight = allocationNumbers[i] / totalAllocation
        weightedSum += performances[i] * weight
    }

    return weightedSum
}

// Placeholder for TVL conversion
function tvlToTvlEth(tvl: number): bigint {
    // Placeholder - implement actual conversion logic
    // This should convert native token amounts to ETH equivalent
    return BigInt(Math.floor(tvl))
}

// APY dilution calculation
function calculateDilutedApy(currentApy: number, currentTvl: bigint, additionalTvl: bigint): number {
    if (currentTvl === 0n) {
        return currentApy // No dilution if no existing TVL
    }

    const currentTvlNum = Number(currentTvl)
    const additionalTvlNum = Number(additionalTvl)

    // ΔAPY = APY₀ × (TVL₀/(TVL₀ + ΔTVL) - 1)
    const dilutionFactor = currentTvlNum / (currentTvlNum + additionalTvlNum)
    return currentApy * dilutionFactor
}

// Main allocation optimization algorithm using w() for weighted performance maximization
function r(totalTvlEth: bigint, strategyOperators: StrategyOperator[]): bigint[] {
    if (strategyOperators.length === 0) {
        return []
    }

    const n = strategyOperators.length

    if (totalTvlEth === 0n) {
        return new Array(n).fill(0n)
    }

    // Get current TVL for each strategy
    const currentStrategyTvls: bigint[] = strategyOperators.map((so) => tvlToTvlEth(1)) // TODO

    const totalTvlNum = Number(totalTvlEth)
    const ALLOCATION_STEPS = 100 // Number of optimization steps
    const STEP_SIZE = totalTvlNum / ALLOCATION_STEPS

    let bestAllocations: bigint[] = new Array(n).fill(0n)
    let bestWeightedPerformance = 0

    // Iterative optimization: try different allocation combinations
    for (let step = 0; step < ALLOCATION_STEPS; step++) {
        const currentAllocations: bigint[] = new Array(n).fill(0n)
        let remainingTvl = totalTvlNum

        // Greedy allocation with w() optimization at each step
        while (remainingTvl > STEP_SIZE) {
            let bestStepIndex = -1
            let bestStepWeightedPerformance = -1

            // Try adding STEP_SIZE to each strategy-operator and see which gives best w()
            for (let i = 0; i < n; i++) {
                // Create test allocation
                const testAllocations = [...currentAllocations]
                testAllocations[i] += BigInt(Math.floor(STEP_SIZE))

                // Calculate performance scores for this test allocation
                const performances: number[] = []
                for (let j = 0; j < n; j++) {
                    const so = strategyOperators[j]
                    const currentAllocation = Number(testAllocations[j])

                    if (currentAllocation === 0) {
                        performances.push(0) // No performance if no allocation
                        continue
                    }

                    // Calculate diluted APY considering current allocation
                    const currentTotalTvl = Number(currentStrategyTvls[j]) + currentAllocation
                    const dilutedApy = calculateDilutedApy(
                        so.variableApy,
                        currentStrategyTvls[j],
                        BigInt(currentAllocation)
                    )

                    // Calculate performance with diluted APY
                    const performance = p(so.purity, dilutedApy, so.constantApy, so.bias, so.fees)

                    performances.push(performance)
                }

                // Calculate weighted performance using w()
                const weightedPerformance = w(performances, testAllocations)

                if (weightedPerformance > bestStepWeightedPerformance) {
                    bestStepWeightedPerformance = weightedPerformance
                    bestStepIndex = i
                }
            }

            // Apply the best step
            if (bestStepIndex >= 0) {
                currentAllocations[bestStepIndex] += BigInt(Math.floor(STEP_SIZE))
                remainingTvl -= STEP_SIZE
            } else {
                break
            }
        }

        // Allocate any remaining amount to the best single performer
        if (remainingTvl > 0) {
            let bestRemainingIndex = 0
            let bestRemainingPerformance = -1

            for (let i = 0; i < n; i++) {
                const so = strategyOperators[i]
                const performance = p(so.purity, so.variableApy, so.constantApy, so.bias, so.fees)
                if (performance > bestRemainingPerformance) {
                    bestRemainingPerformance = performance
                    bestRemainingIndex = i
                }
            }

            currentAllocations[bestRemainingIndex] += BigInt(Math.floor(remainingTvl))
        }

        // Calculate final weighted performance for this allocation
        const finalPerformances: number[] = strategyOperators.map((so, i) => {
            const allocation = Number(currentAllocations[i])
            if (allocation === 0) return 0

            const dilutedApy = calculateDilutedApy(so.variableApy, currentStrategyTvls[i], currentAllocations[i])

            return p(so.purity, dilutedApy, so.constantApy, so.bias, so.fees)
        })

        const finalWeightedPerformance = w(finalPerformances, currentAllocations)

        // Keep track of the best allocation found so far
        if (finalWeightedPerformance > bestWeightedPerformance) {
            bestWeightedPerformance = finalWeightedPerformance
            bestAllocations = [...currentAllocations]
        }
    }

    return bestAllocations
}

function matchAssetToStrategy(assetAddress: string, strategies: any[]): string | null {
    // Placeholder function to match asset address to strategy address
    // Note: every asset has a strategy but their addresses are different
    return null
}

function constructPrefWarnActions(
    bcsa: AllocationResult[],
    operatorInsights: OperatorInsightsResponse,
    genesis: boolean
): { apiUpdates: ApiUpdate[]; strategyCategories: StrategyCategories } {
    const apiUpdates: ApiUpdate[] = []
    const strategyCategories: StrategyCategories = {
        sev1Strategies: [],
        sev2Strategies: [],
        sev3Strategies: []
    }

    // Create a map for quick allocation lookup
    const allocationMap = new Map<string, bigint>()
    for (const allocation of bcsa) {
        const key = `${allocation.strategyAddress}-${allocation.operatorAddress}`
        allocationMap.set(key, allocation.aTvlEth)
    }

    // Process each operator insight to determine pref/warn actions
    for (const insight of operatorInsights.data) {
        const key = `${insight.operatorStrategy.strategyAddress}-${insight.operatorStrategy.operatorAddress}`
        const aTvlEth = allocationMap.get(key) || 0n

        let newDaysInPreference = insight.operatorProspect.daysInPreference
        let newDaysInWarning = insight.operatorProspect.daysInWarning || 0
        let newWarningSev = insight.operatorProspect.warningSev

        if (aTvlEth === 0n) {
            // Strategy has no allocation - reset preference and increase warning
            newDaysInPreference = 0

            if (newDaysInWarning >= MAX_DAYS_IN_WARN_SEV1) {
                newDaysInWarning++
                newWarningSev = 1
                if (!strategyCategories.sev1Strategies.includes(insight.operatorStrategy.strategyAddress)) {
                    strategyCategories.sev1Strategies.push(insight.operatorStrategy.strategyAddress)
                }
            } else if (newDaysInWarning >= MAX_DAYS_IN_WARN_SEV2) {
                newDaysInWarning++
                newWarningSev = 2
                if (!strategyCategories.sev2Strategies.includes(insight.operatorStrategy.strategyAddress)) {
                    strategyCategories.sev2Strategies.push(insight.operatorStrategy.strategyAddress)
                }
            } else {
                newDaysInWarning++
                newWarningSev = 3
                if (!strategyCategories.sev3Strategies.includes(insight.operatorStrategy.strategyAddress)) {
                    strategyCategories.sev3Strategies.push(insight.operatorStrategy.strategyAddress)
                }
            }
        } else {
            // Strategy has allocation - reduce warning until zero then begin preference
            if (newDaysInWarning > 0) {
                newDaysInWarning--

                if (newDaysInWarning >= MAX_DAYS_IN_WARN_SEV1) {
                    newWarningSev = 1
                } else if (newDaysInWarning >= MAX_DAYS_IN_WARN_SEV2) {
                    newWarningSev = 2
                } else if (newDaysInWarning > 0) {
                    newWarningSev = 3
                } else {
                    // Days in warning reached 0
                    newWarningSev = null
                }
            } else if (newWarningSev !== null) {
                // Clear warning severity if no warning days left
                newWarningSev = null
            }

            // Handle preference days
            if (genesis) {
                newDaysInPreference = MIN_DAYS_IN_PREF
            } else if (newDaysInPreference < MIN_DAYS_IN_PREF && newWarningSev === null) {
                newDaysInPreference++
            }
        }

        // Only create an update if something changed
        if (
            newDaysInPreference !== insight.operatorProspect.daysInPreference ||
            newDaysInWarning !== (insight.operatorProspect.daysInWarning || 0) ||
            newWarningSev !== insight.operatorProspect.warningSev
        ) {
            apiUpdates.push({
                operatorProspectId: insight.operatorProspect.id,
                daysInPreference: newDaysInPreference,
                daysInWarning: newDaysInWarning,
                warningSev: newWarningSev
            })
        }
    }

    return { apiUpdates, strategyCategories }
}

async function sendApiUpdates(apiUpdates: ApiUpdate[]): Promise<void> {
    if (apiUpdates.length === 0) {
        console.log('[Manager] No API updates needed')
        return
    }

    const response = await fetch(`${LAT_API_URL}/lat/${LIQUID_TOKEN_ADDRESS}/operator-prospects/batch-update`, {
        method: 'POST',
        headers: {
            'Content-Type': 'application/json'
        },
        body: JSON.stringify({ updates: apiUpdates })
    })

    if (!response.ok) {
        throw new Error(`Failed to send API updates: ${response.status} ${response.statusText}`)
    }

    console.log(`[Manager] Successfully sent ${apiUpdates.length} API updates`)
}
