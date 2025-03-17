import {
  type NodeAllocation,
  stakeAssetsToNodes,
} from "../tasks/stakeAssetsToNodes";
import { apiKit } from "../utils/safe";

/**
 * To run this script, edit the params and run
 * `npm run stake-assets-to-nodes` from the `/manager` folder
 *
 */
async function manualStakeAssetsToNodes() {
  try {
    if (!process.env.MULTISIG_PUBLIC_KEY || !process.env.SIGNER_PUBLIC_KEY)
      throw new Error("Env vars not set correctly.");

    // ------------------------------------------------------------------------------------
    // Function params, edit these!
    // ------------------------------------------------------------------------------------
    const allocations: NodeAllocation[] = [
      {
        nodeId: "0",
        assets: ["0x"],
        amounts: ["2500000000000000000"],
      },
      {
        nodeId: "1",
        assets: ["0x"],
        amounts: ["2500000000000000000"],
      },
    ];
    // ------------------------------------------------------------------------------------

    await stakeAssetsToNodes(allocations);

    const pendingTx = (
      await apiKit.getPendingTransactions(process.env.MULTISIG_PUBLIC_KEY, {
        limit: 1,
      })
    ).results;

    console.log(
      `[Manual] Stake Assets To ${allocations.length} Node(s): nonce: ${pendingTx[0].nonce}`
    );
  } catch (error) {
    console.log(error);
  }
}

(async () => {
  try {
    console.log("[Manual] Running manual tx proposal...");
    await manualStakeAssetsToNodes();
  } catch {}
})();
