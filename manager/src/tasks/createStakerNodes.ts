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
 * Creates `count` proposals for the `CreateStakerNodes` task
 *
 * @param count
 * @returns
 */
export async function createStakerNodes(
  count: number
): Promise<ProposalResponseWithUrl[]> {
  try {
    // Setup task params
    const task = "SNC_CreateStakerNodes.s.sol:CreateStakerNodes";
    const sender = ADMIN;
    const sig = "run(string,uint256)";
    const params = `${count}`;

    // Simulate task and retrieve transactions
    const { stdout } = await execAsync(forgeCommand(task, sender, sig, params));
    const transactions = await extractTransactions(stdout);

    // Create an OZ proposal for each tx
    const proposals: ProposalResponseWithUrl[] = [];
    for (const tx of transactions) {
      const title = `Create Staker Node - Nonce ${tx.transaction.nonce}`;
      const description = `Proposal to create a staker node via contract at ${tx.transaction.to}`;
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
