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
 * Creates a proposal for the `UndelegateNodes` task
 *
 * @param nodeIds
 * @returns
 */
export async function undelegateNodes(nodeIds: string[]) {
  try {
    // Setup task params
    const task = "LTM_UndelegateNodes.s.sol:UndelegateNodes";
    const sender = ADMIN;
    const sig = "run(string,uint256[])";
    const params = `[${nodeIds.join(",")}]`;

    // Simulate task and create transaction
    const { stdout } = await execAsync(forgeCommand(task, sender, sig, params));
    const safeTransactions = await createSafeTransactions(stdout);

    // Propose transactions to multisig
    for (const safeTx of safeTransactions) {
      const metadata = {
        title: `Undelegate ${nodeIds.length} Staker Node(s)`,
        description: `Proposal to undelegate a set of staker node(s) via ${task}`,
      };
      await proposeSafeTransaction(safeTx, metadata);
    }
  } catch (error) {
    console.log("Error: ", error);
    return [];
  }
}
