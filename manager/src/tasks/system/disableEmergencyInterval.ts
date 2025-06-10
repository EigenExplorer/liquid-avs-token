import 'dotenv/config'

import { OperationType } from '@safe-global/types-kit'
import { encodeFunctionData, parseAbi, getAddress } from 'viem/utils'
import { apiKit, protocolKitOwnerAdmin } from '../../utils/safe'
import { ADMIN, TOKEN_REGISTRY_ORACLE_ADDRESS, proposeSafeTransaction } from '../../utils/forge'

/**
 * Creates a proposal for `disableEmergencyInterval` on `TokenRegistryOracle`
 *
 * @returns
 */
export async function disableEmergencyInterval() {
    try {
        if (!ADMIN) throw new Error('Env vars not set correctly.')

        // Setup task params
        const contractAddress = TOKEN_REGISTRY_ORACLE_ADDRESS
        const abi = parseAbi(['function disableEmergencyInterval()'])
        const metadata = {
            title: 'Disable Emergency Interval',
            description: 'Proposal to disable emergency mode and the emergency interval via manual proposal'
        }

        // Setup transaction data
        const data = encodeFunctionData({
            abi,
            functionName: 'disableEmergencyInterval',
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
    } catch (error) {
        console.log('Error: ', error)
        return []
    }
}
