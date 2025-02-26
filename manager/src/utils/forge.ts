import "dotenv/config";

import type { ProposalResponseWithUrl } from "@openzeppelin/defender-sdk-proposal-client/lib/models/response";
import { defenderClient } from "./defenderClient";
import { fileURLToPath } from "node:url";
import fs from "node:fs/promises";
import path from "node:path";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

export const NETWORK = getNetwork();
export const DEPLOYMENT = getDeployment();
export const ADMIN = await getAdmin();
export const LIQUID_TOKEN_ADDRESS = (await getOutputData()).addresses
  .liquidToken;

export function forgeCommand(
  task: string,
  sender: string,
  sig: string,
  params: string
): string {
  return `forge script ../script/tasks/${task} --rpc-url ${getRpcUrl()} --json --sender ${sender} --sig '${sig}' -- ${getConfigFile()} ${params} -vvvv`;
}

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
  const functionSignature = tx.function;

  const functionNameMatch = functionSignature.match(/^([^(]+)\((.*)\)$/);
  if (!functionNameMatch) {
    throw new Error(`Could not parse function signature: ${functionSignature}`);
  }

  const functionInputs = tx.arguments || [];
  const functionName = functionNameMatch[1];
  const parameterString = functionNameMatch[2];
  const parameterTypes = parseParameterTypes(parameterString);
  const inputs = parameterTypes.map((type, index) => ({
    name: `param${index}`,
    type: type,
  }));

  console.log("functionName: ", functionName);
  console.log("inputs: ", inputs);
  console.log("functionInputs: ", functionInputs);

  const proposal = await defenderClient.proposal.create({
    proposal: {
      contract: {
        address: tx.transaction.to,
        network: NETWORK,
      },
      title: title,
      description: description,
      type: "custom",
      functionInterface: {
        name: functionName,
        inputs: inputs,
      },
      functionInputs: functionInputs,
      via: process.env.ADMIN_PUBLIC_KEY,
      viaType: "Safe",
    },
  });

  if (!proposal) throw new Error("Couldn't create proposal");
  return proposal;
}

// --- Helper functions ---

// Default to public if DEPLOYMENT not set
export function getDeployment(): string {
  const deployment = process.env.DEPLOYMENT;
  if (!deployment || deployment !== "local") return "public";
  return "local";
}

// Default to mainnet if NETWORK not set
export function getNetwork(): string {
  const network = process.env.NETWORK;
  if (!network || network !== "holesky") return "mainnet";
  return "holesky";
}

// Default to local if RPC_URL not set
export function getRpcUrl(): string {
  const rpcUrl = process.env.RPC_URL;
  if (!rpcUrl || DEPLOYMENT === "local") return "http://localhost:8545";
  return rpcUrl;
}

// Default to mainnet if NETWORK not set & public if DEPLOYMENT not set
export function getConfigFile(): string {
  if (NETWORK === "mainnet") {
    if (DEPLOYMENT === "local") return "/local/mainnet_deployment_data.json";
    return "/mainnet/deployment_data.json";
  }
  if (DEPLOYMENT === "local") return "/local/holesky_deployment_data.json";
  return "/holesky/deployment_data.json";
}

// Default to local forge test account if ADMIN_PUBLIC_KEY not set
export async function getAdmin(): Promise<string> {
  if (DEPLOYMENT === "local") return (await getOutputData()).roles.admin;
  return (
    process.env.ADMIN_PUBLIC_KEY || "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266"
  );
}

export async function getOutputData() {
  return JSON.parse(
    await fs.readFile(
      path.resolve(__dirname, `../../../script/outputs${getConfigFile()}`),
      "utf8"
    )
  );
}

/**
 * Returns an array of parameter types from a function signature with support for complex types like tuples.
 *
 * @param parameterString
 * @returns
 */
function parseParameterTypes(parameterString: string): string[] {
  if (!parameterString.trim()) {
    return [];
  }

  const result: string[] = [];
  let currentParam = "";
  let parenDepth = 0;

  // Process the parameter string character by character
  for (let i = 0; i < parameterString.length; i++) {
    const char = parameterString[i];

    if (char === "(" && parenDepth === 0) {
      parenDepth++;
      currentParam += char;
    } else if (char === "(" && parenDepth > 0) {
      parenDepth++;
      currentParam += char;
    } else if (char === ")" && parenDepth > 1) {
      parenDepth--;
      currentParam += char;
    } else if (char === ")" && parenDepth === 1) {
      parenDepth--;
      currentParam += char;
    } else if (char === "," && parenDepth === 0) {
      if (currentParam.trim()) {
        result.push(currentParam.trim());
        currentParam = "";
      }
    } else {
      currentParam += char;
    }
  }

  if (currentParam.trim()) {
    result.push(currentParam.trim());
  }

  return result;
}
