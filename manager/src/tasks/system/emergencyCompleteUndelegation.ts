import 'dotenv/config'

import { OperationType } from '@safe-global/types-kit'
import { encodeFunctionData, parseAbi, getAddress } from 'viem/utils'
import { createPublicClient, http } from 'viem'
import { mainnet, holesky } from 'viem/chains'
import { readFileSync } from 'fs'
import { apiKit, protocolKitOwnerAdmin } from '../../utils/safe'
import {
    ADMIN,
    EMERGENCY_RESCUE_ADDRESS,
    DELEGATION_MANAGER_ADDRESS,
    STAKER_NODE_COORDINATOR_ADDRESS,
    DEPLOYMENT,
    proposeSafeTransaction
} from '../../utils/forge'

/**
 * Creates a proposal for emergencyCompleteUndelegation on EmergencyRescue
 * This completes the EigenLayer withdrawals and transfers funds to the multisig
 * 
 * MUST be called at least 7 days (50,400 blocks) after emergencyUndelegateAllNodes
 * 
 * @param withdrawalDataFile Path to the saved withdrawal data JSON file
 * @param recipientAddress Address to receive the recovered funds (usually the multisig)
 * @returns 
 */
export async function emergencyCompleteUndelegation(
    withdrawalDataFile: string,
    recipientAddress: string
) {
    try {
        if (!ADMIN) throw new Error('Env vars not set correctly.')

        // Load saved withdrawal data
        console.log('Loading withdrawal data from:', withdrawalDataFile)
        const savedData = JSON.parse(readFileSync(withdrawalDataFile, 'utf-8'))
        const nodeIds = savedData.nodeIds
        const withdrawalData = savedData.withdrawalData

        console.log(`Processing ${nodeIds.length} nodes...\n`)

        // Setup client
        const chain = DEPLOYMENT === 'mainnet' ? mainnet : holesky
        const client = createPublicClient({
            chain,
            transport: http()
        })

        // Verify withdrawal delay has passed
        const currentBlock = await client.getBlockNumber()
        console.log(`Current block: ${currentBlock}`)

        for (const nodeId of nodeIds) {
            const withdrawals = withdrawalData[nodeId]
            for (const withdrawal of withdrawals) {
                const requiredBlock = BigInt(withdrawal.startBlock) + BigInt(50400)
                if (currentBlock < requiredBlock) {
                    throw new Error(
                        `Withdrawal delay not met for node ${nodeId}!\n` +
                        `   Current block: ${currentBlock}\n` +
                        `   Required block: ${requiredBlock}\n` +
                        `   Blocks remaining: ${requiredBlock - currentBlock}`
                    )
                }
            }
        }

        console.log('Withdrawal delay check passed\n')

        // Get StakerNode addresses from coordinator
        const coordinatorAbi = parseAbi([
            'function getNodeById(uint256) view returns (address)'
        ])

        // Fetch withdrawals from EigenLayer using saved withdrawalRoots
        console.log('Fetching withdrawals from EigenLayer...')

        const delegationManagerAbi = parseAbi([
            'function getQueuedWithdrawal(bytes32) view returns (tuple(address staker, address delegatedTo, address withdrawer, uint256 nonce, uint32 startBlock, address[] strategies, uint256[] scaledShares), uint256[])'
        ])

        const strategyAbi = parseAbi([
            'function underlyingToken() view returns (address)'
        ])

        const allWithdrawals: any[][] = []
        const allAssets: any[][] = []

        for (const nodeId of nodeIds) {
            console.log(`\nProcessing node ${nodeId}...`)

            const nodeWithdrawals: any[] = []
            const nodeAssets: any[][] = []

            // Get node address from coordinator
            const nodeAddress = await client.readContract({
                address: STAKER_NODE_COORDINATOR_ADDRESS as `0x${string}`,
                abi: coordinatorAbi,
                functionName: 'getNodeById',
                args: [BigInt(nodeId)]
            })

            console.log(`  Node address: ${nodeAddress}`)

            const savedWithdrawals = withdrawalData[nodeId]

            for (const savedWithdrawal of savedWithdrawals) {
                console.log(`  Processing ${savedWithdrawal.withdrawalRoots.length} withdrawal root(s)...`)

                // Process each withdrawal root
                for (const withdrawalRoot of savedWithdrawal.withdrawalRoots) {
                    console.log(`    Querying root: ${withdrawalRoot}`)

                    // Query EigenLayer for the actual withdrawal struct
                    const [withdrawal, shares] = await client.readContract({
                        address: DELEGATION_MANAGER_ADDRESS as `0x${string}`,
                        abi: delegationManagerAbi,
                        functionName: 'getQueuedWithdrawal',
                        args: [withdrawalRoot as `0x${string}`]
                    }) as any

                    console.log(`    Found withdrawal with ${withdrawal.strategies.length} strategies`)

                    // Validate withdrawal matches our saved data
                    if (withdrawal.staker.toLowerCase() !== (nodeAddress as string).toLowerCase()) {
                        throw new Error(
                            `Withdrawal staker mismatch!\n` +
                            `  Expected: ${nodeAddress}\n` +
                            `  Got: ${withdrawal.staker}`
                        )
                    }

                    if (BigInt(withdrawal.nonce) !== BigInt(savedWithdrawal.nonce)) {
                        throw new Error(
                            `Withdrawal nonce mismatch!\n` +
                            `  Expected: ${savedWithdrawal.nonce}\n` +
                            `  Got: ${withdrawal.nonce}`
                        )
                    }

                    if (withdrawal.delegatedTo.toLowerCase() !== savedWithdrawal.operator.toLowerCase()) {
                        throw new Error(
                            `Withdrawal operator mismatch!\n` +
                            `  Expected: ${savedWithdrawal.operator}\n` +
                            `  Got: ${withdrawal.delegatedTo}`
                        )
                    }

                    // Add validated withdrawal
                    nodeWithdrawals.push({
                        staker: withdrawal.staker,
                        delegatedTo: withdrawal.delegatedTo,
                        withdrawer: withdrawal.withdrawer,
                        nonce: withdrawal.nonce,
                        startBlock: withdrawal.startBlock,
                        strategies: withdrawal.strategies,
                        scaledShares: withdrawal.scaledShares
                    })

                    // Get token addresses from strategies
                    const tokens: string[] = []
                    console.log(`    Fetching tokens from strategies...`)

                    for (let i = 0; i < withdrawal.strategies.length; i++) {
                        const strategy = withdrawal.strategies[i]

                        try {
                            const token = await client.readContract({
                                address: strategy as `0x${string}`,
                                abi: strategyAbi,
                                functionName: 'underlyingToken'
                            })
                            tokens.push(token as string)
                            console.log(`      Strategy ${i}: ${strategy} -> Token: ${token}`)
                        } catch (error) {
                            throw new Error(
                                `Failed to get underlying token for strategy ${strategy}:\n` +
                                `  ${error}`
                            )
                        }
                    }

                    nodeAssets.push(tokens)
                }
            }

            allWithdrawals.push(nodeWithdrawals)
            allAssets.push(nodeAssets)

            console.log(`  Prepared ${nodeWithdrawals.length} withdrawal(s) for node ${nodeId}`)
        }

        console.log('\nAll withdrawal structs and assets prepared\n')

        // Validate data structure before encoding
        console.log('Validating data structure...')
        console.log(`  Node IDs: ${nodeIds.length}`)
        console.log(`  Withdrawal arrays: ${allWithdrawals.length}`)
        console.log(`  Asset arrays: ${allAssets.length}`)

        if (allWithdrawals.length !== nodeIds.length) {
            throw new Error('Withdrawal arrays length mismatch with node IDs')
        }

        if (allAssets.length !== nodeIds.length) {
            throw new Error('Asset arrays length mismatch with node IDs')
        }

        for (let i = 0; i < nodeIds.length; i++) {
            if (allWithdrawals[i].length !== allAssets[i].length) {
                throw new Error(
                    `Withdrawal/Asset count mismatch for node ${nodeIds[i]}:\n` +
                    `  Withdrawals: ${allWithdrawals[i].length}\n` +
                    `  Assets: ${allAssets[i].length}`
                )
            }
        }

        console.log('Data structure validation passed\n')

        // Setup EmergencyRescue contract call
        const contractAddress = EMERGENCY_RESCUE_ADDRESS
        const abi = parseAbi([
            'function emergencyCompleteUndelegation(uint256[] calldata nodeIds, tuple(address staker, address delegatedTo, address withdrawer, uint256 nonce, uint32 startBlock, address[] strategies, uint256[] scaledShares)[][] calldata withdrawals, address[][][] calldata assets, address recipient) external'
        ])

        const metadata = {
            title: 'Emergency Complete Undelegation',
            description: `EMERGENCY: Proposal to complete undelegation and recover funds to ${recipientAddress}. This is step 2 of the emergency recovery process. Funds will be transferred to the specified address after EigenLayer withdrawal completion.`
        }

        // Encode function data
        console.log('Encoding transaction data...')
        const data = encodeFunctionData({
            abi,
            functionName: 'emergencyCompleteUndelegation',
            args: [
                nodeIds.map((id: number) => BigInt(id)),
                allWithdrawals as any,
                allAssets as any,
                getAddress(recipientAddress)
            ]
        })

        const metaTransactionData = {
            to: getAddress(contractAddress),
            value: '0',
            data: data,
            operation: OperationType.Call
        }

        // Create Safe transaction
        console.log('Creating Safe transaction...')
        const nonce = Number(await apiKit.getNextNonce(ADMIN))
        const safeTransaction = await protocolKitOwnerAdmin.createTransaction({
            transactions: [metaTransactionData],
            options: { nonce }
        })

        // Propose to multisig
        console.log('Proposing to multisig...')
        await proposeSafeTransaction(safeTransaction, metadata)

        console.log('\nEmergency completion proposal created successfully')
        console.log(`Recipient: ${recipientAddress}`)
        console.log('\nNext steps:')
        console.log('  1. Multisig members review and sign the proposal')
        console.log('  2. Execute the proposal')
        console.log('  3. Funds will be transferred to the recipient address')
        console.log('  4. From Safe UI, transfer funds to the original owner if needed')

    } catch (error) {
        console.log('Error: ', error)
        throw error
    }
}

// CLI usage
if (require.main === module) {
    const args = process.argv.slice(2)

    if (args.length !== 2) {
        console.error('Usage: ts-node emergencyCompleteUndelegation.ts <withdrawal-data-file> <recipient-address>')
        console.error('Example: ts-node emergencyCompleteUndelegation.ts ./data/emergency-withdrawal-data-2024-01-15.json 0x1234...')
        process.exit(1)
    }

    const [withdrawalDataFile, recipientAddress] = args
    emergencyCompleteUndelegation(withdrawalDataFile, recipientAddress)
}