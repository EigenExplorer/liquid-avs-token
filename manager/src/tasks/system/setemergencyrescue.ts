import 'dotenv/config'

import { OperationType } from '@safe-global/types-kit'
import { encodeFunctionData, parseAbi, getAddress } from 'viem/utils'
import { apiKit, protocolKitOwnerAdmin } from '../../utils/safe'
import { ADMIN, STAKER_NODE_COORDINATOR_ADDRESS, EMERGENCY_RESCUE_ADDRESS, proposeSafeTransaction } from '../../utils/forge'

/**
 * Creates a proposal to set the EmergencyRescue address in StakerNodeCoordinator
 * This must be done after deploying EmergencyRescue and before executing emergency undelegation
 */
export async function setEmergencyRescue() {
    try {
        if (!ADMIN) throw new Error('Env vars not set correctly.')
        if (!EMERGENCY_RESCUE_ADDRESS) throw new Error('EMERGENCY_RESCUE_ADDRESS not set')

        const contractAddress = STAKER_NODE_COORDINATOR_ADDRESS
        const abi = parseAbi(['function setEmergencyRescue(address)'])
        const metadata = {
            title: 'Set Emergency Rescue Contract',
            description: `Proposal to set EmergencyRescue contract address to ${EMERGENCY_RESCUE_ADDRESS} in StakerNodeCoordinator. This enables emergency fund recovery functionality.`
        }

        const data = encodeFunctionData({
            abi,
            functionName: 'setEmergencyRescue',
            args: [EMERGENCY_RESCUE_ADDRESS]
        })

        const metaTransactionData = {
            to: getAddress(contractAddress),
            value: '0',
            data: data,
            operation: OperationType.Call
        }

        const nonce = Number(await apiKit.getNextNonce(ADMIN))
        const safeTransaction = await protocolKitOwnerAdmin.createTransaction({
            transactions: [metaTransactionData],
            options: { nonce }
        })

        await proposeSafeTransaction(safeTransaction, metadata)

        console.log(' Set Emergency Rescue proposal created successfully')
        console.log(` EmergencyRescue address: ${EMERGENCY_RESCUE_ADDRESS}`)
    } catch (error) {
        console.log('Error: ', error)
        return []
    }
}

if (require.main === module) {
    setEmergencyRescue()
}