import 'dotenv/config'

import { OperationType } from '@safe-global/types-kit'
import { encodeFunctionData, parseAbi, getAddress, keccak256, toBytes } from 'viem/utils'
import { apiKit, protocolKitOwnerAdmin } from '../../utils/safe'
import { ADMIN, proposeSafeTransaction } from '../../utils/forge'

/**
 * Creates a proposal for transferring a role using `grantRole` on an AccessControlUpgradeable contract
 *
 * @param contractAddress
 * @param role
 * @param newAddress
 * @returns
 */
export async function grantRole(contractAddress: string, role: string, newAddress: string) {
    try {
        if (!ADMIN) throw new Error('Env vars not set correctly.')

        let roleHash: `0x${string}`
        if (role === 'DEFAULT_ADMIN_ROLE') {
            roleHash = '0x0000000000000000000000000000000000000000000000000000000000000000'
        } else if (role.startsWith('0x')) {
            roleHash = role as `0x${string}` // If already a hex string, use directly
        } else {
            roleHash = keccak256(toBytes(role))
        }

        // Setup task params
        const abi = parseAbi(['function grantRole(bytes32,address)'])
        const metadata = {
            title: 'Grant Role',
            description: `Proposal to grant the ${role.substring(
                0,
                4
            )}...${role.substring(role.length - 4)} role to ${newAddress.substring(
                0,
                4
            )}...${newAddress.substring(newAddress.length - 4)} via manual proposal`
        }

        // Setup transaction data
        const data = encodeFunctionData({
            abi,
            functionName: 'grantRole',
            args: [roleHash, newAddress]
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
