import "dotenv/config";

import { DEPLOYMENT, NETWORK } from "../../utils/forge";
import { createStakerNodes } from "../../tasks/createStakerNodes";
import { delegateNodes } from "../../tasks/delegateNodes";
import { stakeAssetsToNode } from "../../tasks/stakeAssetsToNode";
import { undelegateNodes } from "../../tasks/undelegateNodes";
import {
  type NodeAllocation,
  stakeAssetsToNodes,
} from "../../tasks/stakeAssetsToNodes";
import { apiKit, protocolKitOwner } from "../../utils/safe";

/**
 * Test script for creating staker nodes
 *
 */
export async function testCreateStakerNodes() {
  try {
    if (DEPLOYMENT !== "local") throw new Error("Deployment is not local");
    if (!process.env.MULTISIG_PUBLIC_KEY)
      throw new Error("Env vars not set correctly.");

    // Create five staker nodes
    await createStakerNodes(2);

    // Confirm and execute the tx
    const pendingTransactions = (
      await apiKit.getPendingTransactions(process.env.MULTISIG_PUBLIC_KEY, {
        ordering: "submissionDate",
        limit: 5,
      })
    ).results;

    for (const pendingTx of pendingTransactions) {
      const safeTxHash = pendingTx.safeTxHash;
      const signature = await protocolKitOwner.signHash(safeTxHash);

      if (safeTxHash) {
        await apiKit.confirmTransaction(safeTxHash, signature.data);
        const safeTransaction = await apiKit.getTransaction(safeTxHash);
        const executeTxResponse = await protocolKitOwner.executeTransaction(
          safeTransaction
        );
      }
    }
  } catch (error) {
    console.log(error);
  }
}

/**
 * Test script for delegating staker nodes
 *
 */
export async function testDelegateNodes() {
  try {
    if (DEPLOYMENT !== "local") throw new Error("Deployment is not local");
    if (!process.env.MULTISIG_PUBLIC_KEY)
      throw new Error("Env vars not set correctly.");

    // Delegate five nodes to EigenYields
    const operatorAddress =
      NETWORK === "mainnet"
        ? "0x5accc90436492f24e6af278569691e2c942a676d"
        : "0x5accc90436492f24e6af278569691e2c942a676d";

    await delegateNodes(
      ["5", "6", "7", "8", "9"],
      [
        operatorAddress,
        operatorAddress,
        operatorAddress,
        operatorAddress,
        operatorAddress,
      ],
      [],
      []
    );

    // Confirm and execute the tx
    const pendingTransactions = (
      await apiKit.getPendingTransactions(process.env.MULTISIG_PUBLIC_KEY)
    ).results;

    const safeTxHash = pendingTransactions[0].transactionHash;
    const signature = await protocolKitOwner.signHash(safeTxHash);

    if (safeTxHash) {
      await apiKit.confirmTransaction(safeTxHash, signature.data);
      const safeTransaction = await apiKit.getTransaction(safeTxHash);
      const executeTxResponse = await protocolKitOwner.executeTransaction(
        safeTransaction
      );
    }
  } catch (error) {
    console.log(error);
  }
}

/**
 * Test script for staking assets to nodes
 *
 */
export async function testStakeAssetsToNodes() {
  try {
    if (DEPLOYMENT !== "local") throw new Error("Deployment is not local");
    if (!process.env.MULTISIG_PUBLIC_KEY)
      throw new Error("Env vars not set correctly.");

    const stEthAddress =
      NETWORK === "mainnet"
        ? "0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84"
        : "0x3f1c547b21f65e10480de3ad8e19faac46c95034";

    // Stake assets to first and second nodes
    const allocations: NodeAllocation[] = [
      {
        nodeId: "0",
        assets: [stEthAddress],
        amounts: ["2500000000000000000"],
      },
      {
        nodeId: "1",
        assets: [stEthAddress],
        amounts: ["2500000000000000000"],
      },
    ];

    await stakeAssetsToNodes(allocations);

    // Confirm and execute the tx
    const pendingTransactions = (
      await apiKit.getPendingTransactions(process.env.MULTISIG_PUBLIC_KEY)
    ).results;

    const safeTxHash = pendingTransactions[0].transactionHash;
    const signature = await protocolKitOwner.signHash(safeTxHash);

    if (safeTxHash) {
      await apiKit.confirmTransaction(safeTxHash, signature.data);
      const safeTransaction = await apiKit.getTransaction(safeTxHash);
      const executeTxResponse = await protocolKitOwner.executeTransaction(
        safeTransaction
      );
    }
  } catch (error) {
    console.log(error);
  }
}

/**
 * Test script for staking assets to one node
 *
 */
export async function testStakeAssetsToNode() {
  try {
    if (DEPLOYMENT !== "local") throw new Error("Deployment is not local");
    if (!process.env.MULTISIG_PUBLIC_KEY)
      throw new Error("Env vars not set correctly.");

    const stEthAddress =
      NETWORK === "mainnet"
        ? "0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84"
        : "0x3f1c547b21f65e10480de3ad8e19faac46c95034";

    // Stake assets to third node
    await stakeAssetsToNode("2", [stEthAddress], ["3000000000000000000"]);

    // Confirm and execute the tx
    const pendingTransactions = (
      await apiKit.getPendingTransactions(process.env.MULTISIG_PUBLIC_KEY)
    ).results;

    const safeTxHash = pendingTransactions[0].transactionHash;
    const signature = await protocolKitOwner.signHash(safeTxHash);

    if (safeTxHash) {
      await apiKit.confirmTransaction(safeTxHash, signature.data);
      const safeTransaction = await apiKit.getTransaction(safeTxHash);
      const executeTxResponse = await protocolKitOwner.executeTransaction(
        safeTransaction
      );
    }
  } catch (error) {
    console.log(error);
  }
}

/**
 * Test script for undelegating nodes
 *
 */
export async function testUndelegateNodes() {
  try {
    if (DEPLOYMENT !== "local") throw new Error("Deployment is not local");
    if (!process.env.MULTISIG_PUBLIC_KEY)
      throw new Error("Env vars not set correctly.");

    // Undelegate fourth and fifth nodes
    await undelegateNodes(["8", "9"]);

    // Confirm and execute the tx
    const pendingTransactions = (
      await apiKit.getPendingTransactions(process.env.MULTISIG_PUBLIC_KEY)
    ).results;

    const safeTxHash = pendingTransactions[0].transactionHash;
    const signature = await protocolKitOwner.signHash(safeTxHash);

    if (safeTxHash) {
      await apiKit.confirmTransaction(safeTxHash, signature.data);
      const safeTransaction = await apiKit.getTransaction(safeTxHash);
      const executeTxResponse = await protocolKitOwner.executeTransaction(
        safeTransaction
      );
    }
  } catch (error) {
    console.log(error);
  }
}

export async function testFlow() {
  if (DEPLOYMENT !== "local") throw new Error("Deployment is not local");

  await testCreateStakerNodes();
  await testDelegateNodes();
  await testStakeAssetsToNodes();
  await testStakeAssetsToNode();
  await testUndelegateNodes();
}
