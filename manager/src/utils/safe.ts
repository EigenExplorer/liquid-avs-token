import Safe from "@safe-global/protocol-kit";
import SafeApiKit from "@safe-global/api-kit";
import { getChain } from "./viemClient";

export const protocolKitOwner = await Safe.init({
  provider: process.env.RPC_URL,
  signer: process.env.PROPOSER_PRIVATE_KEY,
  safeAddress: process.env.MULTISIG_PUBLIC_KEY,
});

export const apiKit = new SafeApiKit({
  chainId: BigInt(getChain().id),
});
