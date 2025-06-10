import { batchUpdateRates } from '../../tasks/system/batchUpdateRates'
import { ADMIN } from '../../utils/forge'
import { apiKit } from '../../utils/safe'
import { refreshDeployment } from '../../workflows/refreshDeployment'

/**
 * To run this script, edit the params and run
 * `npx tsx ./src/manual/system/batchUpdateRates.ts` from the `/manager` folder
 *
 * IMPORTANT:
 * Make sure the .env is updated to the LAT and the deployment you're targetting!
 *
 */
async function manualBatchUpdateRates() {
    try {
        if (!ADMIN) throw new Error('Env vars not set correctly.')

        // ------------------------------------------------------------------------------------
        // Function params, edit these!
        // ------------------------------------------------------------------------------------
        const tokenAddresses: string[] = ['0x', '0x']
        const rates: bigint[] = [0n, 0n]
        // ------------------------------------------------------------------------------------

        await refreshDeployment()
        await batchUpdateRates(tokenAddresses, rates)

        const pendingTransactions = (
            await apiKit.getPendingTransactions(ADMIN, {
                limit: 1
            })
        ).results

        if (pendingTransactions.length > 0) {
            console.log(
                `[Manual][System] Update rates of ${tokenAddresses.length} tokens: nonce: ${pendingTransactions[0].nonce}`
            )
        }
    } catch (error) {
        console.log('[Manual] Error: ', error.message)
    }
}

;(async () => {
    console.log('[Manual] Running manual tx proposal...')
    await manualBatchUpdateRates()
})()
