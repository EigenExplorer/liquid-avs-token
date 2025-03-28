import { unpauseLiquidToken } from "../../tasks/system/unpauseLiquidToken";
import { ADMIN } from "../../utils/forge";
import { apiKit } from "../../utils/safe";

/**
 * To run this script, edit the params and run
 * `npx tsx run .src/manual/system/unpauseLiquidToken.ts` from the `/manager` folder
 *
 */
async function manualUnpauseLiquidToken() {
  try {
    if (!ADMIN) throw new Error("Env vars not set correctly.");

    await unpauseLiquidToken();

    const pendingTransactions = (
      await apiKit.getPendingTransactions(ADMIN, {
        limit: 1,
      })
    ).results;

    if (pendingTransactions.length > 0) {
      console.log(
        `[Manual][System] Unpause Contract: nonce: ${pendingTransactions[0].nonce}`
      );
    }
  } catch (error) {
    console.log(error);
  }
}

(async () => {
  try {
    console.log("[Manual][System] Running manual tx proposal...");
    await manualUnpauseLiquidToken();
  } catch {}
})();
