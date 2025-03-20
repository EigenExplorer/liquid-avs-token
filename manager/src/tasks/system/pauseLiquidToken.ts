import "dotenv/config";

import { OperationType } from "@safe-global/types-kit";
import { encodeFunctionData, parseAbi, getAddress } from "viem/utils";
import { protocolKitOwnerPauser } from "../../utils/safe";
import {
  LIQUID_TOKEN_ADDRESS,
  proposeSafeTransaction,
} from "../../utils/forge";

/**
 * Creates a proposal for `pause` on `LiquidToken`
 *
 * @returns
 */
export async function pauseLiquidToken() {
  try {
    // Setup task params
    const contractAddress = LIQUID_TOKEN_ADDRESS;
    const metadata = {
      title: "Pause Contract",
      description:
        "Proposal to pause contract functionality via manual proposal",
    };
    const abi = parseAbi(["function pause()"]);

    // Setup transaction data
    const data = encodeFunctionData({
      abi,
      functionName: "pause",
      args: [],
    });
    const metaTransactionData = {
      to: getAddress(contractAddress),
      value: "0",
      data: data,
      operation: OperationType.Call,
    };

    // Create transaction
    const safeTransaction = await protocolKitOwnerPauser.createTransaction({
      transactions: [metaTransactionData],
    });

    // Propose transactions to multisig
    await proposeSafeTransaction(safeTransaction, metadata, "pauser");
  } catch (error) {
    console.log("Error: ", error);
    return [];
  }
}
