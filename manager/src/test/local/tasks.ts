import 'dotenv/config'

import type { Abi } from 'viem'
import { ADMIN, DEPLOYMENT, LIQUID_TOKEN_ADDRESS, NETWORK, PAUSER } from '../../utils/forge'
import { apiKit } from '../../utils/safe'
import { decodeFunctionData, encodeFunctionData, parseAbi } from 'viem/utils'
import { createStakerNodes } from '../../tasks/createStakerNodes'
import { delegateNodes } from '../../tasks/delegateNodes'
import { stakeAssetsToNode } from '../../tasks/stakeAssetsToNode'
import { undelegateNodes } from '../../tasks/undelegateNodes'
import { type NodeAllocation, stakeAssetsToNodes } from '../../tasks/stakeAssetsToNodes'
import { addToken } from '../../tasks/system/addToken'
import { pauseLiquidToken } from '../../tasks/system/pauseLiquidToken'
import { removeToken } from '../../tasks/system/removeToken'
import { setMaxNodes } from '../../tasks/system/setMaxNodes'
import { setVolatilityThreshold } from '../../tasks/system/setVolatilityThreshold'
import { unpauseLiquidToken } from '../../tasks/system/unpauseLiquidToken'
import { upgradeStakerNodeImplementation } from '../../tasks/system/upgradeStakerNodeImplementation'
import { batchUpdateRates } from '../../tasks/system/batchUpdateRates'
import { updateAllPricesIfNeeded } from '../../tasks/system/updateAllPricesIfNeeded'
import { grantRole } from '../../tasks/system/grantRole'
import { revokeRole } from '../../tasks/system/revokeRole'
import { setPriceUpdateInterval } from '../../tasks/system/setPriceUpdateInterval'
import { disableEmergencyInterval } from '../../tasks/system/disableEmergencyInterval'

// --- Manager tasks tests ---

const ABIS: Record<string, string[]> = {
    createStakerNode: ['function createStakerNode()'],
    delegateNodes: ['function delegateNodes(uint256[],address[],(bytes,uint256)[],bytes32[])'],
    stakeAssetsToNode: ['function stakeAssetsToNode(uint256,address[],uint256[])'],
    stakeAssetsToNodes: ['function stakeAssetsToNodes((uint256,address[],uint256[])[])'],
    undelegateNodes: ['function undelegateNodes(uint256[])']
}

/**
 * Test script for creating staker nodes
 *
 */
export async function testCreateStakerNodes() {
    try {
        if (DEPLOYMENT !== 'local') throw new Error('Deployment is not local')
        if (!ADMIN) throw new Error('Env vars not set correctly.')

        let passing = true
        const functionName = 'createStakerNode'
        const abi = parseAbi(ABIS[functionName])

        // Create two staker nodes
        await createStakerNodes(2)

        // Get proposed txs
        const pendingTransactions = (
            await apiKit.getPendingTransactions(ADMIN, {
                limit: 2
            })
        ).results

        for (const [index, pendingTx] of pendingTransactions.entries()) {
            const txData = pendingTx.data as `0x${string}`
            const expectedTxData = encodeFunctionData({
                abi,
                functionName,
                args: []
            })
            passing = compareTxData(txData, expectedTxData, abi)

            console.log(`[Test] ${functionName}: ${index + 1}: `, passing ? 'passing ✅' : 'failing ❌')
        }
    } catch (error) {
        console.log(error)
    }
}

/**
 * Test script for delegating staker nodes
 *
 */
export async function testDelegateNodes() {
    try {
        if (DEPLOYMENT !== 'local') throw new Error('Deployment is not local')
        if (!ADMIN) throw new Error('Env vars not set correctly.')

        let passing = true
        const functionName = 'delegateNodes'
        const abi = parseAbi(ABIS[functionName])

        // Delegate two nodes to EigenYields
        const operatorAddress =
            NETWORK === 'mainnet'
                ? '0x5accc90436492f24e6af278569691e2c942a676d'
                : '0x5accc90436492f24e6af278569691e2c942a676d'

        await delegateNodes(
            ['3', '4'],
            [operatorAddress, operatorAddress],
            [
                {
                    signature: '0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff',
                    expiry: 0
                },
                {
                    signature: '0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff',
                    expiry: 0
                }
            ],
            [
                '0x0000000000000000000000000000000000000000000000000000000000000000',
                '0x0000000000000000000000000000000000000000000000000000000000000000'
            ]
        )

        // Get proposed tx
        const pendingTx = (
            await apiKit.getPendingTransactions(ADMIN, {
                limit: 1
            })
        ).results[0]

        const txData = pendingTx.data as `0x${string}`
        const expectedTxData = encodeFunctionData({
            abi,
            functionName,
            args: [
                ['3', '4'],
                [operatorAddress, operatorAddress],
                [
                    ['0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff', 0n],
                    ['0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff', 0n]
                ],
                [
                    '0x0000000000000000000000000000000000000000000000000000000000000000',
                    '0x0000000000000000000000000000000000000000000000000000000000000000'
                ]
            ]
        })
        passing = compareTxData(txData, expectedTxData, abi)

        console.log(`[Test] ${functionName}: `, passing ? 'passing ✅' : 'failing ❌')
    } catch (error) {
        console.log(error)
    }
}
/**
 * Test script for staking assets to nodes
 *
 */
export async function testStakeAssetsToNodes() {
    try {
        if (DEPLOYMENT !== 'local') throw new Error('Deployment is not local')
        if (!ADMIN) throw new Error('Env vars not set correctly.')

        let passing = true
        const functionName = 'stakeAssetsToNodes'
        const abi = parseAbi(ABIS[functionName])

        const stEthAddress =
            NETWORK === 'mainnet'
                ? '0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84'
                : '0x3f1c547b21f65e10480de3ad8e19faac46c95034'

        // Stake assets to first and second nodes
        const allocations: NodeAllocation[] = [
            {
                nodeId: '0',
                assets: [stEthAddress],
                amounts: ['2500000000000000000']
            },
            {
                nodeId: '1',
                assets: [stEthAddress],
                amounts: ['2500000000000000000']
            }
        ]

        await stakeAssetsToNodes(allocations)

        // Get proposed tx
        const pendingTx = (
            await apiKit.getPendingTransactions(ADMIN, {
                limit: 1
            })
        ).results[0]

        const txData = pendingTx.data as `0x${string}`
        const expectedTxData = encodeFunctionData({
            abi,
            functionName,
            args: [
                [
                    [0n, [stEthAddress], ['2500000000000000000'].map((amount) => BigInt(amount))],
                    [1n, [stEthAddress], ['2500000000000000000'].map((amount) => BigInt(amount))]
                ]
            ]
        })
        passing = compareTxData(txData, expectedTxData, abi)

        console.log(`[Test] ${functionName}: `, passing ? 'passing ✅' : 'failing ❌')
    } catch (error) {
        console.log(error)
    }
}

/**
 * Test script for staking assets to one node
 *
 */
export async function testStakeAssetsToNode() {
    try {
        if (DEPLOYMENT !== 'local') throw new Error('Deployment is not local')
        if (!ADMIN) throw new Error('Env vars not set correctly.')

        let passing = true
        const functionName = 'stakeAssetsToNode'
        const abi = parseAbi(ABIS[functionName])

        const stEthAddress =
            NETWORK === 'mainnet'
                ? '0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84'
                : '0x3f1c547b21f65e10480de3ad8e19faac46c95034'

        const args: [string, string[], string[]] = ['2', [stEthAddress], ['3000000000000000000']]

        // Stake assets to third node
        await stakeAssetsToNode(...args)

        // Get proposed tx
        const pendingTx = (
            await apiKit.getPendingTransactions(ADMIN, {
                limit: 1
            })
        ).results[0]

        const txData = pendingTx.data as `0x${string}`
        const expectedTxData = encodeFunctionData({
            abi,
            functionName,
            args
        })
        passing = compareTxData(txData, expectedTxData, abi)

        console.log(`[Test] ${functionName}: `, passing ? 'passing ✅' : 'failing ❌')
    } catch (error) {
        console.log(error)
    }
}

/**
 * Test script for undelegating nodes
 *
 */
export async function testUndelegateNodes() {
    try {
        if (DEPLOYMENT !== 'local') throw new Error('Deployment is not local')
        if (!ADMIN) throw new Error('Env vars not set correctly.')

        let passing = true
        const functionName = 'undelegateNodes'
        const abi = parseAbi(ABIS[functionName])

        const args: [string[]] = [['0', '1']]

        // Undelegate two nodes
        await undelegateNodes(...args)

        // Get proposed tx
        const pendingTx = (
            await apiKit.getPendingTransactions(ADMIN, {
                limit: 1
            })
        ).results[0]

        const txData = pendingTx.data as `0x${string}`
        const expectedTxData = encodeFunctionData({
            abi,
            functionName,
            args
        })
        passing = compareTxData(txData, expectedTxData, abi)

        console.log(`[Test] ${functionName}: `, passing ? 'passing ✅' : 'failing ❌')
    } catch (error) {
        console.log(error)
    }
}

// --- System tasks tests ---

/**
 * Test script for adding token
 *
 */
export async function testAddToken() {
    try {
        if (DEPLOYMENT !== 'local') throw new Error('Deployment is not local')
        if (!ADMIN) throw new Error('Env vars not set correctly.')

        let passing = true
        const functionName = 'addToken'
        const abi = parseAbi(['function addToken(address,uint8,uint256,address,uint8,address,uint8,address,bytes4)'])

        const args: [string, number, string, string, number, string, number, string, `0x${string}`] = [
            NETWORK === 'holesky'
                ? '0xa63f56985f9c7f3bc9ffc5685535649e0c1a55f3' // sfrxETH
                : '0xac3e018457b222d93114458476f3e3416abbe38f', // sfrxETH
            18,
            '50000000000000000',
            NETWORK === 'holesky'
                ? '0x9281ff96637710cd9a5cacce9c6fad8c9f54631c'
                : '0x8ca7a5d6f3acd3a7a8bc468a8cd0fb14b6bd28b6',
            3,
            '0xac3E018457B222d93114458476f3E3416Abbe38F',
            1,
            NETWORK === 'holesky'
                ? '0xa63f56985f9c7f3bc9ffc5685535649e0c1a55f3'
                : '0xac3E018457B222d93114458476f3E3416Abbe38F',
            '0x07a2d13a'
        ]

        await addToken(...args)

        // Get proposed tx
        const pendingTx = (
            await apiKit.getPendingTransactions(ADMIN, {
                limit: 1
            })
        ).results[0]

        const txData = pendingTx.data as `0x${string}`
        const expectedTxData = encodeFunctionData({
            abi,
            functionName,
            args: [
                NETWORK === 'holesky'
                    ? '0xa63f56985f9c7f3bc9ffc5685535649e0c1a55f3' // sfrxETH
                    : '0xac3e018457b222d93114458476f3e3416abbe38f', // sfrxETH
                18,
                BigInt('50000000000000000'),
                NETWORK === 'holesky'
                    ? '0x9281ff96637710cd9a5cacce9c6fad8c9f54631c'
                    : '0x8ca7a5d6f3acd3a7a8bc468a8cd0fb14b6bd28b6',
                3,
                '0xac3E018457B222d93114458476f3E3416Abbe38F',
                1,
                NETWORK === 'holesky'
                    ? '0xa63f56985f9c7f3bc9ffc5685535649e0c1a55f3'
                    : '0xac3E018457B222d93114458476f3E3416Abbe38F',
                '0x07a2d13a'
            ]
        })
        passing = compareTxData(txData, expectedTxData, abi)

        console.log(`[Test] ${functionName}: `, passing ? 'passing ✅' : 'failing ❌')
    } catch (error) {
        console.log(error)
    }
}

/**
 * Test script for pausing liquid token
 *
 */
export async function testPauseLiquidToken() {
    try {
        if (DEPLOYMENT !== 'local') throw new Error('Deployment is not local')
        if (!PAUSER) throw new Error('Env vars not set correctly.')

        let passing = true
        const functionName = 'pause'
        const abi = parseAbi(['function pause()'])

        await pauseLiquidToken()

        // Get proposed tx
        const pendingTx = (
            await apiKit.getPendingTransactions(PAUSER, {
                limit: 1
            })
        ).results[0]

        const txData = pendingTx.data as `0x${string}`
        const expectedTxData = encodeFunctionData({
            abi,
            functionName,
            args: []
        })
        passing = compareTxData(txData, expectedTxData, abi)

        console.log(`[Test] ${functionName}: `, passing ? 'passing ✅' : 'failing ❌')
    } catch (error) {
        console.log(error)
    }
}

/**
 * Test script for removing token
 *
 */
export async function testRemoveToken() {
    try {
        if (DEPLOYMENT !== 'local') throw new Error('Deployment is not local')
        if (!ADMIN) throw new Error('Env vars not set correctly.')

        let passing = true
        const functionName = 'removeToken'
        const abi = parseAbi(['function removeToken(address)'])

        const args: [string] = [
            NETWORK === 'holesky'
                ? '0x3f1c547b21f65e10480de3ad8e19faac46c95034' // stETH
                : '0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84' // stETH
        ]

        await removeToken(args[0])

        // Get proposed tx
        const pendingTx = (
            await apiKit.getPendingTransactions(ADMIN, {
                limit: 1
            })
        ).results[0]

        const txData = pendingTx.data as `0x${string}`
        const expectedTxData = encodeFunctionData({
            abi,
            functionName,
            args
        })
        passing = compareTxData(txData, expectedTxData, abi)

        console.log(`[Test] ${functionName}: `, passing ? 'passing ✅' : 'failing ❌')
    } catch (error) {
        console.log(error)
    }
}

/**
 * Test script for setting max nodes
 *
 */
export async function testSetMaxNodes() {
    try {
        if (DEPLOYMENT !== 'local') throw new Error('Deployment is not local')
        if (!ADMIN) throw new Error('Env vars not set correctly.')

        let passing = true
        const functionName = 'setMaxNodes'
        const abi = parseAbi(['function setMaxNodes(uint256)'])

        const args: [string] = ['1000']

        await setMaxNodes(args[0])

        // Get proposed tx
        const pendingTx = (
            await apiKit.getPendingTransactions(ADMIN, {
                limit: 1
            })
        ).results[0]

        const txData = pendingTx.data as `0x${string}`
        const expectedTxData = encodeFunctionData({
            abi,
            functionName,
            args: [BigInt('1000')]
        })
        passing = compareTxData(txData, expectedTxData, abi)

        console.log(`[Test] ${functionName}: `, passing ? 'passing ✅' : 'failing ❌')
    } catch (error) {
        console.log(error)
    }
}

/**
 * Test script for setting volatility threshold
 *
 */
export async function testSetVolatilityThreshold() {
    try {
        if (DEPLOYMENT !== 'local') throw new Error('Deployment is not local')
        if (!ADMIN) throw new Error('Env vars not set correctly.')

        let passing = true
        const functionName = 'setVolatilityThreshold'
        const abi = parseAbi(['function setVolatilityThreshold(address,uint256)'])

        const args: [string, string] = [
            NETWORK === 'holesky'
                ? '0xa63f56985f9c7f3bc9ffc5685535649e0c1a55f3' // sfrxETH
                : '0xac3e018457b222d93114458476f3e3416abbe38f', // sfrxETH
            '50000000000000000'
        ]

        await setVolatilityThreshold(args[0], args[1])

        // Get proposed tx
        const pendingTx = (
            await apiKit.getPendingTransactions(ADMIN, {
                limit: 1
            })
        ).results[0]

        const txData = pendingTx.data as `0x${string}`
        const expectedTxData = encodeFunctionData({
            abi,
            functionName,
            args: [
                NETWORK === 'holesky'
                    ? '0xa63f56985f9c7f3bc9ffc5685535649e0c1a55f3' // sfrxETH
                    : '0xac3e018457b222d93114458476f3e3416abbe38f', // sfrxETH
                BigInt('50000000000000000')
            ]
        })
        passing = compareTxData(txData, expectedTxData, abi)

        console.log(`[Test] ${functionName}: `, passing ? 'passing ✅' : 'failing ❌')
    } catch (error) {
        console.log(error)
    }
}

/**
 * Test script for unpausing liquid token
 *
 */
export async function testUnpauseLiquidToken() {
    try {
        if (DEPLOYMENT !== 'local') throw new Error('Deployment is not local')
        if (!ADMIN) throw new Error('Env vars not set correctly.')

        let passing = true
        const functionName = 'unpause'
        const abi = parseAbi(['function unpause()'])

        await unpauseLiquidToken()

        // Get proposed tx
        const pendingTx = (
            await apiKit.getPendingTransactions(ADMIN, {
                limit: 1
            })
        ).results[0]

        const txData = pendingTx.data as `0x${string}`
        const expectedTxData = encodeFunctionData({
            abi,
            functionName,
            args: []
        })
        passing = compareTxData(txData, expectedTxData, abi)

        console.log(`[Test] ${functionName}: `, passing ? 'passing ✅' : 'failing ❌')
    } catch (error) {
        console.log(error)
    }
}

/**
 * Test script for upgrading staker node implementation
 *
 */
export async function testUpgradeStakerNodeImplementation() {
    try {
        if (DEPLOYMENT !== 'local') throw new Error('Deployment is not local')
        if (!ADMIN) throw new Error('Env vars not set correctly.')

        let passing = true
        const functionName = 'upgradeStakerNodeImplementation'
        const abi = parseAbi(['function upgradeStakerNodeImplementation(address)'])

        const args: [string] = [
            NETWORK === 'holesky'
                ? '0x1234567890123456789012345678901234567890'
                : '0x0987654321098765432109876543210987654321'
        ]

        await upgradeStakerNodeImplementation(args[0])

        // Get proposed tx
        const pendingTx = (
            await apiKit.getPendingTransactions(ADMIN, {
                limit: 1
            })
        ).results[0]

        const txData = pendingTx.data as `0x${string}`
        const expectedTxData = encodeFunctionData({
            abi,
            functionName,
            args
        })
        passing = compareTxData(txData, expectedTxData, abi)

        console.log(`[Test] ${functionName}: `, passing ? 'passing ✅' : 'failing ❌')
    } catch (error) {
        console.log(error)
    }
}

/**
 * Test script for updating all token prices
 *
 */
export async function testUpdateAllPricesIfNeeded() {
    try {
        if (DEPLOYMENT !== 'local') throw new Error('Deployment is not local')
        if (!ADMIN) throw new Error('Env vars not set correctly.')

        let passing = true
        const functionName = 'updateAllPricesIfNeeded'
        const abi = parseAbi(['function updateAllPricesIfNeeded()'])

        await updateAllPricesIfNeeded()

        // Get proposed tx
        const pendingTx = (
            await apiKit.getPendingTransactions(ADMIN, {
                limit: 1
            })
        ).results[0]

        const txData = pendingTx.data as `0x${string}`
        const expectedTxData = encodeFunctionData({
            abi,
            functionName,
            args: []
        })
        passing = compareTxData(txData, expectedTxData, abi)

        console.log(`[Test] ${functionName}: `, passing ? 'passing ✅' : 'failing ❌')
    } catch (error) {
        console.log(error)
    }
}

/**
 * Test script for batched price update
 *
 */
export async function testBatchUpdateRates() {
    try {
        if (DEPLOYMENT !== 'local') throw new Error('Deployment is not local')
        if (!ADMIN) throw new Error('Env vars not set correctly.')

        let passing = true
        const functionName = 'batchUpdateRates'
        const abi = parseAbi(['function batchUpdateRates(address[],uint256[])'])

        const args: [string[], bigint[]] = [
            NETWORK === 'holesky'
                ? ['0x3f1c547b21f65e10480de3ad8e19faac46c95034', '0xa63f56985f9c7f3bc9ffc5685535649e0c1a55f3'] // stETH, sfrxETH
                : ['0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84', '0xac3e018457b222d93114458476f3e3416abbe38f'], // stETH, sfrxETH
            [110100000000000000n, 102500000000000000n]
        ]

        await batchUpdateRates(args[0], args[1])

        // Get proposed tx
        const pendingTx = (
            await apiKit.getPendingTransactions(ADMIN, {
                limit: 1
            })
        ).results[0]

        const txData = pendingTx.data as `0x${string}`
        const expectedTxData = encodeFunctionData({
            abi,
            functionName,
            args
        })
        passing = compareTxData(txData, expectedTxData, abi)

        console.log(`[Test] ${functionName}: `, passing ? 'passing ✅' : 'failing ❌')
    } catch (error) {
        console.log(error)
    }
}

/**
 * Test script for granting role
 *
 */
export async function testGrantRole() {
    try {
        if (DEPLOYMENT !== 'local') throw new Error('Deployment is not local')
        if (!ADMIN) throw new Error('Env vars not set correctly.')

        let passing = true
        const functionName = 'grantRole'
        const abi = parseAbi(['function grantRole(bytes32,address)'])

        const args: [`0x${string}`, string] = [
            '0x0000000000000000000000000000000000000000000000000000000000000000',
            '0x457e4309b91f5cb6b0ad9c6bf39e4788b5ba6a12'
        ]

        await grantRole(LIQUID_TOKEN_ADDRESS, args[0], args[1])

        // Get proposed tx
        const pendingTx = (
            await apiKit.getPendingTransactions(ADMIN, {
                limit: 1
            })
        ).results[0]

        const txData = pendingTx.data as `0x${string}`
        const expectedTxData = encodeFunctionData({
            abi,
            functionName,
            args
        })
        passing = compareTxData(txData, expectedTxData, abi)

        console.log(`[Test] ${functionName}: `, passing ? 'passing ✅' : 'failing ❌')
    } catch (error) {
        console.log(error)
    }
}

/**
 * Test script for revoking role
 *
 */
export async function testRevokeRole() {
    try {
        if (DEPLOYMENT !== 'local') throw new Error('Deployment is not local')
        if (!ADMIN) throw new Error('Env vars not set correctly.')

        let passing = true
        const functionName = 'revokeRole'
        const abi = parseAbi(['function revokeRole(bytes32,address)'])

        const args: [`0x${string}`, string] = [
            '0x0000000000000000000000000000000000000000000000000000000000000000',
            '0x457e4309b91f5cb6b0ad9c6bf39e4788b5ba6a12'
        ]

        await revokeRole(LIQUID_TOKEN_ADDRESS, args[0], args[1])

        // Get proposed tx
        const pendingTx = (
            await apiKit.getPendingTransactions(ADMIN, {
                limit: 1
            })
        ).results[0]

        const txData = pendingTx.data as `0x${string}`
        const expectedTxData = encodeFunctionData({
            abi,
            functionName,
            args
        })
        passing = compareTxData(txData, expectedTxData, abi)

        console.log(`[Test] ${functionName}: `, passing ? 'passing ✅' : 'failing ❌')
    } catch (error) {
        console.log(error)
    }
}

/**
 * Test script for setting price update interval
 *
 */
export async function testSetPriceUpdateInterval() {
    try {
        if (DEPLOYMENT !== 'local') throw new Error('Deployment is not local')
        if (!ADMIN) throw new Error('Env vars not set correctly.')

        let passing = true
        const functionName = 'setPriceUpdateInterval'
        const abi = parseAbi(['function setPriceUpdateInterval(uint256 interval)'])

        const args: [bigint] = [86400n]

        await setPriceUpdateInterval(args[0])

        // Get proposed tx
        const pendingTx = (
            await apiKit.getPendingTransactions(ADMIN, {
                limit: 1
            })
        ).results[0]

        const txData = pendingTx.data as `0x${string}`
        const expectedTxData = encodeFunctionData({
            abi,
            functionName,
            args
        })
        passing = compareTxData(txData, expectedTxData, abi)

        console.log(`[Test] ${functionName}: `, passing ? 'passing ✅' : 'failing ❌')
    } catch (error) {
        console.log(error)
    }
}

/**
 * Test script for disabling emergency interval
 *
 */
export async function testDisableEmergencyInterval() {
    try {
        if (DEPLOYMENT !== 'local') throw new Error('Deployment is not local')
        if (!ADMIN) throw new Error('Env vars not set correctly.')

        let passing = true
        const functionName = 'disableEmergencyInterval'
        const abi = parseAbi(['function disableEmergencyInterval()'])

        const args: [] = []

        await disableEmergencyInterval()

        // Get proposed tx
        const pendingTx = (
            await apiKit.getPendingTransactions(ADMIN, {
                limit: 1
            })
        ).results[0]

        const txData = pendingTx.data as `0x${string}`
        const expectedTxData = encodeFunctionData({
            abi,
            functionName,
            args
        })
        passing = compareTxData(txData, expectedTxData, abi)

        console.log(`[Test] ${functionName}: `, passing ? 'passing ✅' : 'failing ❌')
    } catch (error) {
        console.log(error)
    }
}

// --- Helper functions ---

/**
 * Compares two transaction data strings to determine if they represent the same function call.
 * Works with complex parameter types including arrays, structs, and nested data.
 *
 * @param actualTxData
 * @param expectedTxData
 * @param abiRegistry
 * @returns
 */
function compareTxData(actualTxData: `0x${string}`, expectedTxData: `0x${string}`, abi: Abi): boolean {
    if (actualTxData === expectedTxData) {
        return true
    }

    const actualSelector = actualTxData.slice(0, 10)
    const expectedSelector = expectedTxData.slice(0, 10)

    if (actualSelector !== expectedSelector) {
        console.log("Function selectors don't match")
        return false
    }

    const actualDecodedData = decodeFunctionData({
        abi,
        data: actualTxData
    })
    const expectedDecodedData = decodeFunctionData({
        abi,
        data: expectedTxData
    })

    if (actualDecodedData.functionName === expectedDecodedData.functionName) {
        return compareArgs(actualDecodedData.args, expectedDecodedData.args)
    }

    return false
}

/**
 * Deep compares two argument arrays or objects, handling nested structures
 *
 * @param args1
 * @param args2
 * @returns
 */
function compareArgs(args1, args2) {
    if (args1 === args2) return true
    if (args1 == null || args2 == null) return false

    if (Array.isArray(args1) && Array.isArray(args2)) {
        if (args1.length !== args2.length) return false

        for (let i = 0; i < args1.length; i++) {
            if (!compareArgs(args1[i], args2[i])) return false
        }

        return true
    }

    if (typeof args1 === 'object' && typeof args2 === 'object') {
        const keys1 = Object.keys(args1)
        const keys2 = Object.keys(args2)

        if (keys1.length !== keys2.length) return false

        for (const key of keys1) {
            if (!keys2.includes(key)) return false
            if (!compareArgs(args1[key], args2[key])) return false
        }

        return true
    }

    if (typeof args1 === 'bigint' && typeof args2 === 'bigint') {
        return args1 === args2
    }

    return String(args1) === String(args2)
}
