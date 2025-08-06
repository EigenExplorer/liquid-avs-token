import { getPendingProposals, isContractOurs, LIQUID_TOKEN_ADDRESS, AVS_ADDRESS } from '../utils/forge'
import { type NodeAllocation, stakeAssetsToNodes } from '../tasks/stakeAssetsToNodes'
import { sharesToTvl } from '../utils/strategyShares'

// --- Types ---

interface LatResponse {
    address: string
    baseAsset: string
    assets: { asset: string; balance: string }[]
    tvl: {
        tvlAssetsEth: Record<string, number>
        tvlAssetsBase?: Record<string, number>
    }
}

export interface TokenInfo {
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
        asset: string
        strategy: string
        stakedAmount: string
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

interface UserWithdrawal {
    requestId: string
    user: string
    assets: string[]
    requestedElShares: string[]
    sharedDeposited: string[]
}

interface UserWithdrawalsResponse {
    data: UserWithdrawal[]
    meta: {
        count: number
        skip: number
        take: number
    }
}

interface OptimalAllocation {
    strategyAddress: string
    operatorAddress: string
    aTvlBase: bigint
}

interface ApiUpdate {
    id: number
    daysInPreference: number
    daysInWarning: number
    warningSev: number | null
}

interface UserWithdrawalsSettlement {
    requestIds: string[]
    ltAssets: string[]
    ltAmounts: string[]
    nodeIds: number[]
    elAssets: string[][]
    elAmounts: string[][]
}

interface NodeAllocationWithSwap {
    nodeId: number
    assetsToSwap: string[]
    amountsToSwap: bigint[]
    assetsToStake: string[]
}

interface NodeWithdrawals {
    nodeIds: number[]
    assets: string[][]
    amounts: string[][]
}

// --- Constants ---

const LAT_API_URL = process.env.LAT_API_URL
const LAT_API_TOKEN = process.env.LAT_API_TOKEN
const EE_API_URL = process.env.EE_API_URL
const EE_API_TOKEN = process.env.EE_API_TOKEN

const MIN_DAYS_IN_PREF = 3
const MAX_DAYS_IN_WARN_SEV3 = 7
const MAX_DAYS_IN_WARN_SEV2 = MAX_DAYS_IN_WARN_SEV3 + 7
const MAX_DAYS_IN_WARN_SEV1 = MAX_DAYS_IN_WARN_SEV2 + 7

// --- Core functions ---

/**
 * Workflow for staking unstaked assets in the `LiquidToken` contract across nodes
 *
 * @returns
 */
export async function stakeUnstakedAssets() {
    try {
        // Bail early if the multisig has any pending proposals for this LAT
        const pendingProposals = await getPendingProposals()
        for (const proposal of pendingProposals) {
            if (isContractOurs(proposal.to.toLowerCase())) {
                throw new Error(
                    `Cannot execute workflow due to existing pending tx for this LAT at nonce ${proposal.nonce}`
                )
            }
        }

        // Gather required data
        const {
            operatorProspectStrategies,
            avsData,
            userWithdrawals,
            tokenInfo,
            baseAssetSymbol,
            quantum,
            withdrawalAmounts,
            restakeableTvlBase,
            delegatedNodes,
            unstakedAssetsAvailable
        } = await fetchLatState()

        // We want to accomplish the following whilst maximising P = p(total apy, avs purity, operator bias, operator fees):
        //
        //   Action i    -  allocate funds (unstaked / staked only if required) for user withdrawals
        //   Action ii   -  allocate remaining funds to nodes for staking
        //   Action iii  -  evaluate every (OperatorProspect, Strategy) pair on their contribution to P and send relevant API updates
        //   Action iv   -  if any (OperatorProspect, Strategy) pair has been underperforming for >= `MAX_DAYS_IN_WARN_SEV1` days, call for EL withdrawals from corresponding node(s)
        //
        // where P represents a system-wide weighted aggregate of the params, with each param weighted by their relative importance

        // Action i
        // Construct the withdrawal settlement object and the amounts of unstaked funds remaining for deposits
        const { withdrawalSettlement, remainingUnstakedAssetsAvailable } = constructUserWithdrawalSettlement(
            userWithdrawals,
            // Maximise system-wide P by calling for withdrawals on the (OperatorProspect, Strategy) pairs in ascending order of P
            (
                await calculateOptimalAllocations(
                    restakeableTvlBase,
                    // Each OperatorProspect should be delegated
                    operatorProspectStrategies.data.filter((ops) => {
                        return ops.operatorProspect.isDelegated
                    }),
                    avsData,
                    quantum,
                    tokenInfo,
                    baseAssetSymbol
                )
            ).reverse(),
            delegatedNodes,
            unstakedAssetsAvailable,
            withdrawalAmounts,
            tokenInfo
        )
        // TODO: if (withdrawalSettlement) await settleUserWithdrawals(withdrawalSettlement)

        // Action ii
        // Construct node allocations for staking from the remaining deposits available after settling withdrawals
        const optimalAllocations = // Maximise system-wide P by allocating deposits on the (OperatorProspect, Strategy) pairs in descending order of P
            await calculateOptimalAllocations(
                restakeableTvlBase,
                operatorProspectStrategies.data.filter((ops) => {
                    // The OperatorProspect should be delegated but not in warning
                    // If in warning, but biased, we allow it
                    const operatorProspect = ops.operatorProspect
                    const operatorProspectQualified =
                        operatorProspect.isDelegated &&
                        (operatorProspect.warningSev === null ||
                            operatorProspect.warningSev === 0 ||
                            operatorProspect.bias > 0)

                    // The OperatorProspectStrategy should not be in warning and also should have been in pref for at least `MIN_DAYS_IN_PREF`
                    // If this is the first time that the strategy is being evaluated (strategy restaked tvl is 0), then we forgo the `MIN_DAYS_IN_PREF` requirement
                    const strategyGenesis = !delegatedNodes.some((n) =>
                        n.assets.map(
                            (a) => a.strategy.toLowerCase() === ops.operatorStrategy.strategyAddress.toLowerCase()
                        )
                    )
                    const strategyQualified =
                        (ops.warningSev === null || ops.warningSev === 0) &&
                        (ops.daysInPreference >= MIN_DAYS_IN_PREF || strategyGenesis)

                    return operatorProspectQualified && strategyQualified
                }),
                avsData,
                quantum,
                tokenInfo,
                baseAssetSymbol
            )
        const nodeAllocations = constructNodeAllocations(
            delegatedNodes,
            optimalAllocations,
            remainingUnstakedAssetsAvailable,
            tokenInfo
        )
        // TODO: if (nodeAllocations.length) await swapAndStakeAssetsToNodes(nodeAllocations)

        // Action iii
        // Construct API updates for underperforming (OperatorProspect, Strategy) pairs and return the pairs that need to be retired
        const eligibleOps = operatorProspectStrategies.data.filter((ops) => {
            // The OperatorProspect should be delegated and not be in warning
            // If in warning, but biased, we allow it
            return (
                ops.operatorProspect.isDelegated &&
                (ops.operatorProspect.warningSev === null ||
                    ops.operatorProspect.warningSev === 0 ||
                    ops.operatorProspect.bias > 0)
            )
        })
        const { apiUpdates, opsToRetire } = constructPrefWarnActions(
            await calculateOptimalAllocations(
                restakeableTvlBase,
                eligibleOps,
                avsData,
                quantum,
                tokenInfo,
                baseAssetSymbol
            ),
            eligibleOps
        )
        await sendApiUpdates(apiUpdates)

        // Action iv
        // Construct node withdrawals for portfolio rebalancing for all `opsToRetire` items that do not have an allocation for deposit
        const nodeWithdrawals = constructNodeWithdrawals(
            opsToRetire.filter(
                (op) =>
                    !optimalAllocations.some(
                        (allocation) =>
                            allocation.operatorAddress === op.operatorStrategy.operatorAddress &&
                            allocation.strategyAddress === op.operatorStrategy.strategyAddress
                    )
            ),
            delegatedNodes
        )
        // TODO: if (nodeWithdrawals.length) await withdrawNodeAssets(nodeWithdrawals)

        console.log('[Manager] Stake unstaked assets complete')
    } catch (error) {
        console.log('[Manager] Error: ', error.message)
        throw error
    }
}

// --- Helper functions ---

/**
 * Structures and returns all relevant data from EE & LAT APIs
 *
 * @returns
 */
async function fetchLatState(): Promise<{
    operatorProspectStrategies: OperatorInsightsResponse
    avsData: AvsResponse
    userWithdrawals: UserWithdrawal[]
    tokenInfo: Map<string, TokenInfo>
    baseAssetSymbol: string | undefined
    quantum: bigint
    withdrawalAmounts: Map<string, bigint>
    restakeableTvlBase: bigint
    delegatedNodes: StakerNode[]
    unstakedAssetsAvailable: Map<string, bigint>
}> {
    // Fetch all data with promises
    const nodesPromise = fetch(`${LAT_API_URL}/lat/${LIQUID_TOKEN_ADDRESS}/staker-nodes`).then((response) => {
        if (!response.ok) {
            throw new Error(`Failed to fetch staker nodes: ${response.status} ${response.statusText}`)
        }
        return response.json()
    })

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

    const userWithdrawalsPromise = (async (): Promise<UserWithdrawalsResponse> => {
        const allWithdrawals: UserWithdrawal[] = []
        let skip = 0
        const take = 100

        while (true) {
            const response = await fetch(
                `${LAT_API_URL}/lat/${LIQUID_TOKEN_ADDRESS}/user-withdrawals?redemption=pending&skip=${skip}&take=${take}`
            )

            if (!response.ok) {
                throw new Error(`Failed to fetch user withdrawals: ${response.status} ${response.statusText}`)
            }

            const data = (await response.json()) as UserWithdrawalsResponse
            allWithdrawals.push(...data.data)

            // If we got less than `take` results, we've fetched all available data
            if (data.data.length < take) {
                break
            }

            skip += take
        }

        return {
            data: allWithdrawals,
            meta: {
                count: allWithdrawals.length,
                skip: 0,
                take: allWithdrawals.length
            }
        }
    })()

    const [nodesData, tokensData, operatorProspectStrategies, avsData, latData, userWithdrawalsData] =
        await Promise.all([
            nodesPromise,
            tokenPromise,
            operatorInsightsPromise,
            avsPromise,
            latPromise,
            userWithdrawalsPromise
        ])

    // Compute derived vars
    const tokenInfo = new Map(
        (tokensData as TokensResponse).data.map((token: TokenInfo) => [token.address.toLowerCase(), token])
    )
    const baseAssetSymbol = tokenInfo.get((latData as LatResponse).baseAsset.toLowerCase())?.symbol
    const quantum = getQuantum(latData as LatResponse, baseAssetSymbol)

    const unstakedTvlBase = await calcTvlBaseFromNative(
        (latData as LatResponse).assets.map((ua) => ua.asset.toLowerCase()),
        (latData as LatResponse).assets.map((ua) => ua.balance),
        tokenInfo
    )

    const withdrawalAmounts = await getWithdrawalAmounts(userWithdrawalsData.data, tokenInfo)
    const withdrawalTvlBase = await calcTvlBaseFromNative(
        Array.from(withdrawalAmounts.keys()),
        Array.from(withdrawalAmounts.values().map((value) => value.toString())),
        tokenInfo
    )
    const restakeableTvlBase = unstakedTvlBase > withdrawalTvlBase ? unstakedTvlBase - withdrawalTvlBase : 0n

    const delegatedNodes = (nodesData as StakerNodesResponse).stakerNodes.filter(
        (node) => node.operatorDelegation !== '0x0000000000000000000000000000000000000000'
    )

    const unstakedAssetsAvailable = new Map<string, bigint>()
    for (const asset of (latData as LatResponse).assets) {
        unstakedAssetsAvailable.set(asset.asset.toLowerCase(), BigInt(asset.balance))
    }

    return {
        operatorProspectStrategies,
        avsData,
        userWithdrawals: userWithdrawalsData.data,
        tokenInfo,
        baseAssetSymbol,
        quantum,
        withdrawalAmounts,
        restakeableTvlBase,
        delegatedNodes,
        unstakedAssetsAvailable
    }
}

/**
 * For a given set of withdrawal requests, returns a mapping of assets to the total amount required to be withdrawn
 * Note: The withdrawal requests store the EL shares of the asset and need to be converted to is native terms
 *
 * @param userWithdrawals
 * @param tokenInfo
 * @returns
 */
async function getWithdrawalAmounts(userWithdrawals: UserWithdrawal[], tokenInfo: Map<string, TokenInfo>) {
    const assetShares = new Map<string, bigint>()

    for (const withdrawal of userWithdrawals) {
        for (let i = 0; i < withdrawal.assets.length; i++) {
            const address = tokenInfo.get(withdrawal.assets[i])?.address
            const sharesRequested = BigInt(withdrawal.requestedElShares[i])

            if (address) {
                const existingAmount = assetShares.get(address) || 0n
                assetShares.set(address, existingAmount + sharesRequested)
            }
        }
    }

    return await sharesToTvl(assetShares, tokenInfo)
}

/**
 * For a given set of withdrawal requests, and (OperatorProspect, Strategy) pairs in asc order of P
 * constructs the the allocation of unstaked and staked (only if required) funds
 *
 * @param userWithdrawals
 * @param optimalWithdrawals
 * @param stakerNodes
 * @param unstakedAssetsAvailable
 * @param requestedWithdrawalAmounts
 * @param tokenInfo
 * @returns
 */
function constructUserWithdrawalSettlement(
    userWithdrawals: UserWithdrawal[],
    optimalWithdrawals: OptimalAllocation[],
    stakerNodes: StakerNode[],
    unstakedAssetsAvailable: Map<string, bigint>,
    requestedWithdrawalAmounts: Map<string, bigint>,
    tokenInfo: Map<string, TokenInfo>
) {
    const withdrawalSettlement: UserWithdrawalsSettlement = {
        requestIds: [],
        ltAssets: [],
        ltAmounts: [],
        nodeIds: [],
        elAssets: [],
        elAmounts: []
    }

    const remainingUnstakedAssetsAvailable = new Map<string, bigint>()
    for (const [asset, amount] of unstakedAssetsAvailable) {
        remainingUnstakedAssetsAvailable.set(asset, amount)
    }

    // Track how much of each asset we can fulfill (unstaked + staked) for each asset and filter out unfulfillable requests
    // The only reason for lack of funds would be because of pending withdrawals for node rebalancing or undelegation
    const assetFulfillmentCapacity = new Map<string, bigint>()
    for (const [assetAddress] of requestedWithdrawalAmounts) {
        const unstakedAmount = remainingUnstakedAssetsAvailable.get(assetAddress) || 0n

        let stakedAmount = 0n
        const token = tokenInfo.get(assetAddress)
        if (token) {
            const strategyAddress = token.strategyAddress.toLowerCase()

            for (const node of stakerNodes) {
                const nodeAsset = node.assets.find(
                    (a) => a.strategy.toLowerCase() === strategyAddress && a.asset.toLowerCase() === assetAddress
                )
                if (nodeAsset) {
                    stakedAmount += BigInt(nodeAsset.stakedAmount)
                }
            }
        }

        assetFulfillmentCapacity.set(assetAddress, unstakedAmount + stakedAmount)
    }

    const fulfillableRequestIds = new Set<string>()
    for (const withdrawal of userWithdrawals) {
        let isFulfillable = true

        for (let i = 0; i < withdrawal.assets.length; i++) {
            const assetAddress = withdrawal.assets[i].toLowerCase()
            const requestedAmount = BigInt(withdrawal.requestedElShares[i])
            const capacity = assetFulfillmentCapacity.get(assetAddress) || 0n

            if (capacity < requestedAmount) {
                isFulfillable = false
                break
            }
        }

        if (isFulfillable) {
            fulfillableRequestIds.add(withdrawal.requestId)

            // Reduce capacity for these assets
            for (let i = 0; i < withdrawal.assets.length; i++) {
                const assetAddress = withdrawal.assets[i].toLowerCase()
                const requestedAmount = BigInt(withdrawal.requestedElShares[i])
                const currentCapacity = assetFulfillmentCapacity.get(assetAddress) || 0n
                assetFulfillmentCapacity.set(assetAddress, currentCapacity - requestedAmount)
            }
        }
    }

    const fulfillableWithdrawals = userWithdrawals.filter((w) => fulfillableRequestIds.has(w.requestId))
    withdrawalSettlement.requestIds = fulfillableWithdrawals.map((w) => w.requestId)

    // Recalculate requested amounts based on fulfillable requests only
    const fulfillableWithdrawalAmounts = new Map<string, bigint>()
    for (const withdrawal of fulfillableWithdrawals) {
        for (let i = 0; i < withdrawal.assets.length; i++) {
            const assetAddress = withdrawal.assets[i].toLowerCase()
            const requestedAmount = BigInt(withdrawal.requestedElShares[i])
            const existingAmount = fulfillableWithdrawalAmounts.get(assetAddress) || 0n
            fulfillableWithdrawalAmounts.set(assetAddress, existingAmount + requestedAmount)
        }
    }

    // Allocate withdrawals from unstaked assets
    const remainingWithdrawalAmounts = new Map<string, bigint>()
    for (const [assetAddress, totalRequestedAmount] of fulfillableWithdrawalAmounts) {
        const availableAmount = remainingUnstakedAssetsAvailable.get(assetAddress) || 0n
        const amountToFulfillFromUnstaked =
            availableAmount < totalRequestedAmount ? availableAmount : totalRequestedAmount

        if (amountToFulfillFromUnstaked > 0n) {
            withdrawalSettlement.ltAssets.push(assetAddress)
            withdrawalSettlement.ltAmounts.push(amountToFulfillFromUnstaked.toString())

            remainingUnstakedAssetsAvailable.set(assetAddress, availableAmount - amountToFulfillFromUnstaked)
        }

        // Track remaining amount that needs to be fulfilled from staked assets
        const remainingAmount = totalRequestedAmount - amountToFulfillFromUnstaked
        if (remainingAmount > 0n) {
            remainingWithdrawalAmounts.set(assetAddress, remainingAmount)
        }
    }

    // For the remainder, allocate from nodes' staked assets
    const strategyWithdrawalOrder = new Map<string, string[]>()
    for (const withdrawal of optimalWithdrawals) {
        const strategy = withdrawal.strategyAddress.toLowerCase()
        if (!strategyWithdrawalOrder.has(strategy)) {
            strategyWithdrawalOrder.set(strategy, [])
        }
        const operators = strategyWithdrawalOrder.get(strategy)
        if (operators && !operators.includes(withdrawal.operatorAddress.toLowerCase())) {
            operators.push(withdrawal.operatorAddress.toLowerCase())
        }
    }

    const operatorToNodes = new Map<string, StakerNode[]>()
    for (const node of stakerNodes) {
        const operatorAddress = node.operatorDelegation.toLowerCase()
        if (!operatorToNodes.has(operatorAddress)) {
            operatorToNodes.set(operatorAddress, [])
        }
        operatorToNodes.get(operatorAddress)?.push(node)
    }

    // Process remaining withdrawal amounts from staked assets
    for (const [assetAddress, remainingAmount] of remainingWithdrawalAmounts) {
        const token = tokenInfo.get(assetAddress)
        if (!token) continue

        const strategyAddress = token.strategyAddress.toLowerCase()
        const operatorsInOrder = strategyWithdrawalOrder.get(strategyAddress) || []

        let amountStillNeeded = remainingAmount

        for (const operatorAddress of operatorsInOrder) {
            if (amountStillNeeded <= 0n) break

            const nodes = operatorToNodes.get(operatorAddress) || []

            for (const node of nodes) {
                if (amountStillNeeded <= 0n) break

                const nodeAsset = node.assets.find(
                    (a) => a.strategy.toLowerCase() === strategyAddress && a.asset.toLowerCase() === assetAddress
                )

                if (nodeAsset && BigInt(nodeAsset.stakedAmount) > 0n) {
                    const stakedAmount = BigInt(nodeAsset.stakedAmount)
                    const amountToWithdraw = stakedAmount < amountStillNeeded ? stakedAmount : amountStillNeeded

                    const existingNodeIndex = withdrawalSettlement.nodeIds.indexOf(node.nodeId)

                    if (existingNodeIndex >= 0) {
                        withdrawalSettlement.elAssets[existingNodeIndex].push(assetAddress)
                        withdrawalSettlement.elAmounts[existingNodeIndex].push(amountToWithdraw.toString())
                    } else {
                        withdrawalSettlement.nodeIds.push(node.nodeId)
                        withdrawalSettlement.elAssets.push([assetAddress])
                        withdrawalSettlement.elAmounts.push([amountToWithdraw.toString()])
                    }

                    amountStillNeeded -= amountToWithdraw
                }
            }
        }
    }

    return { withdrawalSettlement, remainingUnstakedAssetsAvailable }
}

/**
 * For a given set of assets avilable to stake, and ideal ((OperatorProspect, Strategy), TVL) pairs in desc order of P
 * computes the swaps required and constructs the final allocations to corresponding staker nodes
 *
 * @param stakerNodes
 * @param allocations
 * @param assetsAvailable
 * @param tokenInfo
 * @returns
 */
function constructNodeAllocations(
    stakerNodes: StakerNode[],
    allocations: OptimalAllocation[],
    assetsAvailable: Map<string, bigint>,
    tokenInfo: Map<string, TokenInfo>
) {
    const nodeAllocations: NodeAllocationWithSwap[] = []

    const allocationMap = new Map<string, OptimalAllocation>()
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

/**
 * For a given set of (OperatorProspect, Strategy) pairs and the total TVL to be allocated,
 * returns a list of ((OperatorProspect, Strategy), TVL) maximising system-wide P
 *
 * @param totalTvlBase
 * @param operatorProspectStrategies
 * @param avsData
 * @param quantum
 * @param tokenInfo
 * @param baseAssetSymbol
 * @returns
 */
async function calculateOptimalAllocations(
    totalTvlBase: bigint,
    operatorProspectStrategies: OperatorProspectStrategy[],
    avsData: AvsResponse,
    quantum: bigint,
    tokenInfo: Map<string, TokenInfo>,
    baseAssetSymbol?: string
): Promise<OptimalAllocation[]> {
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
    const allocations: OptimalAllocation[] = []
    const steps = Number((totalTvlBase + quantum - 1n) / quantum)

    // For every `quantum` of base asset, we find the best (strategy, operator) such that P is maximised
    // P is dependent on the tvl of the strategy, hence on every allocation of `quantum`, we need to re-evaluate the best (OperatorProspect, Strategy) pair
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

/**
 * For a given set of optimal allocations and (OperatorProspect, Strategy) pairs, asses if any pair
 * requires to incr/decr/reset warning or pref days and also returns pairs that have been warned for too
 * long and need to be retired
 *
 * @param allocations
 * @param ops
 * @returns
 */
function constructPrefWarnActions(allocations: OptimalAllocation[], ops: OperatorProspectStrategy[]) {
    const apiUpdates: ApiUpdate[] = []
    const opsToRetire: OperatorProspectStrategy[] = []

    const allocationMap = new Map<string, bigint>()
    for (const allocation of allocations) {
        const key = `${allocation.strategyAddress}-${allocation.operatorAddress}`
        allocationMap.set(key, allocation.aTvlBase)
    }

    // Process each OperatorProspectStrategy to determine pref/warn actions
    for (const o of ops) {
        const key = `${o.operatorStrategy.strategyAddress}-${o.operatorStrategy.operatorAddress}`
        const aTvlEth = allocationMap.get(key) || 0n

        let newDaysInPreference = o.operatorProspect.daysInPreference
        let newDaysInWarning = o.operatorProspect.daysInWarning || 0
        let newWarningSev = o.operatorProspect.warningSev

        if (aTvlEth === 0n) {
            // Strategy has no allocation -- reset preference and increase warning
            newDaysInPreference = 0

            if (newDaysInWarning >= MAX_DAYS_IN_WARN_SEV2) {
                newDaysInWarning++
                newWarningSev = 1
                if (newDaysInWarning > MAX_DAYS_IN_WARN_SEV1) opsToRetire.push(o)
            } else if (newDaysInWarning >= MAX_DAYS_IN_WARN_SEV3) {
                newDaysInWarning++
                newWarningSev = 2
            } else {
                newDaysInWarning++
                newWarningSev = 3
            }
        } else {
            // Strategy has allocation -- reduce warning until zero then begin preference
            if (newDaysInWarning > 0) {
                newDaysInWarning--

                if (newDaysInWarning >= MAX_DAYS_IN_WARN_SEV2) {
                    newWarningSev = 1
                } else if (newDaysInWarning >= MAX_DAYS_IN_WARN_SEV3) {
                    newWarningSev = 2
                } else if (newDaysInWarning > 0) {
                    newWarningSev = 3
                } else {
                    // Days in warning reached 0
                    newWarningSev = null
                }
            } else if (newWarningSev !== null) {
                // Clear warning if no warning days left
                newWarningSev = null
            }

            // Handle pref
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

    return { apiUpdates, opsToRetire }
}

/**
 * For a given set of (OperatorProspect, Strategy) pairs that are to be retired, returns a set of
 * corresponding nodes and the entire staked balance
 *
 * @param opsToRetire
 * @param stakerNodes
 * @returns
 */
function constructNodeWithdrawals(opsToRetire: OperatorProspectStrategy[], stakerNodes: StakerNode[]): NodeWithdrawals {
    const nodeWithdrawals: NodeWithdrawals = {
        nodeIds: [],
        assets: [],
        amounts: []
    }

    const operatorStrategies = new Map<string, Set<string>>()
    for (const ops of opsToRetire) {
        const operatorAddress = ops.operatorStrategy.operatorAddress.toLowerCase()
        if (!operatorStrategies.has(operatorAddress)) {
            operatorStrategies.set(operatorAddress, new Set())
        }
        operatorStrategies.get(operatorAddress)?.add(ops.operatorStrategy.strategyAddress.toLowerCase())
    }

    // Find nodes delegated to operators that need to be retired
    for (const node of stakerNodes) {
        const operatorAddress = node.operatorDelegation.toLowerCase()
        const strategiesToRetire = operatorStrategies.get(operatorAddress)

        if (strategiesToRetire && strategiesToRetire.size > 0) {
            const assetsToWithdraw: string[] = []
            const amountsToWithdraw: string[] = []

            // Check each asset in the node
            for (const asset of node.assets) {
                const strategyAddress = asset.strategy.toLowerCase()

                // If this strategy should be retired from this operator
                if (strategiesToRetire.has(strategyAddress)) {
                    const stakedAmount = BigInt(asset.stakedAmount)

                    if (stakedAmount > 0n) {
                        assetsToWithdraw.push(asset.asset.toLowerCase())
                        amountsToWithdraw.push(stakedAmount.toString())
                    }
                }
            }

            // Only add the node if there are assets to withdraw
            if (assetsToWithdraw.length > 0) {
                nodeWithdrawals.nodeIds.push(node.nodeId)
                nodeWithdrawals.assets.push(assetsToWithdraw)
                nodeWithdrawals.amounts.push(amountsToWithdraw)
            }
        }
    }

    return nodeWithdrawals
}

/**
 * Send a POST update to the LAT API to update the state of a set of `OperatorProspectStrategy` items
 * to update their warn/pref fields
 *
 * @param apiUpdates
 * @returns
 */
async function sendApiUpdates(apiUpdates: ApiUpdate[]): Promise<void> {
    if (apiUpdates.length === 0) {
        console.log('[Manager] No API updates needed')
        return
    }

    const response = await fetch(`${LAT_API_URL}/lat/${LIQUID_TOKEN_ADDRESS}/operator-prospects/batch-update`, {
        method: 'POST',
        headers: {
            'Content-Type': 'application/json',
            'X-API-Token': `${LAT_API_TOKEN}`
        },
        body: JSON.stringify({ updates: apiUpdates })
    })

    if (!response.ok) {
        throw new Error(`Failed to send API updates: ${response.status} ${response.statusText}`)
    }

    console.log(`[Manager] Successfully sent ${apiUpdates.length} API updates`)
}

// --- Utility functions ---

/**
 * For a given set of assets and amounts, returns the TVL amount in the base token of the LAT
 *
 * @param assets
 * @param amounts
 * @param tokenInfo
 * @returns
 */
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

/**
 * For a given set of Strategies, returns the AVS TVL in the base token of the LAT
 *
 * @param strategies
 * @param avsData
 * @param tokenInfo
 * @param baseAssetSymbol
 * @returns
 */
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
        strategyOperatorSetStakeTvlBase.set(strategy, 0) // TODO after API Slashing upgrade
    }

    return { strategyCommonStakeTvlBase, strategyOperatorSetStakeTvlBase }
}

/**
 * Function to maximize to achieve the business goals of the LAT
 *
 * @param strategy
 * @param metrics
 * @param allocations
 * @param quantum
 * @param commonStakeTvlBase
 * @param operatorSetStakeTvlBase
 * @returns
 */
function p(
    strategy: string,
    metrics: OperatorAvsStrategyMetrics,
    allocations: OptimalAllocation[],
    quantum: bigint,
    commonStakeTvlBase: number,
    operatorSetStakeTvlBase: number // TODO after API Slashing upgrade
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

/**
 * Returns 1 ETH worth of any LAT base asset
 *
 * @param latData
 * @param baseAssetSymbol
 * @returns
 */
function getQuantum(latData: LatResponse, baseAssetSymbol?: string) {
    if (!baseAssetSymbol) throw new Error('Unknown base asset')

    return latData.tvl.tvlAssetsBase
        ? BigInt(latData.tvl.tvlAssetsBase[baseAssetSymbol] / latData.tvl.tvlAssetsEth[baseAssetSymbol])
        : 1n
}
