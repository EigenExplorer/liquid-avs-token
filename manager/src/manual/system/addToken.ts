import { addToken } from "../../tasks/system/addToken";
import { apiKit } from "../../utils/safe";

/**
 * To run this script, edit the params and run
 * `npx tsx run .src/manual/system/addToken.ts` from the `/manager` folder
 *
 */
async function manualAddToken() {
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
    const decimals = 18;
    const initialPrice = "1000000000000000000";
    const volatilityThreshold = "50000000000000000";
    const strategyAddress = "0x";
    // ------------------------------------------------------------------------------------

    await addToken(
      tokenAddress,
      decimals,
      initialPrice,
      volatilityThreshold,
      strategyAddress
    );

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
        `[Manual] Add Token ${tokenAddress}: nonce: ${pendingTransactions[0].nonce}`
      );
    }
  } catch (error) {
    console.log(error);
  }
}

(async () => {
  try {
    console.log("[Manual][System] Running manual tx proposal...");
    await manualAddToken();
  } catch {}
})();
