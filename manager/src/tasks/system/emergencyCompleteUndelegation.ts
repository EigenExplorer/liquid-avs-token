import 'dotenv/config'

import { OperationType } from '@safe-global/types-kit'
import { encodeFunctionData, parseAbi, getAddress, encodeAbiParameters } from 'viem/utils'
import { createPublicClient, http } from 'viem'
import { mainnet, holesky } from 'viem/chains'
import { readFileSync } from 'fs'
import { apiKit, protocolKitOwnerAdmin } from '../../utils/safe'
import { ADMIN, LIQUID_TOKEN_MANAGER_ADDRESS, DEPLOYMENT, proposeSafeTransaction } from '../../utils/forge'

/**
 * Creates a proposal for `emergencyCompleteUndelegation` on `LiquidTokenManager`
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
        console.log(' Loading withdrawal data from:', withdrawalDataFile)
        const savedData = JSON.parse(readFileSync(withdrawalDataFile, 'utf-8'))
        const nodeIds = savedData.nodeIds
        const withdrawalData = savedData.withdrawalData

        console.log(` Processing ${nodeIds.length} nodes...\n`)

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
                        ` Withdrawal delay not met for node ${nodeId}!\n` +
                        `   Current block: ${currentBlock}\n` +
                        `   Required block: ${requiredBlock}\n` +
                        `   Blocks remaining: ${requiredBlock - currentBlock}`
                    )
                }
            }
        }

        console.log(' Withdrawal delay check passed\n')

        // Reconstruct withdrawal structs
        console.log(' Reconstructing withdrawal structs...')
        
        const contractAddress = LIQUID_TOKEN_MANAGER_ADDRESS
        const reconstructAbi = parseAbi([
            'function reconstructWithdrawal(uint256,address[],uint256[],uint256,address,uint256) view returns (tuple(address staker, address delegatedTo, address withdrawer, uint256 nonce, uint32 startBlock, address[] strategies, uint256[] scaledShares), bytes32)'
        ])

        const allWithdrawals: any[] = []
        const allAssets: any[] = []

        for (const nodeId of nodeIds) {
            const nodeWithdrawals: any[] = []
            const nodeAssets: any[] = []

            const withdrawals = withdrawalData[nodeId]

            for (const withdrawal of withdrawals) {
                // Reconstruct the withdrawal struct
                const [reconstructedWithdrawal, withdrawalRoot] = await client.readContract({
                    address: contractAddress as `0x${string}`,
                    abi: reconstructAbi,
                    functionName: 'reconstructWithdrawal',
                    args: [
                        BigInt(nodeId),
                        withdrawal.strategies,
                        withdrawal.depositShares.map((s: string) => BigInt(s)),
                        BigInt(withdrawal.nonce),
                        withdrawal.operator,
                        BigInt(withdrawal.startBlock)
                    ]
                })

                nodeWithdrawals.push(reconstructedWithdrawal)
                nodeAssets.push(withdrawal.tokens)

                console.log(`  Node ${nodeId}: Reconstructed withdrawal`)
                console.log(`    - Root: ${withdrawalRoot}`)
                console.log(`    - Strategies: ${withdrawal.strategies.length}`)
            }

            allWithdrawals.push(nodeWithdrawals)
            allAssets.push(nodeAssets)
        }

        console.log(' Withdrawal structs reconstructed\n')

        // Setup task params
        const abi = parseAbi([
            'function emergencyCompleteUndelegation(uint256[],tuple(address,address,address,uint256,uint32,address[],uint256[])[],address[][][],address)'
        ])
        const metadata = {
            title: 'Emergency Complete Undelegation',
            description: `EMERGENCY: Proposal to complete undelegation and recover funds to ${recipientAddress}. This is step 2 of the emergency recovery process. Funds will be transferred to the specified address.`
        }

        // Setup transaction data
        const data = encodeFunctionData({
            abi,
            functionName: 'emergencyCompleteUndelegation',
            args: [
                nodeIds.map((id: number) => BigInt(id)),
                allWithdrawals as any,
                allAssets as any,
                recipientAddress
            ]
        })

        const metaTransactionData = {
            to: getAddress(contractAddress),
            value: '0',
            data: data,
            operation: OperationType.Call
        }

        // Create transaction
        const nonce = Number(await apiKit.getNextNonce(ADMIN))
        const safeTransaction = await protocolKitOwnerAdmin.createTransaction({
            transactions: [metaTransactionData],
            options: { nonce }
        })

        // Propose transactions to multisig
        await proposeSafeTransaction(safeTransaction, metadata)

        console.log(' Emergency completion proposal created successfully')
        console.log(` Funds will be sent to: ${recipientAddress}`)
        console.log('  After execution, funds can be transferred to the original owner from Safe UI')
    } catch (error) {
        console.log('Error: ', error)
        return []
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