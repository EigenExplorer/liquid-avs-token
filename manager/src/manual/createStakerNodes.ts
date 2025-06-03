import { createStakerNodes } from '../tasks/createStakerNodes'
import { ADMIN } from '../utils/forge'
import { apiKit } from '../utils/safe'
import { refreshDeployment } from '../workflows/refreshDeployment'

/**
 * To run this script, edit the params and run
 * `npm run create-staker-nodes` from the `/manager` folder
 *
 * IMPORTANT:
 * Make sure the .env is updated to the LAT and the deployment you're targetting!
 *
 */
async function manualCreateStakerNodes() {
    try {
        if (!ADMIN) throw new Error('Env vars not set correctly.')

        // ------------------------------------------------------------------------------------
        // Function params, edit these!
        // ------------------------------------------------------------------------------------
        const count: number = 1
        // ------------------------------------------------------------------------------------

        await refreshDeployment()
        await createStakerNodes(count)

        const pendingTransactions = (
            await apiKit.getPendingTransactions(ADMIN, {
                limit: count
            })
        ).results

        for (const [index, pendingTx] of pendingTransactions.entries()) {
            console.log(
                `[Manual] Create ${count} Staker Nodes: ${index + 1}: nonce: ${pendingTx.nonce}`
            )
        }
    } catch (error) {
        console.log('[Manual] Error: ', error.message)
    }
}

;(async () => {
    console.log('[Manual] Running manual tx proposal...')
    await manualCreateStakerNodes()
})()
