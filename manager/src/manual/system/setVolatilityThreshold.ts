import { setVolatilityThreshold } from "../../tasks/system/setVolatilityThreshold";
import { apiKit } from "../../utils/safe";

/**
 * To run this script, edit the params and run
 * `npx tsx run .src/manual/system/setVolatilityThreshold.ts` from the `/manager` folder
 *
 */
async function manualSetVolatilityThreshold() {
  try {
    if (
      !process.env.MULTISIG_ADMIN_PUBLIC_KEY ||
      !process.env.SIGNER_ADMIN_PUBLIC_KEY
    )
      throw new Error("Env vars not set correctly.");

    // ------------------------------------------------------------------------------------
    // Function params, edit these!
    // ------------------------------------------------------------------------------------
    const assetAddress = "0x";
    const newThreshold = "50000000000000000";
    // ------------------------------------------------------------------------------------

    await setVolatilityThreshold(assetAddress, newThreshold);

    const pendingTransactions = (
      await apiKit.getPendingTransactions(
        process.env.MULTISIG_ADMIN_PUBLIC_KEY,
        {
          limit: 1,
        }
      )
    ).results;

    if (pendingTransactions.length > 0) {
      console.log(
        `[Manual] Set Volatility Threshold for ${assetAddress}: nonce: ${pendingTransactions[0].nonce}`
      );
    }
  } catch (error) {
    console.log(error);
  }
}

(async () => {
  try {
    console.log("[Manual][System] Running manual tx proposal...");
    await manualSetVolatilityThreshold();
  } catch {}
})();
