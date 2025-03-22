import "dotenv/config";

import { OperationType } from "@safe-global/types-kit";
import { encodeFunctionData, parseAbi, getAddress } from "viem/utils";
import { apiKit, protocolKitOwnerAdmin } from "../../utils/safe";
import {
  ADMIN,
  LIQUID_TOKEN_MANAGER_ADDRESS,
  proposeSafeTransaction,
} from "../../utils/forge";

/**
 * Creates a proposal for `addToken` on `LiquidTokenManager`
 *
 * @param tokenAddress
 * @param decimals
 * @param initialPrice
 * @param volatilityThreshold
 * @param strategyAddress
 * @returns
 */
export async function addToken(
  tokenAddress: string,
  decimals: number,
  initialPrice: string,
  volatilityThreshold: string,
  strategyAddress: string
) {
  try {
    if (!ADMIN) throw new Error("Env vars not set correctly.");

    // Setup task params
    const contractAddress = LIQUID_TOKEN_MANAGER_ADDRESS;
    const abi = parseAbi([
      "function addToken(address,uint8,uint256,uint256,address)",
    ]);
    const metadata = {
      title: `Add Token ${tokenAddress}`,
      description: "Proposal to add token via manual proposal",
    };

    // Setup transaction data
    const data = encodeFunctionData({
      abi,
      functionName: "addToken",
      args: [
        tokenAddress,
        decimals,
        BigInt(initialPrice),
        BigInt(volatilityThreshold),
        strategyAddress,
      ],
    });
    const metaTransactionData = {
      to: getAddress(contractAddress),
      value: "0",
      data: data,
      operation: OperationType.Call,
    };

    // Create transaction
    const nonce = Number(await apiKit.getNextNonce(ADMIN));
    const safeTransaction = await protocolKitOwnerAdmin.createTransaction({
      transactions: [metaTransactionData],
      options: { nonce },
    });

    // Propose transactions to multisig
    await proposeSafeTransaction(safeTransaction, metadata);
  } catch (error) {
    console.log("Error: ", error);
    return [];
  }
}
