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
 * Creates a proposal for the `UndelegateNodes` task
 *
 * @param nodeIds
 * @returns
 */
export async function undelegateNodes(
  nodeIds: string[]
): Promise<ProposalResponseWithUrl[]> {
  try {
    // Setup task params
    const task = "LTM_UndelegateNodes.s.sol:UndelegateNodes";
    const sender = ADMIN;
    const sig = "run(string,uint256[])";
    const params = `[${nodeIds.join(",")}]`;

    // Simulate task and retrieve transactions
    const { stdout } = await execAsync(forgeCommand(task, sender, sig, params));
    const transactions = await extractTransactions(stdout);

    // Create an OZ proposal for each tx
    const proposals: ProposalResponseWithUrl[] = [];
    for (const tx of transactions) {
      const title = `Undelegate Staker Nodes - Nonce ${tx.transaction.nonce}`;
      const description = `Proposal to undelegate a set of staker nodes via contract at ${tx.transaction.to}`;
      const proposal = await createOzProposal(tx, title, description);
      proposals.push(proposal);
    }

    if (!proposals) throw new Error("No proposals created");

    return proposals;
  } catch (error) {
    console.log("Error: ", error);
    return [];
  }
}
