import "dotenv/config";

import { OperationType } from "@safe-global/types-kit";
import { encodeFunctionData, parseAbi, getAddress } from "viem/utils";
import { protocolKitOwnerAdmin } from "../../utils/safe";
import {
  STAKER_NODE_COORDINATOR_ADDRESS,
  proposeSafeTransaction,
} from "../../utils/forge";

/**
 * Creates a proposal for `setMaxNodes` on `StakerNodeCoordinator`
 *
 * @param maxNodes
 * @returns
 */
export async function setMaxNodes(maxNodes: string) {
  try {
    // Setup task params
    const contractAddress = STAKER_NODE_COORDINATOR_ADDRESS;
    const abi = parseAbi(["function setMaxNodes(uint256)"]);
    const metadata = {
      title: `Set Max Nodes to ${maxNodes}`,
      description:
        "Proposal to set maximum number of nodes via manual proposal",
    };

    // Setup transaction data
    const data = encodeFunctionData({
      abi,
      functionName: "setMaxNodes",
      args: [BigInt(maxNodes)],
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
