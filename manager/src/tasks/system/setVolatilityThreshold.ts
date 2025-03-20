import "dotenv/config";

import { OperationType } from "@safe-global/types-kit";
import { encodeFunctionData, parseAbi, getAddress } from "viem/utils";
import { protocolKitOwnerAdmin } from "../../utils/safe";
import {
  LIQUID_TOKEN_MANAGER_ADDRESS,
  proposeSafeTransaction,
} from "../../utils/forge";

/**
 * Creates a proposal for `setVolatilityThreshold` on `LiquidTokenManager`
 *
 * @param assetAddress
 * @param newThreshold
 * @returns
 */
export async function setVolatilityThreshold(
  assetAddress: string,
  newThreshold: string
) {
  try {
    // Setup task params
    const contractAddress = LIQUID_TOKEN_MANAGER_ADDRESS;
    const abi = parseAbi(["function setVolatilityThreshold(address,uint256)"]);
    const metadata = {
      title: `Set Volatility Threshold for ${assetAddress}`,
      description: "Proposal to set volatility threshold via manual proposal",
    };

    // Setup transaction data
    const data = encodeFunctionData({
      abi,
      functionName: "setVolatilityThreshold",
      args: [assetAddress, BigInt(newThreshold)],
    });
    const metaTransactionData = {
      to: getAddress(contractAddress),
      value: "0",
      data: data,
      operation: OperationType.Call,
    };

    // Create transaction
    const safeTransaction = await protocolKitOwnerAdmin.createTransaction({
      transactions: [metaTransactionData],
    });

    // Propose transactions to multisig
    await proposeSafeTransaction(safeTransaction, metadata);
  } catch (error) {
    console.log("Error: ", error);
    return [];
  }
}
