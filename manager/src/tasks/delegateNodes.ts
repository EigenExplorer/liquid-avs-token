import "dotenv/config";

import type { ProposalResponseWithUrl } from "@openzeppelin/defender-sdk-proposal-client/lib/models/response";
import { exec } from "node:child_process";
import { promisify } from "node:util";
import {
  ADMIN,
  forgeCommand,
  extractTransactions,
  createOzProposal,
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
): Promise<ProposalResponseWithUrl[]> {
  try {
    // Setup task params
    const task = "LTM_DelegateNodes.s.sol:DelegateNodes";
    const sender = ADMIN;
    const sig = "run(string,uint256[],address[],(bytes,uint256)[],bytes32[])";
    const nodeIdsParam = `[${nodeIds.join(",")}]`;
    const operatorsParam = `[${operators.map((op) => `"${op}"`).join(",")}]`;
    const signaturesParam =
      signatures.length > 0
        ? `[${signatures
            .map((sig) => `{signature:"${sig.signature}",expiry:${sig.expiry}}`)
            .join(",")}]`
        : "[]";
    const saltsParam =
      salts.length > 0
        ? `[${salts.map((salt) => `"${salt}"`).join(",")}]`
        : "[]";
    const params = `${nodeIdsParam} ${operatorsParam} ${signaturesParam} ${saltsParam}`;

    // Simulate task and retrieve transactions
    const { stdout } = await execAsync(forgeCommand(task, sender, sig, params));
    const transactions = await extractTransactions(stdout);

    // Create an OZ proposal for each tx
    const proposals: ProposalResponseWithUrl[] = [];
    for (const tx of transactions) {
      const title = `Delegate Staker Nodes - Nonce ${tx.transaction.nonce}`;
      const description = `Proposal to delegate a set of staker nodes via contract at ${tx.transaction.to}`;
      const proposal = await createOzProposal(tx, title, description);
      proposals.push(proposal);
    }

    if (!proposals) throw new Error("No proposals created");

    return proposals;
  } catch (error) {
    console.log("Error:", error);
    return [];
  }
}
