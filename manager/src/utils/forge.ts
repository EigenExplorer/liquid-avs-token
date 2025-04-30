import "dotenv/config";

import {
  type MetaTransactionData,
  type SafeTransaction,
  OperationType,
} from "@safe-global/types-kit";
import { apiKit, protocolKitOwnerAdmin, protocolKitOwnerPauser } from "./safe";
import { fileURLToPath } from "node:url";
import { getAddress } from "viem/utils";
import fs from "node:fs/promises";
import path from "node:path";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

export const NETWORK = getNetwork();
export const DEPLOYMENT = getDeployment();

export const SIGNER_ADMIN = process.env.SIGNER_ADMIN_PUBLIC_KEY;
export const SIGNER_PAUSER = process.env.SIGNER_PAUSER_PUBLIC_KEY;

export let LIQUID_TOKEN_ADDRESS = "";
export let LIQUID_TOKEN_MANAGER_ADDRESS = "";
export let STAKER_NODE_COORDINATOR_ADDRESS = "";
export let TOKEN_REGISTRY_ORACLE_ADDRESS = "";
export let PRICE_UPDATER = "";
export let ADMIN = process.env.MULTISIG_ADMIN_PUBLIC_KEY; // Updates from deployment data if not local
export let PAUSER = process.env.MULTISIG_PAUSER_PUBLIC_KEY; // Updates from deployment data if not local

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
  return `forge script ../script/tasks/${task} --rpc-url ${getRpcUrl()} --json --sender ${sender} --sig '${sig}' -- ${getOutputFile()} ${params} -vvvv`;
}

/**
 * Creates a set of transactions ready to be proposed to a gnosis safe
 *
 * @param stdout
 * @returns
 */
export async function createSafeTransactions(
  stdout: string,
  to: "admin" | "pauser" = "admin"
): Promise<SafeTransaction[]> {
  const multisigAddress = to === "admin" ? ADMIN : PAUSER;

  if (!multisigAddress) throw new Error("Env vars not set correctly.");

  const protocolKitOwner =
    to === "admin" ? protocolKitOwnerAdmin : protocolKitOwnerPauser;

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

  let nonce = Number(await apiKit.getNextNonce(multisigAddress));

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
  origin: { title: string; description: string },
  to: "admin" | "pauser" = "admin"
) {
  const multisigAddress = to === "admin" ? ADMIN : PAUSER;
  const signerAddress = to === "admin" ? SIGNER_ADMIN : SIGNER_PAUSER;

  if (!multisigAddress || !signerAddress)
    throw new Error("Env vars not set correctly.");

  const protocolKitOwner =
    to === "admin" ? protocolKitOwnerAdmin : protocolKitOwnerPauser;

  const safeTxHash = await protocolKitOwner.getTransactionHash(safeTransaction);
  const senderSignature = await protocolKitOwner.signHash(safeTxHash);

  await apiKit.proposeTransaction({
    safeAddress: multisigAddress,
    safeTransactionData: safeTransaction.data,
    safeTxHash,
    senderAddress: signerAddress,
    senderSignature: senderSignature.data,
    origin: JSON.stringify(origin),
  });

  await new Promise((resolve) => setTimeout(resolve, 1000));

  const pendingTransactions = (
    await apiKit.getPendingTransactions(multisigAddress)
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
 * Returns the output file from the deployment
 * Defaults to holesky if `NETWORK` env var not set & public if `DEPLOYMENT` env var not set
 *
 * @returns
 */
export function getOutputFile(): string {
  if (DEPLOYMENT === "local") return "/local/deployment_data.json";
  if (NETWORK === "mainnet") return "/mainnet/deployment_data.json";
  return "/holesky/deployment_data.json";
}

/**
 * Returns the deployment data file
 * Defaults to mainnet if local deployment & `NETWORK` env var not set, public if `DEPLOYMENT` env var not set
 *
 * @returns
 */
export async function refreshDeploymentAddresses() {
  try {
    const output = await JSON.parse(
      await fs.readFile(
        path.resolve(__dirname, `../../../script/outputs${getOutputFile()}`),
        "utf8"
      )
    );

    LIQUID_TOKEN_ADDRESS = String(output.proxyAddress);
    LIQUID_TOKEN_MANAGER_ADDRESS = String(
      output.contractDeployments.proxy.liquidTokenManager.address
    );
    STAKER_NODE_COORDINATOR_ADDRESS = String(
      output.contractDeployments.proxy.stakerNodeCoordinator.address
    );
    TOKEN_REGISTRY_ORACLE_ADDRESS = String(
      output.contractDeployments.proxy.tokenRegistryOracle.address
    );
    ADMIN = String(output.roles.admin);
    PAUSER = String(output.roles.pauser);
    PRICE_UPDATER = String(output.roles.priceUpdater);
  } catch (error) {
    console.log("Error: ", error);
  }
}

/**
 * Returns all pending transaction proposals for the given multisig
 *
 * @param multisig
 * @returns
 */
export async function getPendingProposals(
  multisig: "admin" | "pauser" = "admin"
) {
  const multisigAddress = multisig === "admin" ? ADMIN : PAUSER;

  if (!multisigAddress) throw new Error("Env vars not set correctly.");
  return (await apiKit.getPendingTransactions(multisigAddress)).results;
}
