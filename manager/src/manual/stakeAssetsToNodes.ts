import { type NodeAllocation, stakeAssetsToNodes } from '../tasks/stakeAssetsToNodes'
import { ADMIN } from '../utils/forge'
import { apiKit } from '../utils/safe'
import { refreshDeployment } from '../workflows/refreshDeployment'

/**
 * To run this script, edit the params and run
 * `npm run stake-assets-to-nodes` from the `/manager` folder
 *
 * IMPORTANT:
 * Make sure the .env is updated to the LAT and the deployment you're targetting!
 *
 */
async function manualStakeAssetsToNodes() {
    try {
        if (!ADMIN) throw new Error('Env vars not set correctly.')

        // ------------------------------------------------------------------------------------
        // Function params, edit these!
        // ------------------------------------------------------------------------------------
        const allocations: NodeAllocation[] = [
            {
                nodeId: '0',
                assets: ['0x'],
                amounts: ['2500000000000000000']
            },
            {
                nodeId: '1',
                assets: ['0x'],
                amounts: ['2500000000000000000']
            }
        ]
        // ------------------------------------------------------------------------------------

        await refreshDeployment()
        await stakeAssetsToNodes(allocations)

        const pendingTx = (
            await apiKit.getPendingTransactions(ADMIN, {
                limit: 1
            })
        ).results

        console.log(
            `[Manual] Stake Assets To ${allocations.length} Node(s): nonce: ${pendingTx[0].nonce}`
        )
    } catch (error) {
        console.log('[Manual] Error: ', error.message)
    }
}

;(async () => {
    console.log('[Manual] Running manual tx proposal...')
    await manualStakeAssetsToNodes()
})()
