import 'dotenv/config'

import { OperationType } from '@safe-global/types-kit'
import { encodeFunctionData, parseAbi, getAddress } from 'viem/utils'
import { apiKit, protocolKitOwnerAdmin } from '../../utils/safe'
import { ADMIN, proposeSafeTransaction } from '../../utils/forge'

/**
 * Creates a proposal for transferring ProxyAdmin ownership to enable V1-V2 migration
 * This should be executed BEFORE running the migration script in private hardhat repo
 *
 * @param proxyAdminAddress - Address of the ProxyAdmin contract
 * @param newOwnerAddress - Address of the deployer who will execute the migration
 * @returns
 */
export async function transferProxyAdminForMigration(proxyAdminAddress: string, newOwnerAddress: string) {
    try {
        if (!ADMIN) throw new Error('Env vars not set correctly.')

        // Setup task params
        const contractAddress = proxyAdminAddress
        const abi = parseAbi(['function transferOwnership(address)'])
        const metadata = {
            title: `Transfer ProxyAdmin Ownership for V2 Migration`,
            description: `Proposal to transfer ProxyAdmin ownership from multisig (${ADMIN}) to deployer (${newOwnerAddress}) to enable V1-V2 migration. The deployer will automatically transfer ownership back to multisig after migration completion.`
        }

        // Setup transaction data
        const data = encodeFunctionData({
            abi,
            functionName: 'transferOwnership',
            args: [getAddress(newOwnerAddress)]
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

        console.log(` Proposal created to transfer ProxyAdmin ownership`)
        console.log(`   From: ${ADMIN} (multisig)`)
        console.log(`   To: ${newOwnerAddress} (deployer)`)
        console.log(`   ProxyAdmin: ${proxyAdminAddress}`)
        console.log(``)
        console.log(`  NEXT STEPS:`)
        console.log(`   1. Execute this multisig proposal`)
        console.log(`   2. Run migration script with the deployer account`)
        console.log(`   3. Migration script will automatically transfer ownership back to multisig`)

    } catch (error) {
        console.log('Error: ', error)
        return []
    }
}

/**
 * Convenience function to restore ProxyAdmin ownership back to multisig
 * This is not needed as the migration script handles it automatically in our hardhat part,
 * but provided as a backup option
 *
 * @param proxyAdminAddress - Address of the ProxyAdmin contract
 * @param deployerAddress - Current owner (deployer) who will transfer back to multisig
 * @returns
 */
export async function restoreProxyAdminOwnership(proxyAdminAddress: string, deployerAddress: string) {
    try {
        if (!ADMIN) throw new Error('Env vars not set correctly.')

        // Setup task params
        const contractAddress = proxyAdminAddress
        const abi = parseAbi(['function transferOwnership(address)'])
        const metadata = {
            title: `Restore ProxyAdmin Ownership to Multisig`,
            description: `Emergency proposal to restore ProxyAdmin ownership from deployer (${deployerAddress}) back to multisig (${ADMIN}). This is typically handled automatically by the migration script.`
        }

        // Setup transaction data - NOTE: This would need to be signed by the deployer, not multisig
        const data = encodeFunctionData({
            abi,
            functionName: 'transferOwnership',
            args: [getAddress(ADMIN)]
        })
        const metaTransactionData = {
            to: getAddress(contractAddress),
            value: '0',
            data: data,
            operation: OperationType.Call
        }

        console.log(`  WARNING: This transaction must be executed by the deployer (${deployerAddress}), not the multisig!`)
        console.log(`   Transaction data: ${data}`)
        console.log(`   Target: ${contractAddress}`)

        // This is mainly for reference -EXC NEEDTOBEDONE BY DEPLOYER
        return metaTransactionData

    } catch (error) {
        console.log('Error: ', error)
        return []
    }
}