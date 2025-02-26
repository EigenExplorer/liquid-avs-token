import {
  type PublicClient,
  type WalletClient,
  createPublicClient,
  createWalletClient,
  http,
} from "viem";
import { privateKeyToAccount } from "viem/accounts";
import { type Chain, holesky, mainnet } from "viem/chains";

let publicViemClient: PublicClient;
let walletViemClient: WalletClient;
let network: Chain = mainnet;

if (process.env.NETWORK) {
  switch (process.env.NETWORK) {
    case "holesky":
      network = holesky;
      break;
  }
}

/**
 * Return the selected network
 *
 * @returns
 */
export function getChain() {
  return network;
}

/**
 * Get the initialized viem public client
 *
 * @returns
 */
export function getViemClient(n?: Chain) {
  if (n) {
    network = n;
  }

  if (!publicViemClient) {
    publicViemClient = createPublicClient({
      cacheTime: 10_000,
      batch: {
        multicall: true,
      },
      transport: process.env.NETWORK_CHAIN_RPC_URL
        ? http(process.env.NETWORK_CHAIN_RPC_URL)
        : http(network.rpcUrls.default.http[0]),
    });
  }

  return publicViemClient;
}

/**
 * Get the initialized viem wallet client for transactions that require signing
 *
 * @param privateKeyEnvVar - The environment variable name that contains the private key
 * @returns The wallet client configured for the current network
 */
export function getWalletClient(privateKeyEnvVar = "PRIVATE_KEY", n?: Chain) {
  if (n) {
    network = n;
  }

  // Get the private key from environment variables
  const privateKey = process.env[privateKeyEnvVar];
  if (!privateKey) {
    throw new Error(`Environment variable ${privateKeyEnvVar} not set`);
  }

  // Create an account from the private key
  const account = privateKeyToAccount(privateKey as `0x${string}`);

  // Create a wallet client with the account
  walletViemClient = createWalletClient({
    account,
    chain: network,
    transport: process.env.NETWORK_CHAIN_RPC_URL
      ? http(process.env.NETWORK_CHAIN_RPC_URL)
      : http(network.rpcUrls.default.http[0]),
  });

  return walletViemClient;
}

export function getAccount(privateKeyEnvVar = "PRIVATE_KEY", n?: Chain) {
  if (n) {
    network = n;
  }

  // Get the private key from environment variables
  const privateKey = process.env[privateKeyEnvVar];
  if (!privateKey) {
    throw new Error(`Environment variable ${privateKeyEnvVar} not set`);
  }

  // Create an account from the private key
  return privateKeyToAccount(privateKey as `0x${string}`);
}

// Keep the existing deprecated code for backward compatibility
// ====================== DEPRECATED ======================
// biome-ignore lint/suspicious/noExplicitAny:
if (!(global as any).publicViemClient) {
  // biome-ignore lint/suspicious/noExplicitAny:
  (global as any).publicViemClient = createPublicClient({
    cacheTime: 10_000,
    batch: {
      multicall: true,
    },
    transport: process.env.NETWORK_CHAIN_RPC_URL
      ? http(process.env.NETWORK_CHAIN_RPC_URL)
      : http(network.rpcUrls.default.http[0]),
  });
}

// biome-ignore lint/suspicious/noExplicitAny:
publicViemClient = (global as any).publicViemClient;

export default publicViemClient;
// ====================== DEPRECATED ======================
