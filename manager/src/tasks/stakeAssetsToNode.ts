import "dotenv/config";

import { exec } from "node:child_process";
import { promisify } from "node:util";
import {
  ADMIN,
  forgeCommand,
  createSafeTransactions,
  proposeSafeTransaction,
} from "../utils/forge";

const execAsync = promisify(exec);

/**
 * Creates a proposal for the `StakeAssetsToNode` task
 *
 * @param nodeId
 * @param assets
 * @param amounts
 * @returns
 */
export async function stakeAssetsToNode(
  nodeId: string,
  assets: string[],
  amounts: string[]
) {
  try {
    // Setup task params
    const task = "LTM_StakeAssetsToNode.s.sol:StakeAssetsToNode";
    const sender = ADMIN;
    const sig = "run(string,uint256,address[],uint256[])";
    const assetsParam = `[${assets.map((op) => `"${op}"`).join(",")}]`;
    const amountsParam = `[${amounts.join(",")}]`;
    const params = `${nodeId} ${assetsParam} ${amountsParam}`;

    // Simulate task and create transaction
    const { stdout } = await execAsync(forgeCommand(task, sender, sig, params));
    const safeTransactions = await createSafeTransactions(stdout);

    // Propose transactions to multisig
    for (const safeTx of safeTransactions) {
      const metadata = {
        title: `Stake ${assets.length} Asset(s) To Node ${nodeId}`,
        description: `Proposal to stake a set of assets to a staker node via ${task}`,
      };
      await proposeSafeTransaction(safeTx, metadata);
    }
  } catch (error) {
    console.log("Error: ", error);
    return [];
  }
}
