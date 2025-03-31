import { stakeAssetsToNode } from "../tasks/stakeAssetsToNode";
import { ADMIN } from "../utils/forge";
import { apiKit } from "../utils/safe";
import { refreshDeployment } from "../workflows/refreshDeployment";

/**
 * To run this script, edit the params and run
 * `npm run stake-assets-to-node` from the `/manager` folder
 *
 * IMPORTANT:
 * Make sure the .env is updated to the LAT and the deployment you're targetting!
 *
 */
async function manualStakeAssetsToNode() {
  try {
    if (!ADMIN) throw new Error("Env vars not set correctly.");

    // ------------------------------------------------------------------------------------
    // Function params, edit these!
    // ------------------------------------------------------------------------------------
    const nodeId: string = "0";
    const assets: string[] = ["0x", "0x"];
    const amounts: string[] = ["3000000000000000000", "1000000000000000000"];
    // ------------------------------------------------------------------------------------

    await refreshDeployment();
    await stakeAssetsToNode(nodeId, assets, amounts);

    const pendingTx = (
      await apiKit.getPendingTransactions(ADMIN, {
        limit: 1,
      })
    ).results;

    console.log(
      `[Manual] Stake ${assets.length} Asset(s) To Node ${nodeId}: nonce: ${pendingTx[0].nonce}`
    );
  } catch (error) {
    console.log(error);
  }
}

(async () => {
  try {
    console.log("[Manual] Running manual tx proposal...");
    await manualStakeAssetsToNode();
  } catch {}
})();
