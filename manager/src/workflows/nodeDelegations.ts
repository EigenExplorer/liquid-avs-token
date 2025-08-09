import { getPendingProposals, isContractOurs, LIQUID_TOKEN_ADDRESS } from '../utils/forge'
import { delegateNodes } from '../tasks/delegateNodes'
import { undelegateNodes } from '../tasks/undelegateNodes'
import { createStakerNodes } from '../tasks/createStakerNodes'

// --- Types ---

interface OperatorProspectResponse {
    data: OperatorProspect[]
    meta: {
        count: number
    }
}

interface OperatorProspect {
    id: number
    liquidTokenAddress: string
    operatorAddress: string
    isDelegated: boolean
    bias: number
    daysInPreference: number
    daysInWarning: number
    warningSev: number | null
    createdAt: Date
    updatedAt: Date
}

interface StakerNode {
    nodeId: number
    operatorDelegation: string
    assets: {
        asset: string
        strategy: string
        stakedAmount: string
    }[]
}

interface StakerNodesResponse {
    stakerNodes: StakerNode[]
}

// --- Constants ---

const LAT_API_URL = process.env.LAT_API_URL

const MIN_DAYS_IN_PREF = 30
const MAX_DAYS_IN_WARN_SEV1 = 30

// --- Core functions ---

/**
 * Workflow for staking unstaked assets in the `LiquidToken` contract across nodes
 *
 * @returns
 */
export async function nodeDelegations() {
    try {
        // Bail early if the multisig has any pending proposals for this LAT
        const pendingProposals = await getPendingProposals()
        for (const proposal of pendingProposals) {
            if (isContractOurs(proposal.to.toLowerCase())) {
                throw new Error(
                    `Cannot execute workflow due to existing pending tx for this LAT at nonce ${proposal.nonce}`
                )
            }
        }

        // Gather required data
        const { nodesData, operatorProspectsData } = await fetchLatState()

        // Undelegate nodes from problematic operators
        const operatorsToUndelegate = operatorProspectsData.data.filter(
            (op) => op.warningSev === 1 && op.daysInWarning > MAX_DAYS_IN_WARN_SEV1
        )

        const nodesToUndelegate = nodesData.stakerNodes.filter((node) =>
            operatorsToUndelegate.some(
                (op) => op.operatorAddress.toLowerCase() === node.operatorDelegation.toLowerCase()
            )
        )

        if (nodesToUndelegate.length > 0) {
            console.log(`[Manager] Undelegating ${nodesToUndelegate.length} nodes from problematic operators`)
            await undelegateNodes(nodesToUndelegate.map((node) => node.nodeId.toString()))
        }

        const availableNodes = nodesData.stakerNodes.filter(
            (node) => node.operatorDelegation === '0x0000000000000000000000000000000000000000'
        )

        // Operators ready for delegation today
        const operatorsReadyToday = operatorProspectsData.data.filter(
            (op) => op.daysInPreference > MIN_DAYS_IN_PREF && !op.isDelegated
        )

        // Operators who will be ready tomorrow (currently at 29 days)
        const operatorsReadyTomorrow = operatorProspectsData.data.filter(
            (op) => op.daysInPreference === MIN_DAYS_IN_PREF - 1 && !op.isDelegated
        )

        // Calculate nodes available tomorrow (remaining after today's delegation + nodes freed by today's undelegation)
        const nodesAfterTodaysDelegation = availableNodes.length - operatorsReadyToday.length
        const nodesFreedByUndelegation = nodesToUndelegate.length
        const totalNodesAvailableTomorrow = Math.max(0, nodesAfterTodaysDelegation) + nodesFreedByUndelegation

        if (operatorsReadyTomorrow.length > 0 && operatorsReadyTomorrow.length > totalNodesAvailableTomorrow) {
            const nodesToCreate = operatorsReadyTomorrow.length - totalNodesAvailableTomorrow
            console.log(
                `[Manager] Creating ${nodesToCreate} nodes for ${operatorsReadyTomorrow.length} operators becoming ready tomorrow (${totalNodesAvailableTomorrow} nodes will be available)`
            )
            await createStakerNodes(nodesToCreate)
        }

        // Delegate available nodes to operators ready
        if (operatorsReadyToday.length > 0 && availableNodes.length > 0) {
            const nodesToDelegate = availableNodes.slice(0, operatorsReadyToday.length)
            const operatorsToDelegate = operatorsReadyToday.slice(0, nodesToDelegate.length)

            console.log(
                `[Manager] Delegating ${nodesToDelegate.length} nodes to ${operatorsToDelegate.length} operators`
            )

            const signatures: { signature: string; expiry: number | string }[] = []
            const salts: string[] = []

            await delegateNodes(
                nodesToDelegate.map((node) => node.nodeId.toString()),
                operatorsToDelegate.map((op) => op.operatorAddress),
                signatures,
                salts
            )
        }

        console.log('[Manager] Node delegations complete')
    } catch (error) {
        console.log('[Manager] Error: ', error.message)
        throw error
    }
}

// --- Helper functions ---

/**
 * Structures and returns all relevant data from EE & LAT APIs
 *
 * @returns
 */
async function fetchLatState(): Promise<{
    nodesData: StakerNodesResponse
    operatorProspectsData: OperatorProspectResponse
}> {
    // Fetch all data with promises
    const nodesPromise = fetch(`${LAT_API_URL}/lat/${LIQUID_TOKEN_ADDRESS}/staker-nodes`).then((response) => {
        if (!response.ok) {
            throw new Error(`Failed to fetch staker nodes: ${response.status} ${response.statusText}`)
        }
        return response.json()
    })

    const operatorProspectsPromise = fetch(`${LAT_API_URL}/lat/${LIQUID_TOKEN_ADDRESS}/operator-insights`).then(
        (response) => {
            if (!response.ok) {
                throw new Error(`Failed to fetch Operator Insights data: ${response.status} ${response.statusText}`)
            }
            return response.json()
        }
    )

    const [nodesData, operatorProspectsData] = await Promise.all([nodesPromise, operatorProspectsPromise])

    return { nodesData, operatorProspectsData }
}
