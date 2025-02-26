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
 * @param privateKeyEnvVar
 * @returns
 */
export function getWalletClient(privateKeyEnvVar = "PRIVATE_KEY", n?: Chain) {
  if (n) {
    network = n;
  }

  const privateKey = process.env[privateKeyEnvVar];
  if (!privateKey) {
    throw new Error(`Environment variable ${privateKeyEnvVar} not set`);
  }

  const account = privateKeyToAccount(privateKey as `0x${string}`);

  walletViemClient = createWalletClient({
    account,
    chain: network,
    transport: process.env.NETWORK_CHAIN_RPC_URL
      ? http(process.env.NETWORK_CHAIN_RPC_URL)
      : http(network.rpcUrls.default.http[0]),
  });

  return walletViemClient;
}

/**
 * Get account from a given private key
 *
 * @param privateKeyEnvVar
 * @param n
 * @returns
 */
export function getAccount(privateKeyEnvVar = "PRIVATE_KEY", n?: Chain) {
  if (n) {
    network = n;
  }

  const privateKey = process.env[privateKeyEnvVar];
  if (!privateKey) {
    throw new Error(`Environment variable ${privateKeyEnvVar} not set`);
  }

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
