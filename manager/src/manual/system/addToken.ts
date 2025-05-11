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
    const tokenAddress: string = "0x";
    const decimals: number = 18;
    const volatilityThreshold: string = "50000000000000000";
    const strategyAddress: string = "0x";
    const primaryType: number = 1;
    const primarySource: string = "0x";
    const needsArg: number = 0;
    const fallbackSource: string = "0x";
    const fallbackFn: `0x${string}` = "0x";
    // ------------------------------------------------------------------------------------

    await refreshDeployment();
    await addToken(
      tokenAddress,
      decimals,
      volatilityThreshold,
      strategyAddress,
      primaryType,
      primarySource,
      needsArg,
      fallbackSource,
      fallbackFn
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
    console.log("[Manual] Error: ", error.message);
  }
}

(async () => {
  console.log("[Manual] Running manual tx proposal...");
  await manualAddToken();
})();
