import "dotenv/config";

import { exec } from "node:child_process";
import { promisify } from "node:util";
import { DEPLOYMENT, forgeCommand } from "../../utils/forge";
import { PRICE_UPDATER } from "../../utils/forge";
import { privateKeyToAccount } from "viem/accounts";
import { getWalletClient } from "../../utils/viemClient";
import fs from "node:fs/promises";

const execAsync = promisify(exec);

/**
 * Creates a tx for the `BatchUpdateRates` task
 *
 * @param addresses
 * @param prices
 * @returns
 */
export async function batchUpdateRates(
  addresses: `0x${string}`[],
  prices: bigint[]
) {
  try {
    if (!process.env.PRICE_UPDATER_PRIVATE_KEY)
      throw new Error("Env vars not set correctly.");

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
    return [];
  }
}
