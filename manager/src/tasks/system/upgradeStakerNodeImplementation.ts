import "dotenv/config";

import { OperationType } from "@safe-global/types-kit";
import { encodeFunctionData, parseAbi, getAddress } from "viem/utils";
import { protocolKitOwnerAdmin } from "../../utils/safe";
import {
  STAKER_NODE_COORDINATOR_ADDRESS,
  proposeSafeTransaction,
} from "../../utils/forge";

/**
 * Creates a proposal for `upgradeStakerNodeImplementation` on `StakerNodeCoordinator`
 *
 * @param implementationContractAddress
 * @returns
 */
export async function upgradeStakerNodeImplementation(
  implementationContractAddress: string
) {
  try {
    // Setup task params
    const contractAddress = STAKER_NODE_COORDINATOR_ADDRESS;
    const abi = parseAbi(["function upgradeStakerNodeImplementation(address)"]);
    const metadata = {
      title: `Upgrade Staker Node Implementation to ${implementationContractAddress}`,
      description:
        "Proposal to upgrade the staker node implementation contract via manual proposal",
    };

    // Setup transaction data
    const data = encodeFunctionData({
      abi,
      functionName: "upgradeStakerNodeImplementation",
      args: [implementationContractAddress],
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
