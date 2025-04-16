import "dotenv/config";
import cron from "node-cron";

import { stakeUnstakedAssets } from "./workflows/stakeUnstakedAssets";
import { refreshDeployment } from "./workflows/refreshDeployment";

console.log("Initializing Restaking Manager ...");

// Constants
const MAX_RETRIES = 3;
const RETRY_DELAY = 15 * 60;

/**
 * Daily responsibilities of restaking manager
 *
 * @param retryCount
 */
async function dailyResponsibilities(retryCount = 0) {
  try {
    console.log("\n[Manager] Performing daily responsibilities...");

    console.time("[Manager] Completed all responsibilities in");

    await refreshDeployment();
    await stakeUnstakedAssets();

    console.timeEnd("[Manager] Completed all responsibilities in");
  } catch (error) {
    console.log(
      `[Manager] Failed to perform daily responsibilities at: ${Date.now()}`
    );
    console.log(error);

    if (retryCount < MAX_RETRIES) {
      console.log(
        `[Manager] Retrying in 15 minutes... (Attempt ${
          retryCount + 1
        } of ${MAX_RETRIES})`
      );
      setTimeout(
        () => dailyResponsibilities(retryCount + 1),
        RETRY_DELAY * 1000
      );
    } else {
      console.log(
        "[Manager] Max retries reached. Performing daily repsonsibilities failed."
      );
    }
  }
}

// 5 minutes past midnight every day
cron.schedule("5 0 * * *", () => dailyResponsibilities());
