import "dotenv/config";
import cron from "node-cron";

import { stakeUnstakedAssets } from "./workflows/stakeUnstakedAssets";
import { fetchLatestDeploymentData } from "./workflows/fetchLatestDeploymentData";
import { updateAllTokenPrices } from "./workflows/updateAllTokenPrices";

console.log("Initializing Restaking Manager ...");

// Constants
const MAX_RETRIES = 3;
const RETRY_DELAY = 15 * 60;
const PRICE_UPDATE_FREQUENCY = 720 * 60;

function delay(seconds: number) {
  return new Promise((resolve) => setTimeout(resolve, seconds * 1000));
}

/**
 * Daily responsibilities of restaking manager
 *
 */
async function dailyResponsibilities(retryCount = 0) {
  try {
    console.log("\nPerforming daily responsibilities...");

    console.time("Completed all responsibilities in");

    await fetchLatestDeploymentData();
    await stakeUnstakedAssets();

    console.timeEnd("Completed all responsibilities in");
  } catch (error) {
    console.log(`Failed to perform daily responsibilities at: ${Date.now()}`);
    console.log(error);

    if (retryCount < MAX_RETRIES) {
      console.log(
        `Retrying in 15 minutes... (Attempt ${
          retryCount + 1
        } of ${MAX_RETRIES})`
      );
      setTimeout(
        () => dailyResponsibilities(retryCount + 1),
        RETRY_DELAY * 1000
      );
    } else {
      console.log(
        "Max retries reached. Performing daily repsonsibilities failed."
      );
    }
  }
}

// Manager plays the role of price-updater in v1
async function updatePrices(retryCount = 0) {
  while (true) {
    try {
      console.log(`\nUpdating prices every ${PRICE_UPDATE_FREQUENCY} seconds:`);

      console.time("Updated prices in");

      await updateAllTokenPrices();

      console.timeEnd("Updated prices in");
    } catch (error) {
      console.log("Failed to update prices at:", Date.now());
      console.log(error);

      if (retryCount < MAX_RETRIES) {
        console.log(
          `Retrying in 15 minutes... (Attempt ${
            retryCount + 1
          } of ${MAX_RETRIES})`
        );
        setTimeout(() => updatePrices(retryCount + 1), RETRY_DELAY * 1000);
      } else {
        console.log("Max retries reached. Updating prices failed.");
      }
    }
    await delay(PRICE_UPDATE_FREQUENCY);
  }
}

// Fetch deployment data immediately
await fetchLatestDeploymentData();

// Start price updation immediately
await updatePrices();

// 5 minutes past midnight every day
cron.schedule("5 0 * * *", () => dailyResponsibilities());
