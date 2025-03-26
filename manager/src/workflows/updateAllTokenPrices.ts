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

interface Token {
  address: string;
  pricePerUnit: string;
  decimals: number;
  cmcId: number;
}

interface TokenWithQuote extends Token {
  ethPrice: number;
}

const LAT_API_URL = process.env.LAT_API_URL;
const PRICE_UPDATE_THRESHOLD = 0.001;

export async function updateAllTokenPrices() {
  try {
    if (
      !process.env.PRICE_UPDATER_PRIVATE_KEY ||
      !process.env.CMC_API_KEY ||
      (DEPLOYMENT === "local" &&
        !process.env.VALID_LIQUID_TOKEN_ADDRESS_BACKEND)
    )
      throw new Error("Env vars not set correctly.");

    // Fetch all supported tokens
    const latResponse = await fetch(
      DEPLOYMENT === "local"
        ? `${LAT_API_URL}/lat/${process.env.VALID_LIQUID_TOKEN_ADDRESS_BACKEND}/tokens`
        : `${LAT_API_URL}/lat/${LIQUID_TOKEN_ADDRESS}/tokens`
    );

    if (!latResponse.ok) {
      throw new Error(
        `Failed to fetch LAT data: ${latResponse.status} ${latResponse.statusText}`
      );
    }

    const tokens = (await latResponse.json()).data as Token[];

    const cmcTokenIds = tokens.map((t) => t.cmcId);
    const CMC_API =
      "https://pro-api.coinmarketcap.com/v1/cryptocurrency/quotes/latest";
    const keysStr = cmcTokenIds.filter((id) => id !== 0).join(",");
    const cmcResponse = await fetch(`${CMC_API}?id=${keysStr}&convert=eth`, {
      headers: { "X-CMC_PRO_API_KEY": process.env.CMC_API_KEY },
    });

    if (!cmcResponse.ok) {
      throw new Error(
        `Failed to fetch price data from CMC: ${cmcResponse.status} ${cmcResponse.statusText}`
      );
    }

    // biome-ignore lint/suspicious/noExplicitAny: <explanation>
    const quotes = Object.values((await cmcResponse.json()).data) as any[];
    const tokenQuotes: TokenWithQuote[] = tokens.map((token) => {
      const quote = quotes.find((q) => q.id === token.cmcId);

      return {
        ...token,
        ethPrice: quote ? quote.quote.ETH.price : 0,
      };
    });

    // Find tokens that need price updates
    const addresses: `0x${string}`[] = [];
    const prices: bigint[] = [];
    for (const token of tokenQuotes) {
      try {
        const tokenAddress = token.address as `0x${string}`;
        const currentPrice = Number(token.pricePerUnit);
        const newPrice = token.ethPrice;
        const priceDifference =
          Math.abs(currentPrice - newPrice) / currentPrice;
        const ethPrice = BigInt(Math.round(newPrice * 10 ** token.decimals));

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
        ? "0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC" // Anvil acc #2
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
      chain: walletClient.chain,
    });

    console.log(
      `[Price Updater] Transaction submitted: ${txHash}: tokens updated: ${addresses.length}`
    );
  } catch (error) {
    console.log("Error: ", error);
  }
}
