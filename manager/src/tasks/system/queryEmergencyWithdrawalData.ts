import 'dotenv/config'

import { createPublicClient, http, parseAbi } from 'viem'
import { mainnet, holesky } from 'viem/chains'
import { writeFileSync } from 'fs'
import { EMERGENCY_RESCUE_ADDRESS, DEPLOYMENT } from '../../utils/forge'

/**
 * Queries and saves all emergency withdrawal data after emergencyUndelegateAllNodes execution
 * This data is needed to complete the undelegation after 7 days
 * 
 * @param nodeIds Array of node IDs that were undelegated
 * @returns 
 */
export async function queryEmergencyWithdrawalData(nodeIds: number[]) {
    try {
        // Setup client
        const chain = DEPLOYMENT === 'mainnet' ? mainnet : holesky
        const client = createPublicClient({
            chain,
            transport: http()
        })

        const contractAddress = EMERGENCY_RESCUE_ADDRESS
        const abi = parseAbi([
            'function getAllEmergencyWithdrawalData(uint256) view returns (tuple(address[] strategies, uint256[] depositShares, bytes32[] withdrawalRoots, uint256 nonce, address operator, uint256 startBlock, bool exists)[])',
            'function emergencyWithdrawalCount(uint256) view returns (uint256)'
        ])

        console.log('Querying emergency withdrawal data...\n')

        const allWithdrawalData: any = {}

        for (const nodeId of nodeIds) {
            console.log(`Querying Node ${nodeId}...`)

            // Get withdrawal count
            const count = await client.readContract({
                address: contractAddress as `0x${string}`,
                abi,
                functionName: 'emergencyWithdrawalCount',
                args: [BigInt(nodeId)]
            })

            console.log(`  - Found ${count} withdrawal(s)`)

            // Get all withdrawal data
            const withdrawalData = await client.readContract({
                address: contractAddress as `0x${string}`,
                abi,
                functionName: 'getAllEmergencyWithdrawalData',
                args: [BigInt(nodeId)]
            })

            // Map withdrawal data with all fields including withdrawalRoots
            const withdrawalsWithAllData = (withdrawalData as any[]).map((withdrawal: any) => {
                return {
                    strategies: withdrawal.strategies,
                    depositShares: withdrawal.depositShares.map((share: bigint) => share.toString()),
                    withdrawalRoots: withdrawal.withdrawalRoots,
                    nonce: withdrawal.nonce.toString(),
                    operator: withdrawal.operator,
                    startBlock: withdrawal.startBlock.toString(),
                    exists: withdrawal.exists
                }
            })

            allWithdrawalData[nodeId] = withdrawalsWithAllData

            console.log(`  - Operator: ${withdrawalsWithAllData[0]?.operator}`)
            console.log(`  - Start Block: ${withdrawalsWithAllData[0]?.startBlock}`)
            console.log(`  - Strategies: ${withdrawalsWithAllData[0]?.strategies.length}`)
            console.log(`  - Withdrawal Roots: ${withdrawalsWithAllData[0]?.withdrawalRoots.length}\n`)
        }

        // Save to file
        const timestamp = new Date().toISOString().replace(/[:.]/g, '-')
        const filename = `emergency-withdrawal-data-${timestamp}.json`
        const filepath = `./data/${filename}`

        const output = {
            timestamp: new Date().toISOString(),
            deployment: DEPLOYMENT,
            nodeIds,
            withdrawalData: allWithdrawalData,
            notes: {
                minimumWaitBlocks: '50400',
                minimumWaitTime: '7 days',
                nextStep: 'Run emergencyCompleteUndelegation.ts after 7 days'
            }
        }

        writeFileSync(filepath, JSON.stringify(output, null, 2))

        console.log('Emergency withdrawal data saved successfully')
        console.log(`File: ${filepath}`)
        console.log('\nSAVE THIS FILE - It is required to complete the undelegation')
        console.log('Wait at least 7 days (50,400 blocks) before running the completion script')

        return output
    } catch (error) {
        console.log('Error: ', error)
        throw error
    }
}

/**
 * Helper to query from transaction receipt
 */
export async function queryFromTransactionReceipt(txHash: string) {
    try {
        const chain = DEPLOYMENT === 'mainnet' ? mainnet : holesky
        const client = createPublicClient({
            chain,
            transport: http()
        })

        // Get transaction receipt
        const receipt = await client.getTransactionReceipt({ hash: txHash as `0x${string}` })

        // Parse EmergencyUndelegationInitiated event
        const abi = parseAbi([
            'event EmergencyUndelegationInitiated(uint256[] nodeIds, address indexed initiator)'
        ])

        const logs = receipt.logs
        const relevantLog = logs.find(log => {
            try {
                const decoded = client.decodeEventLog({
                    abi,
                    data: log.data,
                    topics: log.topics
                })
                return decoded.eventName === 'EmergencyUndelegationInitiated'
            } catch {
                return false
            }
        })

        if (!relevantLog) {
            throw new Error('EmergencyUndelegationInitiated event not found in transaction')
        }

        const decoded = client.decodeEventLog({
            abi,
            data: relevantLog.data,
            topics: relevantLog.topics
        })

        const nodeIds = (decoded.args as any).nodeIds.map((id: bigint) => Number(id))

        console.log(`Found ${nodeIds.length} undelegated nodes:`, nodeIds)

        // Query the data
        return await queryEmergencyWithdrawalData(nodeIds)
    } catch (error) {
        console.log('Error: ', error)
        throw error
    }
}

// CLI usage
if (require.main === module) {
    const args = process.argv.slice(2)

    if (args[0] === '--tx') {
        const txHash = args[1]
        if (!txHash) {
            console.error('Usage: ts-node queryEmergencyWithdrawalData.ts --tx <transaction-hash>')
            process.exit(1)
        }
        queryFromTransactionReceipt(txHash)
    } else if (args[0] === '--nodes') {
        const nodeIds = args.slice(1).map(id => parseInt(id))
        if (nodeIds.length === 0) {
            console.error('Usage: ts-node queryEmergencyWithdrawalData.ts --nodes <nodeId1> <nodeId2> ...')
            process.exit(1)
        }
        queryEmergencyWithdrawalData(nodeIds)
    } else {
        console.error('Usage:')
        console.error('  From transaction: ts-node queryEmergencyWithdrawalData.ts --tx <transaction-hash>')
        console.error('  From node IDs:    ts-node queryEmergencyWithdrawalData.ts --nodes <nodeId1> <nodeId2> ...')
        process.exit(1)
    }
}