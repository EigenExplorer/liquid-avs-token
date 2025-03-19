import { LIQUID_TOKEN_MANAGER_ADDRESS } from "../../utils/forge";
import { OperationType } from "@safe-global/types-kit";
import { protocolKitOwner, apiKit } from "../../utils/safe";
import { encodeFunctionData, parseAbi, getAddress } from "viem/utils";

/**
 * To run this script, edit the params and run
 * `npx tsx run .src/manual/system/setVolatilityThreshold.ts` from the `/manager` folder
 *
 */
async function manualSetVolatilityThreshold() {
  try {
    if (!process.env.MULTISIG_PUBLIC_KEY || !process.env.SIGNER_PUBLIC_KEY)
      throw new Error("Env vars not set correctly.");

    // ------------------------------------------------------------------------------------
    // Function params, edit these!
    // ------------------------------------------------------------------------------------
    const assetAddress = "0x";
    const newThreshold = "50000000000000000";
    const metadata = {
      title: `Set Volatility Threshold for ${assetAddress}`,
      description: "Proposal to set volatility threshold via manual proposal",
    };
    // ------------------------------------------------------------------------------------

    const contractAddress = LIQUID_TOKEN_MANAGER_ADDRESS;
    const abi = parseAbi(["function setVolatilityThreshold(address,uint256)"]);

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
        `[Manual] Set Volatility Threshold for ${assetAddress}: nonce: ${pendingTransactions[0].nonce}`
      );
    }
  } catch (error) {
    console.log(error);
  }
}

(async () => {
  try {
    console.log("[Manual][System] Running manual tx proposal...");
    await manualSetVolatilityThreshold();
  } catch {}
})();
