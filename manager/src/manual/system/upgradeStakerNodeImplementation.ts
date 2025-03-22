import { upgradeStakerNodeImplementation } from "../../tasks/system/upgradeStakerNodeImplementation";
import { ADMIN } from "../../utils/forge";
import { apiKit } from "../../utils/safe";

/**
 * To run this script, edit the params and run
 * `npx tsx run .src/manual/system/upgradeStakerNodeImplementation.ts` from the `/manager` folder
 *
 */
async function manualUpgradeStakerNodeImplementation() {
  try {
    if (!ADMIN) throw new Error("Env vars not set correctly.");

    // ------------------------------------------------------------------------------------
    // Function params, edit these!
    // ------------------------------------------------------------------------------------
    const implementationContractAddress = "0x";
    // ------------------------------------------------------------------------------------

    await upgradeStakerNodeImplementation(implementationContractAddress);

    const pendingTransactions = (
      await apiKit.getPendingTransactions(ADMIN, {
        limit: 1,
      })
    ).results;

    if (pendingTransactions.length > 0) {
      console.log(
        `[Manual] Upgrade Staker Node Implementation to ${implementationContractAddress}: nonce: ${pendingTransactions[0].nonce}`
      );
    }
  } catch (error) {
    console.log(error);
  }
}

(async () => {
  try {
    console.log("[Manual][System] Running manual tx proposal...");
    await manualUpgradeStakerNodeImplementation();
  } catch {}
})();
