import { removeToken } from "../../tasks/system/removeToken";
import { apiKit } from "../../utils/safe";

/**
 * To run this script, edit the params and run
 * `npx tsx run .src/manual/system/removeToken.ts` from the `/manager` folder
 *
 */
async function manualRemoveToken() {
  try {
    if (
      !process.env.MULTISIG_ADMIN_PUBLIC_KEY ||
      !process.env.SIGNER_ADMIN_PUBLIC_KEY
    )
      throw new Error("Env vars not set correctly.");

    // ------------------------------------------------------------------------------------
    // Function params, edit these!
    // ------------------------------------------------------------------------------------
    const tokenAddress = "0x";
    // ------------------------------------------------------------------------------------

    await removeToken(tokenAddress);

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
        `[Manual] Remove Token ${tokenAddress}: nonce: ${pendingTransactions[0].nonce}`
      );
    }
  } catch (error) {
    console.log(error);
  }
}

(async () => {
  try {
    console.log("[Manual][System] Running manual tx proposal...");
    await manualRemoveToken();
  } catch {}
})();
