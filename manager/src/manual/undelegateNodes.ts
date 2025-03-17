import { undelegateNodes } from "../tasks/undelegateNodes";
import { apiKit } from "../utils/safe";

/**
 * To run this script, edit the params and run
 * `npm run undelegate-nodes` from the `/manager` folder
 *
 */
export async function manualUndelegateNodes() {
  try {
    if (!process.env.MULTISIG_PUBLIC_KEY)
      throw new Error("Env vars not set correctly.");

    // ------------------------------------------------------------------------------------
    // Function params, edit these!
    // ------------------------------------------------------------------------------------
    const nodeIds: string[] = ["0", "1"];
    // ------------------------------------------------------------------------------------

    await undelegateNodes(nodeIds);

    const pendingTx = (
      await apiKit.getPendingTransactions(process.env.MULTISIG_PUBLIC_KEY, {
        limit: 1,
      })
    ).results;

    console.log(
      `[Manual] Undelegate ${nodeIds.length} Staker Node(s): nonce: ${pendingTx[0].nonce}`
    );
  } catch (error) {
    console.log(error);
  }
}
