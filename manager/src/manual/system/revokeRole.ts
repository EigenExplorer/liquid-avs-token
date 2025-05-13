import { revokeRole } from "../../tasks/system/revokeRole";
import { ADMIN } from "../../utils/forge";
import { apiKit } from "../../utils/safe";
import { refreshDeployment } from "../../workflows/refreshDeployment";

/**
 * To run this script, edit the params and run
 * `npx tsx ./src/manual/system/revokeRole.ts` from the `/manager` folder
 *
 * IMPORTANT:
 * Make sure the .env is updated to the LAT and the deployment you're targetting!
 *
 */
async function manualRevokeRole() {
  try {
    if (!ADMIN) throw new Error("Env vars not set correctly.");

    // ------------------------------------------------------------------------------------
    // Function params, edit these!
    // ------------------------------------------------------------------------------------
    const contractAddress: string = "0x";
    const role: string = "DEFAULT_ADMIN_ROLE";
    const addressToRevoke: string = "0x";
    const skipSafetyCheck: boolean = false;
    // ------------------------------------------------------------------------------------

    await refreshDeployment();
    await revokeRole(contractAddress, role, addressToRevoke, skipSafetyCheck);

    const pendingTransactions = (
      await apiKit.getPendingTransactions(ADMIN, {
        limit: 1,
      })
    ).results;

    if (pendingTransactions.length > 0) {
      console.log(
        `[Manual][System] Revoke role ${role}: nonce: ${pendingTransactions[0].nonce}`
      );
    }
  } catch (error) {
    console.log("[Manual] Error: ", error.message);
  }
}

(async () => {
  console.log("[Manual] Running manual tx proposal...");
  await manualRevokeRole();
})();
