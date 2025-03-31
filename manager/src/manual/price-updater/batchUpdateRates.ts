import { batchUpdateRates } from "../../tasks/price-updater/batchUpdateRates";
import { refreshDeployment } from "../../workflows/refreshDeployment";

/**
 * To run this script, edit the params and run
 * `npx tsx ./src/manual/price-updater/batchUpdateRates.ts` from the `/manager` folder
 *
 * IMPORTANT:
 * Make sure the .env is updated to the LAT and the deployment you're targetting!
 *
 */
async function manualBatchUpdateRates() {
  try {
    if (!process.env.PRICE_UPDATER_PRIVATE_KEY)
      throw new Error("Env vars not set correctly.");

    // ------------------------------------------------------------------------------------
    // Function params, edit these!
    // ------------------------------------------------------------------------------------
    const addresses: `0x${string}`[] = ["0x", "0x"];
    const prices: bigint[] = [1000000000000000000n];
    // ------------------------------------------------------------------------------------

    await refreshDeployment();
    await batchUpdateRates(addresses, prices);

    console.log(
      `[Manual][Price Updater] Batch Update Rates: length: ${addresses.length}`
    );
  } catch (error) {
    console.log(error);
  }
}

(async () => {
  try {
    console.log("[Manual][Price Updater] Running manual tx execution...");
    await manualBatchUpdateRates();
  } catch {}
})();
