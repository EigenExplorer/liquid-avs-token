import { getPendingProposals, isContractOurs, LIQUID_TOKEN_ADDRESS, AVS_ADDRESS } from '../utils/forge'
import { type NodeAllocation, stakeAssetsToNodes } from '../tasks/stakeAssetsToNodes'

interface LatResponse {
    address: string
    baseAsset: string
    assets: { asset: string; balance: string }[]
    tvl: {
        tvlAssetsEth: Record<string, number>
        tvlAssetsBase?: Record<string, number>
    }
}

interface TokenInfo {
    address: string
    symbol: string
    strategyAddress: string
    decimals: number
    pricePerUnit: string
}

interface TokensResponse {
    data: TokenInfo[]
}

interface StakerNode {
    nodeId: number
    operatorDelegation: string
    assets: {
        strategy: string
    }[]
}

interface StakerNodesResponse {
    stakerNodes: StakerNode[]
}

interface OperatorProspectStrategy {
    id: number
    operatorStrategyId: number
    operatorProspectId: number
    commonStakeApy: number
    operatorSetStakeApy: number
    purityBps: number
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
        baseApy: number
        elApy: number
        feesBps: number
        createdAt: Date
        updatedAt: Date
    }
}

interface OperatorInsightsResponse {
    data: OperatorProspectStrategy[]
}

interface OperatorAvsStrategyMetrics {
    operatorAddress: string
    bias: number
    baseApy: number
    elApy: number
    feesBps: number
    commonStakeApy: number
    operatorSetStakeApy: number
    purityBps: number
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

interface AllocationResult {
    strategyAddress: string
    operatorAddress: string
    aTvlBase: bigint
}

interface NodeAllocationWithSwap {
    nodeId: number
    assetsToSwap: string[]
    amountsToSwap: bigint[]
    assetsToStake: string[]
}

interface ApiUpdate {
    id: number
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

/**
 * Workflow for staking unstaked assets in the `LiquidToken` contract across nodes
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

        // Gather required data
        const { nodesData, tokensData, operatorProspectStrategies, avsData, latData } = await fetchLatState()

        const tokenInfo = new Map(tokensData.data.map((token) => [token.address.toLowerCase(), token]))
        const baseAssetSymbol = tokenInfo.get(latData.baseAsset.toLowerCase())?.symbol
        const quantum = getQuantum(latData, baseAssetSymbol)

        const unstakedTvlBase = await calcTvlBaseFromNative(
            latData.assets.map((ua) => ua.asset.toLowerCase()),
            latData.assets.map((ua) => ua.balance),
            tokenInfo
        )

        const withdrawalTvlBase = 1n // TODO: Fetch withdrawals and calc its total tvl in base asset
        const restakeableTvlBase = unstakedTvlBase > withdrawalTvlBase ? unstakedTvlBase - withdrawalTvlBase : 0n

        const delegatedNodes = nodesData.stakerNodes.filter(
            (node) => node.operatorDelegation !== '0x0000000000000000000000000000000000000000'
        )

        const assetsAvailable = new Map<string, bigint>()
        for (const asset of latData.assets) {
            assetsAvailable.set(asset.asset.toLowerCase(), BigInt(asset.balance))
        }

        // Construct optimal allocations constained by strategy warnings
        // With this, create a set of node allocations for `LTM.swapAndStakeAssetsToNodes`
        const constrainedEligibleOps = operatorProspectStrategies.data.filter((ops) => {
            // The OperatorProspect should be delegated and not be in warning
            // If in warning, but biased, we allow it
            const operatorProspect = ops.operatorProspect
            const operatorProspectQualified =
                operatorProspect.isDelegated &&
                (operatorProspect.warningSev === null || operatorProspect.warningSev === 0 || operatorProspect.bias > 0)

            // The OperatorProspectStrategy should not be in warning and also should have been in pref for at least `MIN_DAYS_IN_PREF`
            // If this is the first time that the strategy is being evaluated (strategy restaked tvl is 0), then we forgo the `MIN_DAYS_IN_PREF` requirement
            const strategyGenesis = !delegatedNodes.some((n) =>
                n.assets.map((a) => a.strategy.toLowerCase() === ops.operatorStrategy.strategyAddress.toLowerCase())
            )
            const strategyQualified =
                (ops.warningSev === null || ops.warningSev === 0) &&
                (ops.daysInPreference >= MIN_DAYS_IN_PREF || strategyGenesis)

            return operatorProspectQualified && strategyQualified
        })

        const constrainedOptimalAllocations = await calculateOptimalAllocations(
            restakeableTvlBase,
            constrainedEligibleOps,
            avsData,
            quantum,
            tokenInfo,
            baseAssetSymbol
        )

        // Construct optimal allocations NOT constained by strategy warnings
        // This helps us decide any pref/warn actions for strategies, we do not use these results for actual allocation
        const unconstrainedEligibleOps = operatorProspectStrategies.data.filter((ops) => {
            // The OperatorProspect should be delegated and not be in warning
            // If in warning, but biased, we allow it
            const operatorProspect = ops.operatorProspect
            const operatorProspectQualified =
                operatorProspect.isDelegated &&
                (operatorProspect.warningSev === null || operatorProspect.warningSev === 0 || operatorProspect.bias > 0)

            return operatorProspectQualified // Consider all strategies to be qualified
        })

        const unconstrainedOptimalAllocations = await calculateOptimalAllocations(
            restakeableTvlBase,
            constrainedEligibleOps,
            avsData,
            quantum,
            tokenInfo,
            baseAssetSymbol
        )
        const { apiUpdates, strategyCategories } = constructPrefWarnActions(
            unconstrainedOptimalAllocations,
            unconstrainedEligibleOps
        )

        // TODO (After withdrawals finalized)
        // Construct withdrawals with swaps and return remaining available assets

        // Construct node allocations with swaps fromt the remaining available assets
        const nodeAllocations = constructNodeAllocations(
            delegatedNodes,
            constrainedOptimalAllocations,
            assetsAvailable, // TODO: Use the remaining assets available after withdrawals allocatiosn
            tokenInfo
        )

        await sendApiUpdates(apiUpdates)
        // if (withdrawalAllocations.length) await swapAndSettleUserWithdrawals(withdrawalAllocations)
        // if (nodeAllocations.length) await swapAndStakeAssetsToNodes(nodeAllocations)

        console.log('[Manager] Stake unstaked assets complete')
    } catch (error) {
        console.log('[Manager] Error: ', error.message)
        throw error
    }
}

// --- Helper functions ---

async function fetchLatState(): Promise<{
    nodesData: StakerNodesResponse
    tokensData: TokensResponse
    operatorProspectStrategies: OperatorInsightsResponse
    avsData: AvsResponse
    latData: LatResponse
}> {
    // Fetch staker nodes and their delegations
    const nodesResponse = await fetch(`${LAT_API_URL}/lat/${LIQUID_TOKEN_ADDRESS}/staker-nodes`)
    if (!nodesResponse.ok) {
        throw new Error(`Failed to fetch staker nodes: ${nodesResponse.status} ${nodesResponse.statusText}`)
    }
    const nodesData = (await nodesResponse.json()) as StakerNodesResponse

    // Setup promises for remaining data
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

    const latPromise = fetch(`${LAT_API_URL}/lat/${LIQUID_TOKEN_ADDRESS}?withTvl=true`).then((response) => {
        if (!response.ok) {
            throw new Error(`Failed to fetch LAT data: ${response.status} ${response.statusText}`)
        }
        return response.json()
    })

    // Fetch remaining data
    const [tokensData, operatorProspectStrategies, avsData, latData] = await Promise.all([
        tokenPromise,
        operatorInsightsPromise,
        avsPromise,
        latPromise
    ])

    return {
        nodesData,
        tokensData,
        operatorProspectStrategies,
        avsData,
        latData
    }
}

async function calculateOptimalAllocations(
    totalTvlBase: bigint,
    operatorProspectStrategies: OperatorProspectStrategy[],
    avsData: AvsResponse,
    quantum: bigint,
    tokenInfo: Map<string, TokenInfo>,
    baseAssetSymbol?: string
): Promise<AllocationResult[]> {
    if (operatorProspectStrategies.length === 0) {
        return []
    }

    const strategyOperators = new Map<string, OperatorAvsStrategyMetrics[]>()
    for (const ops of operatorProspectStrategies) {
        const strategyAddress = ops.operatorStrategy.strategyAddress.toLowerCase()

        if (!strategyOperators.has(strategyAddress)) {
            strategyOperators.set(strategyAddress, [])
        }
        strategyOperators.get(strategyAddress)?.push({
            operatorAddress: ops.operatorProspect.operatorAddress.toLowerCase(),
            bias: ops.operatorProspect.bias,
            baseApy: ops.operatorStrategy.baseApy,
            elApy: ops.operatorStrategy.elApy,
            feesBps: ops.operatorStrategy.feesBps,
            commonStakeApy: ops.commonStakeApy,
            operatorSetStakeApy: ops.operatorSetStakeApy,
            purityBps: ops.purityBps
        })
    }

    const strategyAddresses = Array.from(strategyOperators.keys())
    const { strategyCommonStakeTvlBase, strategyOperatorSetStakeTvlBase } = calculateStrategyTvlsBase(
        strategyAddresses,
        avsData,
        tokenInfo,
        baseAssetSymbol
    )

    // Calculate the optimal set of allocations
    const allocations: AllocationResult[] = []
    const steps = ceilDiv(totalTvlBase, quantum)

    // For every `quantum` of base asset, we find the best (strategy, operator) such that P is maximised
    // where P is the aggregate of purity, fees and APYs based on a specific weighting algorithm p
    // P is dependent on the tvl of the strategy, hence on every allocation of `quantum`, we need to re-evaluate the best (strategy, operator) pair
    for (let i = 0; i <= steps; i++) {
        const aTvlBase = i < steps ? quantum : totalTvlBase % quantum || quantum
        const maxP = 0
        let bestPair: { s: string; o: string } = { s: '', o: '' }

        for (const strategy of strategyAddresses) {
            const oasm = strategyOperators.get(strategy)
            const csTvlBase = strategyCommonStakeTvlBase.get(strategy) || 0
            const ossTvlBase = strategyOperatorSetStakeTvlBase.get(strategy) || 0
            if (oasm) {
                for (const o of oasm) {
                    if (p(strategy, o, allocations, quantum, csTvlBase, ossTvlBase) > maxP)
                        bestPair = { s: strategy, o: o.operatorAddress }
                }
            }
        }
        if (bestPair.o !== '' && bestPair.s !== '')
            allocations.push({
                strategyAddress: bestPair.s,
                operatorAddress: bestPair.o,
                aTvlBase
            })
    }

    return allocations
}

function p(
    strategy: string,
    metrics: OperatorAvsStrategyMetrics,
    allocations: AllocationResult[],
    quantum: bigint,
    commonStakeTvlBase: number,
    operatorSetStakeTvlBase: number // Unused for now
): number {
    const weights = {
        bias: 0.15,
        purity: 0.25,
        fees: 0.1,
        totalApy: 0.2
    }

    const bias = metrics.bias
    const purity = metrics.purityBps / 100
    const fees = metrics.feesBps / 100

    let allocatedTvlBase = 0
    for (const allocation of allocations) {
        if (allocation.strategyAddress.toLowerCase() === strategy.toLowerCase()) {
            allocatedTvlBase += Number(allocation.aTvlBase)
        }
    }

    const totalApy =
        metrics.baseApy +
        metrics.elApy +
        metrics.commonStakeApy * (commonStakeTvlBase / (commonStakeTvlBase + Number(quantum) + allocatedTvlBase)) // Dilution of APY given existing allocations and potentially new allocation

    return bias * weights.bias + purity * weights.purity + fees * weights.fees + totalApy * weights.totalApy
}

function constructPrefWarnActions(
    allocations: AllocationResult[],
    ops: OperatorProspectStrategy[]
): {
    apiUpdates: ApiUpdate[]
    strategyCategories: StrategyCategories
} {
    const apiUpdates: ApiUpdate[] = []
    const strategyCategories: StrategyCategories = {
        sev1Strategies: [],
        sev2Strategies: [],
        sev3Strategies: []
    }

    // Create a map for quick allocation lookup
    const allocationMap = new Map<string, bigint>()
    for (const allocation of allocations) {
        const key = `${allocation.strategyAddress}-${allocation.operatorAddress}`
        allocationMap.set(key, allocation.aTvlBase)
    }

    // Process each operator insight to determine pref/warn actions
    for (const o of ops) {
        const key = `${o.operatorStrategy.strategyAddress}-${o.operatorStrategy.operatorAddress}`
        const aTvlEth = allocationMap.get(key) || 0n

        let newDaysInPreference = o.operatorProspect.daysInPreference
        let newDaysInWarning = o.operatorProspect.daysInWarning || 0
        let newWarningSev = o.operatorProspect.warningSev

        if (aTvlEth === 0n) {
            // Strategy has no allocation -- reset preference and increase warning
            newDaysInPreference = 0

            if (newDaysInWarning >= MAX_DAYS_IN_WARN_SEV1) {
                newDaysInWarning++
                newWarningSev = 1
                if (!strategyCategories.sev1Strategies.includes(o.operatorStrategy.strategyAddress)) {
                    strategyCategories.sev1Strategies.push(o.operatorStrategy.strategyAddress)
                }
            } else if (newDaysInWarning >= MAX_DAYS_IN_WARN_SEV2) {
                newDaysInWarning++
                newWarningSev = 2
                if (!strategyCategories.sev2Strategies.includes(o.operatorStrategy.strategyAddress)) {
                    strategyCategories.sev2Strategies.push(o.operatorStrategy.strategyAddress)
                }
            } else {
                newDaysInWarning++
                newWarningSev = 3
                if (!strategyCategories.sev3Strategies.includes(o.operatorStrategy.strategyAddress)) {
                    strategyCategories.sev3Strategies.push(o.operatorStrategy.strategyAddress)
                }
            }
        } else {
            // Strategy has allocation -- reduce warning until zero then begin preference
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
            if (newDaysInPreference < MIN_DAYS_IN_PREF && newWarningSev === null) {
                newDaysInPreference++
            }
        }

        // Only create an update if something changed
        if (
            newDaysInPreference !== o.operatorProspect.daysInPreference ||
            newDaysInWarning !== (o.operatorProspect.daysInWarning || 0) ||
            newWarningSev !== o.operatorProspect.warningSev
        ) {
            apiUpdates.push({
                id: o.operatorProspect.id,
                daysInPreference: newDaysInPreference,
                daysInWarning: newDaysInWarning,
                warningSev: newWarningSev
            })
        }
    }

    return { apiUpdates, strategyCategories }
}

function constructNodeAllocations(
    stakerNodes: StakerNode[],
    allocations: AllocationResult[],
    assetsAvailable: Map<string, bigint>,
    tokenInfo: Map<string, TokenInfo>
) {
    const nodeAllocations: NodeAllocationWithSwap[] = []

    const allocationMap = new Map<string, AllocationResult>()
    for (const allocation of allocations) {
        allocationMap.set(allocation.strategyAddress, allocation)
    }

    for (const node of stakerNodes) {
        const assetsToSwap: string[] = []
        const amountsToSwap: bigint[] = []
        const assetsToStake: string[] = []

        // Process each asset in the node
        for (const asset of node.assets) {
            const strategyAddress = asset.strategy
            const allocation = allocationMap.get(strategyAddress)

            if (!allocation) {
                continue // Skip if no allocation found for this strategy
            }

            // Find token info for this strategy
            let tokenAddress = ''
            let tokenDecimals = 18
            let pricePerUnit = '1'

            for (const [address, info] of tokenInfo) {
                if (info.strategyAddress === strategyAddress) {
                    tokenAddress = address
                    tokenDecimals = info.decimals
                    pricePerUnit = info.pricePerUnit
                    break
                }
            }

            if (!tokenAddress) {
                continue // Skip if no token info found
            }

            // Check available amount for this token
            const availableAmount = assetsAvailable.get(tokenAddress) || 0n

            if (availableAmount > 0n) {
                // Calculate required amount based on `aTvlBase`
                const price = BigInt(Math.floor(Number(pricePerUnit) * 10 ** tokenDecimals))
                const requiredAmount = (allocation.aTvlBase * BigInt(10 ** tokenDecimals)) / price

                // Determine amount to swap (min of available and required)
                const amountToSwap = availableAmount < requiredAmount ? availableAmount : requiredAmount

                if (amountToSwap > 0n) {
                    assetsToSwap.push(tokenAddress)
                    amountsToSwap.push(amountToSwap)
                    assetsToStake.push(strategyAddress)
                }
            }
        }

        if (assetsToSwap.length > 0) {
            nodeAllocations.push({
                nodeId: node.nodeId,
                assetsToSwap,
                amountsToSwap,
                assetsToStake
            })
        }
    }

    return nodeAllocations
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

async function calcTvlBaseFromNative(assets: string[], amounts: string[], tokenInfo: Map<string, TokenInfo>) {
    let totalTvlBase = 0n

    for (let i = 0; i < assets.length; i++) {
        const assetAddress = assets[i].toLowerCase()
        const amount = BigInt(amounts[i])
        const token = tokenInfo.get(assetAddress)

        if (!token) {
            continue
        }

        // `pricePerUnit` is price of 1 token in base asset terms
        const pricePerUnit = BigInt(Math.floor(Number(token.pricePerUnit) * 10 ** token.decimals))
        const tvlBase = (amount * pricePerUnit) / BigInt(10 ** token.decimals)

        totalTvlBase += tvlBase
    }

    return totalTvlBase
}

function calculateStrategyTvlsBase(
    strategies: string[],
    avsData: AvsResponse,
    tokenInfo: Map<string, TokenInfo>,
    baseAssetSymbol?: string
) {
    if (!baseAssetSymbol) throw new Error('Unknown base asset')

    const strategyCommonStakeTvlBase = new Map<string, number>()
    const strategyOperatorSetStakeTvlBase = new Map<string, number>()

    for (const strategy of strategies) {
        let strategySymbol = ''
        for (const [, token] of tokenInfo) {
            if (token.strategyAddress.toLowerCase() === strategy.toLowerCase()) {
                strategySymbol = token.symbol
                break
            }
        }

        if (!strategySymbol) {
            continue
        }

        const tvlEth = avsData.tvl.tvlStrategiesEth[strategySymbol] || 0
        let tvlBase = 0

        if (baseAssetSymbol === 'ETH') {
            tvlBase = tvlEth
        } else {
            // Convert to base asset terms
            const baseToken = Array.from(tokenInfo.values()).find((t) => t.symbol === baseAssetSymbol)
            if (baseToken) {
                tvlBase = tvlEth / Number(baseToken.pricePerUnit)
            }
        }

        if (tvlBase) strategyCommonStakeTvlBase.set(strategy, tvlBase)
        strategyOperatorSetStakeTvlBase.set(strategy, 0) // TODO
    }

    return { strategyCommonStakeTvlBase, strategyOperatorSetStakeTvlBase }
}

// Returns 1 ETH worth of base asset
function getQuantum(latData: LatResponse, baseAssetSymbol?: string) {
    if (!baseAssetSymbol) throw new Error('Unknown base asset')

    return latData.tvl.tvlAssetsBase
        ? BigInt(latData.tvl.tvlAssetsBase[baseAssetSymbol] / latData.tvl.tvlAssetsEth[baseAssetSymbol])
        : 1n
}

function ceilDiv(dividend: bigint, divisor: bigint): number {
    return Number((dividend + divisor - 1n) / divisor)
}
