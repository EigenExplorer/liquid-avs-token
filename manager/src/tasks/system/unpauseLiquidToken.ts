import "dotenv/config";

import { OperationType } from "@safe-global/types-kit";
import { encodeFunctionData, parseAbi, getAddress } from "viem/utils";
import { apiKit, protocolKitOwnerAdmin } from "../../utils/safe";
import {
  ADMIN,
  LIQUID_TOKEN_ADDRESS,
  proposeSafeTransaction,
} from "../../utils/forge";

/**
 * Creates a proposal for `unpause` on `LiquidToken`
 *
 * @returns
 */
export async function unpauseLiquidToken() {
  try {
    if (!ADMIN) throw new Error("Env vars not set correctly.");

    // Setup task params
    const contractAddress = LIQUID_TOKEN_ADDRESS;
    const abi = parseAbi(["function unpause()"]);
    const metadata = {
      title: "Unpause Contract",
      description:
        "Proposal to unpause contract functionality via manual proposal",
    };

    // Setup transaction data
    const data = encodeFunctionData({
      abi,
      functionName: "unpause",
      args: [],
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
