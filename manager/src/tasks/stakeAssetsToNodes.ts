import "dotenv/config";

import { exec } from "node:child_process";
import { promisify } from "node:util";
import {
  ADMIN,
  DEPLOYMENT,
  forgeCommand,
  createSafeTransactions,
  proposeSafeTransaction,
} from "../utils/forge";

const execAsync = promisify(exec);

export type NodeAllocation = {
  nodeId: string;
  assets: string[];
  amounts: string[];
};

/**
 * Creates a proposal for the `StakeAssetsToNodes` task
 *
 * @param allocations
 * @returns
 */
export async function stakeAssetsToNodes(allocations: NodeAllocation[]) {
  if (!ADMIN) throw new Error("Env vars not set correctly.");

  // Setup task params
  const task = "LTM_StakeAssetsToNodes.s.sol:StakeAssetsToNodes";
  const sender =
    DEPLOYMENT === "local"
      ? "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266"
      : ADMIN;
  const sig = "run(string,(uint256,address[],uint256[])[])";
  const params = `'[${allocations
    .map(
      ({ nodeId, assets, amounts }) =>
        `(${nodeId},[${assets.join(",")}],[${amounts.join(",")}])`
    )
    .join(",")}]'`;

  // Simulate task and create transaction
  const { stdout } = await execAsync(forgeCommand(task, sender, sig, params));
  const safeTransactions = await createSafeTransactions(stdout);

  // Propose transactions to multisig
  for (const safeTx of safeTransactions) {
    const metadata = {
      title: `Stake Assets To ${allocations.length} Node(s)`,
      description: `Proposal to stake a set of assets to a set of staker node(s) via ${task}`,
    };
    await proposeSafeTransaction(safeTx, metadata);
  }
}
