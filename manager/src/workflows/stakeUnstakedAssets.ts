import { getPendingProposals, isContractOurs, LIQUID_TOKEN_ADDRESS } from '../utils/forge'
import { type NodeAllocation, stakeAssetsToNodes } from '../tasks/stakeAssetsToNodes'

interface LATResponse {
    address: string
    assets: { asset: string; balance: string; queuedBalance: string }[]
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
        address: string
        nodeId: number
        operatorDelegation: string
        assets: {
            asset: string
        }[]
    }[]
}

const LAT_API_URL = process.env.LAT_API_URL
const EE_API_URL = process.env.EE_API_URL
const EE_API_TOKEN = process.env.EE_API_TOKEN

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

        // LAT API: Fetch unstaked assets and amounts
        const latResponse = await fetch(`${LAT_API_URL}/lat/${LIQUID_TOKEN_ADDRESS}`)

        if (!latResponse.ok) {
            throw new Error(`Failed to fetch LAT data: ${latResponse.status} ${latResponse.statusText}`)
        }

        const latData = (await latResponse.json()) as LATResponse
        const unstakedAssets = latData.assets

        // LAT API: Fetch nodes and their delegations
        const nodesResponse = await fetch(`${LAT_API_URL}/lat/${LIQUID_TOKEN_ADDRESS}/staker-nodes`)

        if (!nodesResponse.ok) {
            throw new Error(`Failed to fetch staker nodes: ${nodesResponse.status} ${nodesResponse.statusText}`)
        }

        const nodesData = (await nodesResponse.json()) as StakerNodesResponse
        const nodes = nodesData.stakerNodes

        // Filter out nodes that are not delegated
        const delegatedNodes = nodes.filter(
            (node) => node.operatorDelegation !== '0x0000000000000000000000000000000000000000'
        )

        if (delegatedNodes.length === 0) {
            console.log('[Manager][Warning] No delegated nodes found. Skipping workflow...')
            return []
        }

        // LAT API: Fetch token data
        const tokensResponse = await fetch(`${LAT_API_URL}/lat/${LIQUID_TOKEN_ADDRESS}/tokens`)

        if (!tokensResponse.ok) {
            throw new Error(`Failed to fetch token data: ${tokensResponse.status} ${tokensResponse.statusText}`)
        }

        const tokensData = (await tokensResponse.json()) as TokensResponse
        const tokenInfoMap = new Map(tokensData.data.map((token) => [token.address.toLowerCase(), token]))

        // EE API: Fetch strategies restaked by each Operator
        const operatorAddresses = delegatedNodes.map((node) => node.operatorDelegation.toLowerCase())
        const operatorStrategiesData = await Promise.all(
            operatorAddresses.map(async (operatorAddress) => {
                const operatorResponse = await fetch(`${EE_API_URL}/operators/${operatorAddress}`, {
                    headers: {
                        'X-API-Token': `${process.env.EE_API_TOKEN}`
                    }
                })

                if (!operatorResponse.ok) {
                    throw new Error(
                        `Failed to fetch operator ${operatorAddress}: ${operatorResponse.status} ${operatorResponse.statusText}`
                    )
                }

                const data = await operatorResponse.json()
                const strategyAddresses = data.shares.map((share) => share.strategyAddress.toLowerCase())
                return {
                    operator: operatorAddress as string,
                    strategies: strategyAddresses as string[]
                }
            })
        )
        const operatorStrategies = new Map(operatorStrategiesData.map((item) => [item.operator, item.strategies]))

        const allocations: NodeAllocation[] = []

        for (const asset of unstakedAssets) {
            // Get token info to account for decimals
            const tokenInfo = tokenInfoMap.get(asset.asset.toLowerCase())

            if (!tokenInfo) {
                console.log(
                    `[Manager][Warning] Token info for ${asset.asset.toLowerCase()} not found. Skipping its allocation...`
                )
                continue
            }

            const balance = BigInt(asset.balance)
            const stakingAmount = (balance * BigInt(995)) / BigInt(1000) // allow 0.5% margin of error

            if (stakingAmount <= 0) {
                console.log(
                    `[Manager][Warning] Staking amount for ${asset.asset.toLowerCase()} is invalid, computed as ${stakingAmount} . Skipping its allocation...`
                )
                continue
            }

            // Filter for nodes whose Operators restake the asset
            const assetStrategyAddress = tokenInfo.strategyAddress.toLowerCase()
            const eligibleNodes = delegatedNodes.filter((node) =>
                operatorStrategies.get(node.operatorDelegation.toLowerCase())?.includes(assetStrategyAddress)
            )

            // Skip if no operators restake this strategy
            if (eligibleNodes.length === 0) {
                console.log(`[Manager][Warning] No operators restake asset ${asset.asset}. Skipping its allocation...`)
                continue
            }

            // Calculate even distribution across all nodes
            const amountPerNode = stakingAmount / BigInt(eligibleNodes.length)

            // Create allocations for all nodes
            for (const node of eligibleNodes) {
                const existingAllocation = allocations.find((alloc) => alloc.nodeId === node.nodeId.toString())

                if (existingAllocation) {
                    existingAllocation.assets.push(asset.asset)
                    existingAllocation.amounts.push(amountPerNode.toString())
                } else {
                    allocations.push({
                        nodeId: node.nodeId.toString(),
                        assets: [asset.asset],
                        amounts: [amountPerNode.toString()]
                    })
                }
            }
        }

        // If no allocations, exit early
        if (allocations.length === 0) {
            console.log('[Manager][Warning] No allocations computed. Skipping workflow...')
            return []
        }

        // Create proposals to stake assets to nodes
        await stakeAssetsToNodes(allocations)

        console.log('[Manager] Stake unstaked assets complete')
    } catch (error) {
        console.log('[Manager] Error: ', error.message)
        throw error
    }
}
