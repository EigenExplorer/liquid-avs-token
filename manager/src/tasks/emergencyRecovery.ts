import 'dotenv/config'

import { emergencyUndelegateAllNodes } from './system/emergencyUndelegateAllNodes'
import { queryFromTransactionReceipt } from './system/queryEmergencyWithdrawalData'
import { checkWithdrawalStatus } from './system/checkWithdrawalStatus'
import { emergencyCompleteUndelegation } from './system/emergencyCompleteUndelegation'

const STEPS = {
    UNDELEGATE: 'undelegate',
    QUERY: 'query',
    CHECK: 'check',
    COMPLETE: 'complete'
}

async function main() {
    const args = process.argv.slice(2)
    const command = args[0]

    console.log('\n EMERGENCY RECOVERY PROCESS \n')

    switch (command) {
        case STEPS.UNDELEGATE:
            console.log('Step 1: Creating undelegation proposal...')
            await emergencyUndelegateAllNodes()
            console.log('\n Next steps:')
            console.log('  1. Multisig members sign and execute the proposal')
            console.log('  2. Run: npm run emergency:query -- <transaction-hash>')
            console.log('  3. Wait 7 days')
            console.log('  4. Run: npm run emergency:complete -- <data-file> <recipient>')
            break

        case STEPS.QUERY:
            if (!args[1]) {
                console.error(' Error: Transaction hash required')
                console.error('Usage: npm run emergency:query -- <transaction-hash>')
                process.exit(1)
            }
            console.log('Step 2: Querying withdrawal data...')
            await queryFromTransactionReceipt(args[1])
            console.log('\n Next steps:')
            console.log('  1. Save the generated JSON file')
            console.log('  2. Wait 7 days (50,400 blocks)')
            console.log('  3. Check status: npm run emergency:check -- <data-file>')
            console.log('  4. Complete: npm run emergency:complete -- <data-file> <recipient>')
            break

        case STEPS.CHECK:
            if (!args[1]) {
                console.error(' Error: Withdrawal data file required')
                console.error('Usage: npm run emergency:check -- <withdrawal-data-file>')
                process.exit(1)
            }
            console.log('Checking withdrawal status...')
            await checkWithdrawalStatus(args[1])
            break

        case STEPS.COMPLETE:
            if (!args[1] || !args[2]) {
                console.error(' Error: Withdrawal data file and recipient address required')
                console.error('Usage: npm run emergency:complete -- <withdrawal-data-file> <recipient-address>')
                process.exit(1)
            }
            console.log('Step 3: Creating completion proposal...')
            await emergencyCompleteUndelegation(args[1], args[2])
            console.log('\n Next steps:')
            console.log('  1. Multisig members sign and execute the proposal')
            console.log('  2. Funds will be transferred to the recipient address')
            console.log('  3. From Safe UI, transfer funds to the original owner')
            break

        default:
            console.error(' Error: Invalid command')
            console.log('\nAvailable commands:')
            console.log('  undelegate - Step 1: Create undelegation proposal')
            console.log('  query      - Step 2: Query withdrawal data after execution')
            console.log('  check      - Check if withdrawals are ready')
            console.log('  complete   - Step 3: Create completion proposal (after 7 days)')
            console.log('\nUsage:')
            console.log('  npm run emergency:undelegate')
            console.log('  npm run emergency:query -- <transaction-hash>')
            console.log('  npm run emergency:check -- <data-file>')
            console.log('  npm run emergency:complete -- <data-file> <recipient>')
            process.exit(1)
    }
}

main().catch(console.error)