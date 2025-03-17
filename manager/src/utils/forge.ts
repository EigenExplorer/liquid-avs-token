import "dotenv/config";

import {
  type MetaTransactionData,
  type SafeTransaction,
  OperationType,
} from "@safe-global/types-kit";
import { protocolKitOwner, apiKit } from "./safe";
import { fileURLToPath } from "node:url";
import fs from "node:fs/promises";
import path from "node:path";
import { getAddress } from "viem/utils";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

export const NETWORK = getNetwork();
export const DEPLOYMENT = getDeployment();
export const ADMIN = await getAdmin();
export const LIQUID_TOKEN_ADDRESS = (await getOutputData()).proxyAddress;

/**
 * Returns the forge command used to call a task from the /script folder
 *
 * @param task
 * @param sender
 * @param sig
 * @param params
 * @returns
 */
export function forgeCommand(
  task: string,
  sender: string,
  sig: string,
  params: string
): string {
  return `forge script ../script/tasks/${task} --rpc-url ${getRpcUrl()} --json --sender ${sender} --sig '${sig}' -- ${getConfigFile()} ${params} -vvvv`;
}

/**
 * Creates a set of transactions ready to be proposed to a gnosis safe
 *
 * @param stdout
 * @returns
 */
export async function createSafeTransactions(
  stdout: string
): Promise<SafeTransaction[]> {
  if (!process.env.MULTISIG_PUBLIC_KEY || !process.env.MULTISIG_PUBLIC_KEY)
    throw new Error("Env vars not set correctly.");

  const broadcastMatch = stdout.match(/"transactions":"([^"]+)"/);

  if (!broadcastMatch)
    throw new Error("Could not find broadcast file path in output");

  const broadcastData = JSON.parse(
    await fs.readFile(broadcastMatch[1].replace(/\\\\/g, "\\"), "utf8")
  );

  const transactions = broadcastData.transactions;

  if (!transactions || !Array.isArray(transactions))
    throw new Error("No transactions found");

  const safeTransactions: SafeTransaction[] = [];

  let nonce = Number(
    await apiKit.getNextNonce(process.env.MULTISIG_PUBLIC_KEY)
  );

  for (const tx of transactions) {
    const metaTransactionData: MetaTransactionData = {
      to: getAddress(tx.transaction.to),
      value: Number.parseInt(tx.transaction.value, 16).toString(),
      data: tx.transaction.input,
      operation: OperationType.Call,
    };

    const safeTransaction = await protocolKitOwner.createTransaction({
      transactions: [metaTransactionData],
      options: { nonce: nonce++ },
    });

    safeTransactions.push(safeTransaction);
  }

  return safeTransactions;
}

/**
 * Proposes a transaction to the gnosis safe
 *
 * @param safeTransaction
 * @param origin
 * @returns
 */
export async function proposeSafeTransaction(
  safeTransaction: SafeTransaction,
  origin: { title: string; description: string }
) {
  if (!process.env.MULTISIG_PUBLIC_KEY || !process.env.SIGNER_PUBLIC_KEY)
    throw new Error("Env vars not set correctly.");

  const safeTxHash = await protocolKitOwner.getTransactionHash(safeTransaction);
  const senderSignature = await protocolKitOwner.signHash(safeTxHash);

  await apiKit.proposeTransaction({
    safeAddress: process.env.MULTISIG_PUBLIC_KEY,
    safeTransactionData: safeTransaction.data,
    safeTxHash,
    senderAddress: process.env.SIGNER_PUBLIC_KEY,
    senderSignature: senderSignature.data,
    origin: JSON.stringify(origin),
  });

  await new Promise((resolve) => setTimeout(resolve, 1000));

  const pendingTransactions = (
    await apiKit.getPendingTransactions(process.env.MULTISIG_PUBLIC_KEY)
  ).results;

  console.log(
    `[Proposal] ${origin.title}: pending proposals: ${
      pendingTransactions?.length || 0
    }`
  );
}

// --- Helper functions ---

/**
 * Returns whether the deployment is local or public (testnet/mainnet)
 * Defaults to public if `DEPLOYMENT` env var not set
 *
 * @returns
 */
export function getDeployment(): string {
  const deployment = process.env.DEPLOYMENT;
  if (!deployment || deployment !== "local") return "public";
  return "local";
}

/**
 * Returns the network of the deployment
 * Defaults to mainnet if `NETWORK` env var not set
 *
 * @returns
 */
export function getNetwork(): string {
  const network = process.env.NETWORK;
  if (!network || network !== "holesky") return "mainnet";
  return "holesky";
}

/**
 * Returns the RPC URL
 * Defaults to local if `RPC_URL` env var not set
 *
 * @returns
 */
export function getRpcUrl(): string {
  const rpcUrl = process.env.RPC_URL;
  if (!rpcUrl || DEPLOYMENT === "local") return "http://localhost:8545";
  return rpcUrl;
}

/**
 * Returns the input config used to create the deployment
 * Defaults to mainnet if `NETWORK` env var not set & public if `DEPLOYMENT` env var not set
 *
 * @returns
 */
export function getConfigFile(): string {
  if (NETWORK === "mainnet") {
    if (DEPLOYMENT === "local") return "/local/mainnet_deployment_data.json";
    return "/mainnet/deployment_data.json";
  }
  if (DEPLOYMENT === "local") return "/local/holesky_deployment_data.json";
  return "/holesky/deployment_data.json";
}

/**
 * Returns the admin public key
 * Defaults to local forge test account #0 if `MULTISIG_PUBLIC_KEY` env var not set
 * @returns
 */
export async function getAdmin(): Promise<string> {
  if (DEPLOYMENT === "local") return (await getOutputData()).roles.admin;
  return (
    process.env.MULTISIG_PUBLIC_KEY ||
    "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266"
  );
}

/**
 * Returns the output file created after the deployment
 * Defaults to mainnet if `NETWORK` env var not set & public if `DEPLOYMENT` env var not set
 *
 * @returns
 */
export async function getOutputData() {
  return JSON.parse(
    await fs.readFile(
      path.resolve(__dirname, `../../../script/outputs${getConfigFile()}`),
      "utf8"
    )
  );
}
