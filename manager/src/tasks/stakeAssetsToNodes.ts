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

export type NodeAllocation = {
  nodeId: string;
  assets: string[];
  amounts: string[];
};

export async function stakeAssetsToNodes(
  allocations: NodeAllocation[]
): Promise<ProposalResponseWithUrl[]> {
  try {
    // Setup task params
    const task = "LTM_StakeAssetsToNodes.s.sol:StakeAssetsToNodes";
    const sender = ADMIN;
    const sig = "run(string,(uint256,address[],uint256[])[])";
    const params = `'[${allocations
      .map(
        ({ nodeId, assets, amounts }) =>
          `(${nodeId},[${assets.join(",")}],[${amounts.join(",")}])`
      )
      .join(",")}]'`;

    // Simulate task and retrieve transactions
    const { stdout } = await execAsync(forgeCommand(task, sender, sig, params));
    const transactions = await extractTransactions(stdout);

    // Create an OZ proposal for each tx
    const proposals: ProposalResponseWithUrl[] = [];
    for (const tx of transactions) {
      const title = `Stake Assets To Nodes - Nonce ${tx.transaction.nonce}`;
      const description = `Proposal for a set of staker node allocations via contract at ${tx.transaction.to}`;
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
