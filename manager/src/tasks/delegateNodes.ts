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
 * Creates a proposal for the `DelegateNodes` task
 *
 * @param nodeIds
 * @param operators
 * @param signatures
 * @param salts
 * @returns
 */
export async function delegateNodes(
  nodeIds: string[],
  operators: string[],
  signatures: { signature: string; expiry: number | string }[],
  salts: string[]
) {
  try {
    if (!ADMIN) throw new Error("Env vars not set correctly.");

    // Setup task params
    const task = "LTM_DelegateNodes.s.sol:DelegateNodes";
    const sender =
      DEPLOYMENT === "local" ? (await getOutputData()).roles.admin : ADMIN;
    const sig = "run(string,uint256[],address[],(bytes,uint256)[],bytes32[])";
    const nodeIdsParam = `[${nodeIds.join(",")}]`;
    const operatorsParam = `[${operators.map((op) => `"${op}"`).join(",")}]`;
    const signaturesParam =
      signatures.length > 0
        ? `[${signatures
            .map((sig) => `("${sig.signature}",${sig.expiry})`)
            .join(",")}]`
        : "[]";
    const saltsParam =
      salts.length > 0
        ? `[${salts.map((salt) => `"${salt}"`).join(",")}]`
        : "[]";
    const params = `${nodeIdsParam} ${operatorsParam} "${signaturesParam}" ${saltsParam}`;

    // Simulate task and create transaction
    const { stdout } = await execAsync(forgeCommand(task, sender, sig, params));
    const safeTransactions = await createSafeTransactions(stdout);

    // Propose transactions to multisig
    for (const safeTx of safeTransactions) {
      const metadata = {
        title: `Delegate ${nodeIds.length} Staker Nodes`,
        description: `Proposal to delegate a set of staker nodes via ${task}`,
      };
      await proposeSafeTransaction(safeTx, metadata);
    }
  } catch (error) {
    console.log("Error: ", error);
    return [];
  }
}
