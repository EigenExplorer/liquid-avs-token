import 'dotenv/config'

import { createPublicClient, http, parseAbi } from 'viem'
import { mainnet, holesky } from 'viem/chains'
import { readFileSync } from 'fs'
import { LIQUID_TOKEN_MANAGER_ADDRESS, DEPLOYMENT } from '../../utils/forge'

/**
 * Checks if withdrawals are ready to be completed
 * 
 * @param withdrawalDataFile Path to the saved withdrawal data JSON file
 * @returns 
 */
export async function checkWithdrawalStatus(withdrawalDataFile: string) {
    try {
        // Load saved withdrawal data
        console.log(' Loading withdrawal data from:', withdrawalDataFile)
        const savedData = JSON.parse(readFileSync(withdrawalDataFile, 'utf-8'))
        const nodeIds = savedData.nodeIds
        const withdrawalData = savedData.withdrawalData

        // Setup client
        const chain = DEPLOYMENT === 'mainnet' ? mainnet : holesky
        const client = createPublicClient({
            chain,
            transport: http()
        })

        const currentBlock = await client.getBlockNumber()
        const MIN_WITHDRAWAL_DELAY = BigInt(50400) // ~7 days

        console.log(`\n Withdrawal Status Check`)
        console.log(`Current block: ${currentBlock}\n`)

        let allReady = true

        for (const nodeId of nodeIds) {
            console.log(`Node ${nodeId}:`)
            const withdrawals = withdrawalData[nodeId]

            for (let i = 0; i < withdrawals.length; i++) {
                const withdrawal = withdrawals[i]
                const startBlock = BigInt(withdrawal.startBlock)
                const requiredBlock = startBlock + MIN_WITHDRAWAL_DELAY
                const blocksRemaining = requiredBlock > currentBlock ? requiredBlock - currentBlock : BigInt(0)
                const isReady = currentBlock >= requiredBlock

                console.log(`  Withdrawal ${i}:`)
                console.log(`    Start Block: ${startBlock}`)
                console.log(`    Required Block: ${requiredBlock}`)
                console.log(`    Blocks Remaining: ${blocksRemaining}`)
                console.log(`    Status: ${isReady ? ' READY' : ' WAITING'}`)

                if (!isReady) {
                    allReady = false
                    // Estimate time remaining (assuming 12 second blocks)
                    const secondsRemaining = Number(blocksRemaining) * 12
                    const hoursRemaining = Math.floor(secondsRemaining / 3600)
                    const minutesRemaining = Math.floor((secondsRemaining % 3600) / 60)
                    console.log(`    Estimated Time: ~${hoursRemaining}h ${minutesRemaining}m`)
                }
                console.log()
            }
        }

        if (allReady) {
            console.log(' All withdrawals are ready to be completed!')
            console.log(' You can now run: emergencyCompleteUndelegation.ts')
        } else {
            console.log(' Some withdrawals are not ready yet. Please wait.')
        }

        return allReady
    } catch (error) {
        console.log('Error: ', error)
        throw error
    }
}

// CLI usage
if (require.main === module) {
    const args = process.argv.slice(2)
    
    if (args.length !== 1) {
        console.error('Usage: ts-node checkWithdrawalStatus.ts <withdrawal-data-file>')
        console.error('Example: ts-node checkWithdrawalStatus.ts ./data/emergency-withdrawal-data-2024-01-15.json')
        process.exit(1)
    }

    const [withdrawalDataFile] = args
    checkWithdrawalStatus(withdrawalDataFile)
}