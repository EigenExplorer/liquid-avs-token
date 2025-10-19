import 'dotenv/config'

import { OperationType } from '@safe-global/types-kit'
import { encodeFunctionData, parseAbi, getAddress } from 'viem/utils'
import { apiKit, protocolKitOwnerAdmin } from '../../utils/safe'
import { ADMIN, LIQUID_TOKEN_MANAGER_ADDRESS, proposeSafeTransaction } from '../../utils/forge'

/**
 * Creates a proposal for `emergencyUndelegateAllNodes` on `LiquidTokenManager`
 * This will undelegate all nodes and queue withdrawals on EigenLayer
 * 
 * IMPORTANT: After execution, save the returned nodeIds and withdrawalRoots
 * for use in the completion step after 7 days
 * 
 * @returns 
 */
export async function emergencyUndelegateAllNodes() {
    try {
        if (!ADMIN) throw new Error('Env vars not set correctly.')

        // Setup task params
        const contractAddress = LIQUID_TOKEN_MANAGER_ADDRESS
        const abi = parseAbi(['function emergencyUndelegateAllNodes() returns (uint256[], bytes32[][])'])
        const metadata = {
            title: 'Emergency Undelegate All Nodes',
            description: 'EMERGENCY: Proposal to undelegate all staker nodes from their operators and queue EigenLayer withdrawals. This is step 1 of the emergency recovery process. After execution, wait 7 days before completing the undelegation.'
        }

        // Setup transaction data
        const data = encodeFunctionData({
            abi,
            functionName: 'emergencyUndelegateAllNodes',
            args: []
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

        console.log(' Emergency undelegation proposal created successfully')
        console.log('  IMPORTANT: After execution, run the query script to save withdrawal data')
        console.log('  Wait 7 days before executing the completion step')
    } catch (error) {
        console.log('Error: ', error)
        return []
    }
}