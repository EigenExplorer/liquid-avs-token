import { STAKER_NODE_COORDINATOR_ADDRESS } from "../../utils/forge";
import { OperationType } from "@safe-global/types-kit";
import { protocolKitOwner, apiKit } from "../../utils/safe";
import { encodeFunctionData, parseAbi, getAddress } from "viem/utils";

/**
 * To run this script, edit the params and run
 * `npx tsx run .src/manual/system/upgradeStakerNodeImplementation.ts` from the `/manager` folder
 *
 */
async function manualUpgradeStakerNodeImplementation() {
  try {
    if (!process.env.MULTISIG_PUBLIC_KEY || !process.env.SIGNER_PUBLIC_KEY)
      throw new Error("Env vars not set correctly.");

    // ------------------------------------------------------------------------------------
    // Function params, edit these!
    // ------------------------------------------------------------------------------------
    const implementationContractAddress = "0x";
    const metadata = {
      title: `Upgrade Staker Node Implementation to ${implementationContractAddress}`,
      description:
        "Proposal to upgrade the staker node implementation contract via manual proposal",
    };
    // ------------------------------------------------------------------------------------

    const contractAddress = STAKER_NODE_COORDINATOR_ADDRESS;
    const abi = parseAbi(["function upgradeStakerNodeImplementation(address)"]);

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

    const safeTransaction = await protocolKitOwner.createTransaction({
      transactions: [metaTransactionData],
    });
    const safeTxHash = await protocolKitOwner.getTransactionHash(
      safeTransaction
    );
    const signature = await protocolKitOwner.signTransactionHash(safeTxHash);

    await protocolKitOwner.proposeTransaction({
      safeTransactionData: safeTransaction.data,
      safeTxHash,
      senderAddress: process.env.SIGNER_PUBLIC_KEY,
      senderSignature: signature.data,
      origin: JSON.stringify(metadata),
    });

    await new Promise((resolve) => setTimeout(resolve, 1000));

    const pendingTransactions = (
      await apiKit.getPendingTransactions(process.env.MULTISIG_PUBLIC_KEY, {
        limit: 1,
      })
    ).results;

    if (pendingTransactions.length > 0) {
      console.log(
        `[Manual] Upgrade Staker Node Implementation to ${implementationContractAddress}: nonce: ${pendingTransactions[0].nonce}`
      );
    }
  } catch (error) {
    console.log(error);
  }
}

(async () => {
  try {
    console.log("[Manual][System] Running manual tx proposal...");
    await manualUpgradeStakerNodeImplementation();
  } catch {}
})();
