import { createStakerNodes } from "../tasks/createStakerNodes";
import { apiKit } from "../utils/safe";

/**
 * To run this script, edit the params and run
 * `npm run create-staker-nodes` from the `/manager` folder
 *
 */
async function manualCreateStakerNodes() {
  try {
    if (
      !process.env.MULTISIG_ADMIN_PUBLIC_KEY ||
      !process.env.SIGNER_ADMIN_PUBLIC_KEY
    )
      throw new Error("Env vars not set correctly.");

    // ------------------------------------------------------------------------------------
    // Function params, edit these!
    // ------------------------------------------------------------------------------------
    const count: number = 1;
    // ------------------------------------------------------------------------------------

    await createStakerNodes(count);

    const pendingTransactions = (
      await apiKit.getPendingTransactions(
        process.env.MULTISIG_ADMIN_PUBLIC_KEY,
        {
          limit: count,
        }
      )
    ).results;

    for (const [index, pendingTx] of pendingTransactions.entries()) {
      console.log(
        `[Manual] Create ${count} Staker Nodes: ${index + 1}: nonce: ${
          pendingTx.nonce
        }`
      );
    }
  } catch (error) {
    console.log(error);
  }
}

(async () => {
  try {
    console.log("[Manual] Running manual tx proposal...");
    await manualCreateStakerNodes();
  } catch {}
})();
