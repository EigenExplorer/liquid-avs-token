import { addToken } from "../../tasks/system/addToken";
import { ADMIN } from "../../utils/forge";
import { apiKit } from "../../utils/safe";
import { refreshDeployment } from "../../workflows/refreshDeployment";

/**
 * To run this script, edit the params and run
 * `npx tsx ./src/manual/system/addToken.ts` from the `/manager` folder
 *
 * IMPORTANT:
 * Make sure the .env is updated to the LAT and the deployment you're targetting!
 *
 */
async function manualAddToken() {
  try {
    if (!ADMIN) throw new Error("Env vars not set correctly.");

    // ------------------------------------------------------------------------------------
    // Function params, edit these!
    // ------------------------------------------------------------------------------------
    const tokenAddress = "0x";
    const decimals = 18;
    const initialPrice = "1000000000000000000";
    const volatilityThreshold = "50000000000000000";
    const strategyAddress = "0x";
    // ------------------------------------------------------------------------------------

    await refreshDeployment();
    await addToken(
      tokenAddress,
      decimals,
      initialPrice,
      volatilityThreshold,
      strategyAddress
    );

    const pendingTransactions = (
      await apiKit.getPendingTransactions(ADMIN, {
        limit: 1,
      })
    ).results;

    if (pendingTransactions.length > 0) {
      console.log(
        `[Manual][System] Add Token ${tokenAddress}: nonce: ${pendingTransactions[0].nonce}`
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
