import { pauseLiquidToken } from "../../tasks/system/pauseLiquidToken";
import { apiKit } from "../../utils/safe";

/**
 * To run this script, edit the params and run
 * `npx tsx run .src/manual/system/pauseLiquidToken.ts` from the `/manager` folder
 *
 */
async function manualPauseLiquidToken() {
  try {
    if (
      !process.env.MULTISIG_PAUSER_PUBLIC_KEY ||
      !process.env.SIGNER_PAUSER_PUBLIC_KEY
    )
      throw new Error("Env vars not set correctly.");

    await pauseLiquidToken();

    const pendingTransactions = (
      await apiKit.getPendingTransactions(
        process.env.MULTISIG_PAUSER_PUBLIC_KEY,
        {
          limit: 1,
        }
      )
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
