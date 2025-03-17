import "dotenv/config";
import cron from "node-cron";

import { stakeUnstakedAssets } from "./workflows/stakeUnstakedAssets";

/**
 * Daily responsibilities of restaking manager
 *
 */
async function dailyResponsibilities() {
  try {
    await stakeUnstakedAssets();
  } catch {}
}

// 5 minutes past midnight every day
cron.schedule("5 0 * * *", () => dailyResponsibilities());
