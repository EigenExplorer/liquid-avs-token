import { undelegateNodes } from '../tasks/undelegateNodes'
import { ADMIN } from '../utils/forge'
import { apiKit } from '../utils/safe'
import { refreshDeployment } from '../workflows/refreshDeployment'

/**
 * To run this script, edit the params and run
 * `npm run undelegate-nodes` from the `/manager` folder
 *
 * IMPORTANT:
 * Make sure the .env is updated to the LAT and the deployment you're targetting!
 *
 */
async function manualUndelegateNodes() {
    try {
        if (!ADMIN) throw new Error('Env vars not set correctly.')

        // ------------------------------------------------------------------------------------
        // Function params, edit these!
        // ------------------------------------------------------------------------------------
        const nodeIds: string[] = ['0', '1']
        // ------------------------------------------------------------------------------------

        await refreshDeployment()
        await undelegateNodes(nodeIds)

        const pendingTx = (
            await apiKit.getPendingTransactions(ADMIN, {
                limit: 1
            })
        ).results

        console.log(`[Manual] Undelegate ${nodeIds.length} Staker Node(s): nonce: ${pendingTx[0].nonce}`)
    } catch (error) {
        console.log('[Manual] Error: ', error.message)
    }
}

;(async () => {
    console.log('[Manual] Running manual tx proposal...')
    await manualUndelegateNodes()
})()
