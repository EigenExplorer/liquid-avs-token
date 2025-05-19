import { setVolatilityThreshold } from "../../tasks/system/setVolatilityThreshold";
import { ADMIN } from "../../utils/forge";
import { apiKit } from "../../utils/safe";
import { refreshDeployment } from "../../workflows/refreshDeployment";

/**
 * To run this script, edit the params and run
 * `npx tsx ./src/manual/system/setVolatilityThreshold.ts` from the `/manager` folder
 *
 * IMPORTANT:
 * Make sure the .env is updated to the LAT and the deployment you're targetting!
 *
 */
async function manualSetVolatilityThreshold() {
  try {
    if (!ADMIN) throw new Error("Env vars not set correctly.");

    // ------------------------------------------------------------------------------------
    // Function params, edit these!
    // ------------------------------------------------------------------------------------
    const assetAddress = "0x";
    const newThreshold = "50000000000000000";
    // ------------------------------------------------------------------------------------

    await refreshDeployment();
    await setVolatilityThreshold(assetAddress, newThreshold);

    const pendingTransactions = (
      await apiKit.getPendingTransactions(ADMIN, {
        limit: 1,
      })
    ).results;

    if (pendingTransactions.length > 0) {
      console.log(
        `[Manual][System] Set Volatility Threshold for ${assetAddress}: nonce: ${pendingTransactions[0].nonce}`
      );
    }
  } catch (error) {
    console.log("[Manual] Error: ", error.message);
  }
}

(async () => {
  console.log("[Manual] Running manual tx proposal...");
  await manualSetVolatilityThreshold();
})();
