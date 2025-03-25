import "dotenv/config";

import { exec } from "node:child_process";
import { promisify } from "node:util";
import {
  DEPLOYMENT,
  PRICE_UPDATER,
  LIQUID_TOKEN_ADDRESS,
  forgeCommand,
} from "../utils/forge";
import { getChain, getWalletClient } from "../utils/viemClient";
import { privateKeyToAccount } from "viem/accounts";
import fs from "node:fs/promises";

const execAsync = promisify(exec);

interface LATResponse {
  address: string;
  tokens: { address: string; pricePerUnit: string; decimals: number }[];
}

const LAT_API_URL = process.env.LAT_API_URL;
const PRICE_UPDATE_THRESHOLD = 0.1;

export async function updateAllTokenPrices() {
  try {
    if (!process.env.PRICE_UPDATER_PRIVATE_KEY)
      throw new Error("Env vars not set correctly.");

    // Fetch all supported tokens
    const latResponse = await fetch(
      `${LAT_API_URL}/lat/${LIQUID_TOKEN_ADDRESS}`
    );

    if (!latResponse.ok) {
      throw new Error(
        `Failed to fetch LAT data: ${latResponse.status} ${latResponse.statusText}`
      );
    }

    const latData = (await latResponse.json()) as LATResponse;

    const addresses: `0x${string}`[] = [];
    const prices: bigint[] = [];

    // Find tokens that need price updates
    for (const token of latData.tokens) {
      try {
        const tokenAddress = token.address as `0x${string}`;

        // -------------------------- TODO --------------------------
        // Get prices from 3 sources and pass median/mean price
        // Make sure mappings to token symbol and/or API ID are dynamic
        const oneToken = 10n ** BigInt(token.decimals);
        const ethPriceCMC = 10n ** BigInt(token.decimals); // "https://pro-api.coinmarketcap.com",
        const ethPriceCoinGecko = 10n ** BigInt(token.decimals); // "https://api.coingecko.com/api/v3"
        const ethPrice = ethPriceCMC + ethPriceCoinGecko / 2n;
        const currentPrice = BigInt(token.pricePerUnit);
        const priceDifference = 0.15;
        //----------------------------------------------------------

        // Requires update if price diff > threshold
        const requiresUpdate = priceDifference > PRICE_UPDATE_THRESHOLD;

        if (requiresUpdate) {
          addresses.push(tokenAddress);
          prices.push(ethPrice);
        }
      } catch (error) {
        console.log(`Error processing token ${token.address}:`, error);
      }
    }

    // Setup task params
    const task = "TRO_BatchUpdateRates.s.sol:BatchUpdateRates";
    const sender =
      DEPLOYMENT === "local"
        ? "0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC"
        : PRICE_UPDATER;
    const sig = "run(string,address[],uint256[])";
    const addressesParam = `[${addresses.map((op) => `"${op}"`).join(",")}]`;
    const pricesParam = `[${prices.join(",")}]`;
    const params = `${addressesParam} ${pricesParam}`;

    // Simulate task and create transaction
    const { stdout } = await execAsync(forgeCommand(task, sender, sig, params));

    // Parse the transactions from the forge output
    const broadcastMatch = stdout.match(/"transactions":"([^"]+)"/);

    if (!broadcastMatch)
      throw new Error("Could not find broadcast file path in output");

    const broadcastData = JSON.parse(
      await fs.readFile(broadcastMatch[1].replace(/\\\\/g, "\\"), "utf8")
    );

    const transactions = broadcastData.transactions;

    if (!transactions || !Array.isArray(transactions))
      throw new Error("No transactions found");

    const key = process.env.PRICE_UPDATER_PRIVATE_KEY as `0x${string}`;

    const account = privateKeyToAccount(key);
    const walletClient = getWalletClient(account);

    // Send tx
    const txHash = await walletClient.sendTransaction({
      account,
      to: transactions[0].to as `0x${string}`,
      data: transactions[0].input as `0x${string}`,
      value: BigInt(transactions[0].value || "0x0"),
      chain: getChain(),
    });

    console.log(
      `[Price Updater] Transaction submitted: ${txHash}: tokens updated: ${addresses.length}`
    );
  } catch (error) {
    console.log("Error: ", error);
  }
}
