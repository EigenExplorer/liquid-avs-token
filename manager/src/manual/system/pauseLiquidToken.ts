import { pauseLiquidToken } from "../../tasks/system/pauseLiquidToken";
import { PAUSER } from "../../utils/forge";
import { apiKit } from "../../utils/safe";
import { refreshDeployment } from "../../workflows/refreshDeployment";

/**
 * To run this script, edit the params and run
 * `npx tsx ./src/manual/system/pauseLiquidToken.ts` from the `/manager` folder
 *
 * IMPORTANT:
 * Make sure the .env is updated to the LAT and the deployment you're targetting!
 *
 */
async function manualPauseLiquidToken() {
  try {
    if (!PAUSER) throw new Error("Env vars not set correctly.");

    await refreshDeployment();
    await pauseLiquidToken();

    const pendingTransactions = (
      await apiKit.getPendingTransactions(PAUSER, {
        limit: 1,
      })
    ).results;

    if (pendingTransactions.length > 0) {
      console.log(
        `[Manual] Pause Contract: nonce: ${pendingTransactions[0].nonce}`
      );
    }
  } catch (error) {
    console.log(error);
  }
}

(async () => {
  try {
    console.log("[Manual][System] Running manual tx proposal...");
    await manualPauseLiquidToken();
  } catch {}
})();
