import { LIQUID_TOKEN_ADDRESS } from '../utils/forge'

// --- Types ---

interface Redemption {
    id: number
    liquidTokenAddress: string
    redemptionId: string
    requestId: string
    type: string
    withdrawalRoot: string
    nodeId: string | null
    assets: string[]
    staker: string
    delegatedTo: string
    withdrawer: string
    nonce: string
    startBlock: string
    strategies: string[]
    scaledShares: string[]
    createdAtBlock: bigint
    createdAt: Date
    redemptionCompleted: {
        createdAt: Date
    } | null
    status: 'created' | 'mature' | 'complete'
}

interface RedemptionsResponse {
    data: Redemption[]
    meta: {
        total: number
        count: number
        skip: number
        take: number
    }
}

interface ElWithdrawal {
    staker: string
    delegatedTo: string
    withdrawer: string
    nonce: string
    startBlock: string
    strategies: string[]
    scaledShares: string[]
}

interface CompleteRedemption {
    redemptionId: string
    nodeIds: string[]
    withdrawals: ElWithdrawal[][]
    assets: string[][][]
}

// --- Core functions ---

/**
 * Workflow for completing redemptions after maturity by calling
 * `completeRedemptions` on `LiquidTokenManager`
 *
 * @returns
 */
export async function completeRedemptions() {
    try {
        const LAT_API_URL = process.env.LAT_API_URL

        // Gather required data
        const redemptionsPromise = (async (): Promise<RedemptionsResponse> => {
            const allRedemptions: Redemption[] = []
            let total = 0
            let skip = 0
            const take = 100

            while (true) {
                const response = await fetch(
                    `${LAT_API_URL}/lat/${LIQUID_TOKEN_ADDRESS}/redemptions?status=mature&skip=${skip}&take=${take}`
                )

                if (!response.ok) {
                    throw new Error(`Failed to fetch redemptions: ${response.status} ${response.statusText}`)
                }

                const data = (await response.json()) as RedemptionsResponse
                allRedemptions.push(...data.data)

                // Check if we've paginated through `total` records
                if (skip + take >= data.meta.total) {
                    total = data.meta.total
                    break
                }

                skip += take
            }

            return {
                data: allRedemptions,
                meta: {
                    total,
                    count: allRedemptions.length,
                    skip: 0,
                    take: allRedemptions.length
                }
            }
        })()

        const redemptions = (await redemptionsPromise).data

        // Group redemptions by redemptionId since multiple requests can share the same redemptionId
        const redemptionGroups = new Map<string, Redemption[]>()

        for (const redemption of redemptions) {
            if (!redemptionGroups.has(redemption.redemptionId)) {
                redemptionGroups.set(redemption.redemptionId, [])
            }
            redemptionGroups.get(redemption.redemptionId)?.push(redemption)
        }

        // Process each redemption group
        for (const [redemptionId, groupedRedemptions] of redemptionGroups) {
            try {
                const completeRedemption: CompleteRedemption = {
                    redemptionId,
                    nodeIds: groupedRedemptions
                        .map((r) => r.nodeId)
                        .filter((nodeId): nodeId is string => nodeId !== null),
                    withdrawals: groupedRedemptions.map((redemption) => [
                        {
                            staker: redemption.staker,
                            delegatedTo: redemption.delegatedTo,
                            withdrawer: redemption.withdrawer,
                            nonce: redemption.nonce,
                            startBlock: redemption.startBlock,
                            strategies: redemption.strategies,
                            scaledShares: redemption.scaledShares
                        }
                    ]),
                    assets: groupedRedemptions.map((redemption) => [redemption.assets])
                }

                // TODO: await completeRedemption(completeRedemption)
            } catch (error) {
                console.log(`[Manager] Error: Failed to complete redemption ${redemptionId}:`, error)
                // Continue with other redemptions even if one fails
            }
        }

        console.log('[Manager] Complete Redemptions complete')
    } catch (error) {
        console.log('[Manager] Error: ', error.message)
        throw error
    }
}
