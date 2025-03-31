import { delegateNodes } from "../tasks/delegateNodes";
import { ADMIN } from "../utils/forge";
import { apiKit } from "../utils/safe";
import { refreshDeployment } from "../workflows/refreshDeployment";

/**
 * To run this script, edit the params and run
 * `npm run delegate-nodes` from the `/manager` folder
 *
 * IMPORTANT:
 * Make sure the .env is updated to the LAT and the deployment you're targetting!
 *
 */
async function manualDelegateNodes() {
  try {
    if (!ADMIN) throw new Error("Env vars not set correctly.");

    // ------------------------------------------------------------------------------------
    // Function params, edit these!
    // ------------------------------------------------------------------------------------
    const nodeIds: string[] = ["0", "1"];
    const operators: string[] = ["0x", "0x"];
    const signatures: { signature: string; expiry: number | string }[] = [
      {
        signature:
          "0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff",
        expiry: 0,
      },
      {
        signature:
          "0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff",
        expiry: 0,
      },
    ];
    const salts: string[] = [
      "0x0000000000000000000000000000000000000000000000000000000000000000",
      "0x0000000000000000000000000000000000000000000000000000000000000000",
    ];
    // ------------------------------------------------------------------------------------

    await refreshDeployment();
    await delegateNodes(nodeIds, operators, signatures, salts);

    const pendingTx = (
      await apiKit.getPendingTransactions(ADMIN, {
        limit: 1,
      })
    ).results;

    console.log(
      `[Manual] Delegate ${nodeIds.length} Staker Nodes: nonce: ${pendingTx[0].nonce}`
    );
  } catch (error) {
    console.log(error);
  }
}

(async () => {
  try {
    console.log("[Manual] Running manual tx proposal...");
    await manualDelegateNodes();
  } catch {}
})();
