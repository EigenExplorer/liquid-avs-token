import type { ProposalResponseWithUrl } from "@openzeppelin/defender-sdk-proposal-client/lib/models/response";
import { defenderClient } from "./defenderClient";
import fs from "node:fs/promises";

export async function extractTransactions(stdout: string) {
  const broadcastMatch = stdout.match(/"transactions":"([^"]+)"/);

  if (!broadcastMatch)
    throw new Error("Could not find broadcast file path in output");

  const broadcastData = JSON.parse(
    await fs.readFile(broadcastMatch[1].replace(/\\\\/g, "\\"), "utf8")
  );

  const transactions = broadcastData.transactions;

  if (!transactions || !Array.isArray(transactions))
    throw new Error("No transactions found");

  return transactions;
}

export async function createOzProposal(
  // biome-ignore lint/suspicious/noExplicitAny: <explanation>
  tx: any,
  title: string,
  description: string
): Promise<ProposalResponseWithUrl> {
  const network = process.env.NETWORK || "mainnet";
  const functionSignature = tx.function;

  const functionNameMatch = functionSignature.match(/^([^(]+)\((.*)\)$/);
  if (!functionNameMatch) {
    throw new Error(`Could not parse function signature: ${functionSignature}`);
  }

  const functionName = functionNameMatch[1];
  const parameterString = functionNameMatch[2];

  const parameterTypes = parameterString
    ? parameterString.split(",").map((param) => param.trim())
    : [];

  const inputs = parameterTypes.map((type, index) => ({
    name: `param${index}`,
    type: type,
  }));

  const functionArguments = tx.arguments || [];

  const proposal = await defenderClient.proposal.create({
    proposal: {
      contract: {
        address: tx.transaction.to,
        network: network,
      },
      title: title,
      description: description,
      type: "custom",
      functionInterface: {
        name: functionName,
        inputs: inputs,
      },
      functionInputs: functionArguments,
      via: process.env.ADMIN_PUBLIC_KEY,
      viaType: "Safe",
    },
  });

  if (!proposal) throw new Error("Couldn't create proposal");
  return proposal;
}
