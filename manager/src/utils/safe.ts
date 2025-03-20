import Safe from "@safe-global/protocol-kit";
import SafeApiKit from "@safe-global/api-kit";
import { getChain } from "./viemClient";

export const protocolKitOwnerAdmin = await Safe.init({
  provider: process.env.RPC_URL,
  signer: process.env.SIGNER_ADMIN_PRIVATE_KEY,
  safeAddress: process.env.MULTISIG_ADMIN_PUBLIC_KEY,
});

export const protocolKitOwnerPauser = await Safe.init({
  provider: process.env.RPC_URL,
  signer: process.env.SIGNER_PAUSER_PRIVATE_KEY,
  safeAddress: process.env.MULTISIG_PAUSER_PUBLIC_KEY,
});

export const apiKit = new SafeApiKit({
  chainId: BigInt(getChain().id),
});
