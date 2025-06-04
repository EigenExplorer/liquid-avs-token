import 'dotenv/config'

import { OperationType } from '@safe-global/types-kit'
import { encodeFunctionData, parseAbi, getAddress, keccak256, toBytes } from 'viem/utils'
import { apiKit, protocolKitOwnerAdmin } from '../../utils/safe'
import { ADMIN, proposeSafeTransaction } from '../../utils/forge'
import { getViemClient } from '../../utils/viemClient'

/**
 * Creates a proposal for revoking a role using `revokeRole` on an AccessControlUpgradeable contract
 *
 * @param contractAddress
 * @param role
 * @param addressToRevoke
 * @returns
 */
export async function revokeRole(contractAddress: string, role: string, addressToRevoke: string) {
    try {
        if (!ADMIN) throw new Error('Env vars not set correctly.')
        const viemClient = getViemClient()
        const roleManagerAbi = parseAbi([
            'function getRoleMemberCount(bytes32) view returns (uint256)',
            'function getRoleMember(bytes32, uint256) view returns (address)',
            'function hasRole(bytes32, address) view returns (bool)'
        ])

        let roleHash: `0x${string}`
        if (role === 'DEFAULT_ADMIN_ROLE') {
            roleHash = '0x0000000000000000000000000000000000000000000000000000000000000000'
        } else if (role.startsWith('0x')) {
            roleHash = role as `0x${string}` // If already a hex string, use directly
        } else {
            roleHash = keccak256(toBytes(role))
        }

        // Check if the address actually has the role
        const hasRole = await viemClient.readContract({
            address: getAddress(contractAddress),
            abi: roleManagerAbi,
            functionName: 'hasRole',
            args: [roleHash, addressToRevoke]
        })

        if (!hasRole) throw new Error(`Address ${addressToRevoke} does not have the ${role} role`)

        // Setup task params
        const abi = parseAbi(['function revokeRole(bytes32,address)'])
        const metadata = {
            title: 'Revoke Role',
            description: `Proposal to revoke the ${role.substring(0, 4)}...${role.substring(
                role.length - 4
            )} role to ${addressToRevoke.substring(0, 4)}...${addressToRevoke.substring(
                addressToRevoke.length - 4
            )} via manual proposal`
        }

        // Setup transaction data
        const data = encodeFunctionData({
            abi,
            functionName: 'revokeRole',
            args: [roleHash, getAddress(addressToRevoke)]
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
