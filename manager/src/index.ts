import "dotenv/config";
import cron from "node-cron";

import { stakeUnstakedAssets } from "./workflows/stakeUnstakedAssets";
import { testFlow } from "./test/local/tasks";

/**
 * Daily responsibilities of restaking manager
 *
 */
async function dailyResponsibilities() {
  try {
    await stakeUnstakedAssets();
  } catch {}
}

await testFlow();

// 5 minutes past midnight every day
// cron.schedule("5 0 * * *", () => dailyResponsibilities());
