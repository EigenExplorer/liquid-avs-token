import type { TokenInfo } from '../workflows/stakeUnstakedAssets'
import { getViemClient } from './viemClient'

export const strategyAbi = [
    {
        inputs: [
            {
                internalType: 'uint256',
                name: 'amountShares',
                type: 'uint256'
            }
        ],
        name: 'sharesToUnderlying',
        outputs: [
            {
                internalType: 'uint256',
                name: '',
                type: 'uint256'
            }
        ],
        stateMutability: 'nonpayable',
        type: 'function'
    }
]

/**
 * For a given set of assets and share amounts, returns the TVL in native terms
 * after consdering each corresponding strategy's EL `sharesToUnderlying` value
 *
 * @param assetShares
 * @param tokenInfo
 * @returns
 */
export async function sharesToTvl(
    assetShares: Map<string, bigint>,
    tokenInfo: Map<string, TokenInfo>
): Promise<Map<string, bigint>> {
    const viemClient = getViemClient()
    const assetTvls = new Map<string, bigint>()

    for (const [address, shareAmount] of Array.from(assetShares)) {
        let sharesToUnderlying = BigInt(1e18)
        const token = tokenInfo.get(address)
        if (token) {
            try {
                sharesToUnderlying = (await viemClient.readContract({
                    address: token.strategyAddress as `0x${string}`,
                    abi: strategyAbi,
                    functionName: 'sharesToUnderlyingView',
                    args: [1e18]
                })) as bigint
            } catch {}

            const multiplier =
                (shareAmount * BigInt(sharesToUnderlying)) / (BigInt(1e18) * BigInt(10 ** token.decimals))
            const tvl = multiplier * BigInt(token.pricePerUnit)
            assetTvls.set(address, tvl)
        }
    }

    return assetTvls
}
