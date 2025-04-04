import "dotenv/config";
import cron from "node-cron";

import { stakeUnstakedAssets } from "./workflows/stakeUnstakedAssets";
import { refreshDeployment } from "./workflows/refreshDeployment";
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

/**
 * Manager plays the role of price-updater in v1
 *
 * @param retryCount
 */
async function priceUpdater(retryCount = 0) {
  while (true) {
    try {
      console.log(
        `\n[Price Updater] Updating prices every ${PRICE_UPDATE_FREQUENCY} seconds:`
      );

      console.time("[Price Updater] Updated prices in");

      await refreshDeployment();
      await updateAllTokenPrices();

      console.timeEnd("[Price Updater] Updated prices in");
    } catch (error) {
      console.log("Failed to update prices at:", Date.now());
      console.log(error);

      if (retryCount < MAX_RETRIES) {
        console.log(
          `Retrying in 15 minutes... (Attempt ${
            retryCount + 1
          } of ${MAX_RETRIES})`
        );
        setTimeout(() => priceUpdater(retryCount + 1), RETRY_DELAY * 1000);
      } else {
        console.log("Max retries reached. Updating prices failed.");
      }
    }
    await delay(PRICE_UPDATE_FREQUENCY);
  }
}

// Start price updation immediately
priceUpdater();

// 5 minutes past midnight every day
cron.schedule("5 0 * * *", () => dailyResponsibilities());
