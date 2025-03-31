import { setMaxNodes } from "../../tasks/system/setMaxNodes";
import { ADMIN } from "../../utils/forge";
import { apiKit } from "../../utils/safe";
import { refreshDeployment } from "../../workflows/refreshDeployment";

/**
 * To run this script, edit the params and run
 * `npx tsx run .src/manual/system/setMaxNodes.ts` from the `/manager` folder
 *
 * IMPORTANT:
 * Make sure the .env is updated to the LAT and the deployment you're targetting!
 *
 */
async function manualSetMaxNodes() {
  try {
    if (!ADMIN) throw new Error("Env vars not set correctly.");

    // ------------------------------------------------------------------------------------
    // Function params, edit these!
    // ------------------------------------------------------------------------------------
    const maxNodes = "10";
    // ------------------------------------------------------------------------------------

    await refreshDeployment();
    await setMaxNodes(maxNodes);

    const pendingTransactions = (
      await apiKit.getPendingTransactions(ADMIN, {
        limit: 1,
      })
    ).results;

    if (pendingTransactions.length > 0) {
      console.log(
        `[Manual][System] Set Max Nodes to ${maxNodes}: nonce: ${pendingTransactions[0].nonce}`
      );
    }
  } catch (error) {
    console.log(error);
  }
}

(async () => {
  try {
    console.log("[Manual][System] Running manual tx proposal...");
    await manualSetMaxNodes();
  } catch {}
})();
