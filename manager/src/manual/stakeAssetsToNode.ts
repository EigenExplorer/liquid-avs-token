import { stakeAssetsToNode } from "../tasks/stakeAssetsToNode";
import { apiKit } from "../utils/safe";

/**
 * To run this script, edit the params and run
 * `npm run stake-assets-to-node` from the `/manager` folder
 *
 */
export async function manualStakeAssetsToNode() {
  try {
    if (!process.env.MULTISIG_PUBLIC_KEY)
      throw new Error("Env vars not set correctly.");

    // ------------------------------------------------------------------------------------
    // Function params, edit these!
    // ------------------------------------------------------------------------------------
    const nodeId: string = "0";
    const assets: string[] = ["0x", "0x"];
    const amounts: string[] = ["3000000000000000000", "1000000000000000000"];
    // ------------------------------------------------------------------------------------

    await stakeAssetsToNode(nodeId, assets, amounts);

    const pendingTx = (
      await apiKit.getPendingTransactions(process.env.MULTISIG_PUBLIC_KEY, {
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
