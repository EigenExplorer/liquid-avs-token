import "dotenv/config";

import { exec } from "node:child_process";
import { promisify } from "node:util";
import {
  ADMIN,
  DEPLOYMENT,
  forgeCommand,
  createSafeTransactions,
  proposeSafeTransaction,
  getOutputData,
} from "../utils/forge";

const execAsync = promisify(exec);

/**
 * Creates `count` proposals for the `CreateStakerNodes` task
 *
 * @param count
 * @returns
 */
export async function createStakerNodes(count: number) {
  try {
    if (!ADMIN) throw new Error("Env vars not set correctly.");

    // Setup task params
    const task = "SNC_CreateStakerNodes.s.sol:CreateStakerNodes";
    const sender =
      DEPLOYMENT === "local" ? (await getOutputData()).roles.admin : ADMIN;
    const sig = "run(string,uint256)";
    const params = `${count}`;

    // Simulate task and create transaction
    const { stdout } = await execAsync(forgeCommand(task, sender, sig, params));
    const safeTransactions = await createSafeTransactions(stdout);

    // Propose transactions to multisig
    for (const safeTx of safeTransactions) {
      const metadata = {
        title: `Create ${count} Staker Nodes`,
        description: `Proposal to create a staker node via ${task}`,
      };
      await proposeSafeTransaction(safeTx, metadata);
    }
  } catch (error) {
    console.log("Error: ", error);
    return [];
  }
}
