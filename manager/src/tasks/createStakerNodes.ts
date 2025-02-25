import "dotenv/config";

import type { ProposalResponseWithUrl } from "@openzeppelin/defender-sdk-proposal-client/lib/models/response";
import { exec } from "node:child_process";
import { promisify } from "node:util";
import { extractTransactions, createOzProposal } from "../utils/forge";

const execAsync = promisify(exec);

export async function createStakerNodes(count: number) {
  try {
    const forgeCommand = `forge script ../script/tasks/SNC_CreateStakerNodes.s.sol:CreateStakerNodes --rpc-url ${process.env.RPC_URL} --json --sender ${process.env.ADMIN_PUBLIC_KEY} --sig "run(string memory,uint256)" -- "/local/mainnet_deployment_data.json" ${count} -vvvv`;
    const { stdout } = await execAsync(forgeCommand);
    const transactions = await extractTransactions(stdout);

    const proposals: ProposalResponseWithUrl[] = [];
    for (const tx of transactions) {
      const title = `Create Staker Node - Nonce ${tx.transaction.nonce}`;
      const description = `Proposal to create a staker node via contract at ${tx.transaction.to}`;
      const proposal = await createOzProposal(tx, title, description);
      proposals.push(proposal);
    }

    return proposals;
  } catch (error) {
    console.log("Error:", error);
  }
}
