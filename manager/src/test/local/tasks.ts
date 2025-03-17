import "dotenv/config";

import type { Abi } from "viem";
import { DEPLOYMENT, NETWORK } from "../../utils/forge";
import { apiKit } from "../../utils/safe";
import { decodeFunctionData, encodeFunctionData, parseAbi } from "viem/utils";
import { createStakerNodes } from "../../tasks/createStakerNodes";
import { delegateNodes } from "../../tasks/delegateNodes";
import { stakeAssetsToNode } from "../../tasks/stakeAssetsToNode";
import { undelegateNodes } from "../../tasks/undelegateNodes";
import {
  type NodeAllocation,
  stakeAssetsToNodes,
} from "../../tasks/stakeAssetsToNodes";

const ABIS: Record<string, string[]> = {
  createStakerNode: ["function createStakerNode()"],
  delegateNodes: [
    "function delegateNodes(uint256[],address[],(bytes,uint256)[],bytes32[])",
  ],
  stakeAssetsToNode: [
    "function stakeAssetsToNode(uint256,address[],uint256[])",
  ],
  stakeAssetsToNodes: [
    "function stakeAssetsToNodes((uint256,address[],uint256[])[])",
  ],
  undelegateNodes: ["function undelegateNodes(uint256[])"],
};

/**
 * Test script for creating staker nodes
 *
 */
export async function testCreateStakerNodes() {
  try {
    if (DEPLOYMENT !== "local") throw new Error("Deployment is not local");
    if (!process.env.MULTISIG_PUBLIC_KEY)
      throw new Error("Env vars not set correctly.");

    let passing = true;
    const functionName = "createStakerNode";
    const abi = parseAbi(ABIS[functionName]);

    // Create two staker nodes
    await createStakerNodes(2);

    // Get proposed txs
    const pendingTransactions = (
      await apiKit.getPendingTransactions(process.env.MULTISIG_PUBLIC_KEY, {
        limit: 2,
      })
    ).results;

    for (const [index, pendingTx] of pendingTransactions.entries()) {
      const txData = pendingTx.data as `0x${string}`;
      const expectedTxData = encodeFunctionData({
        abi,
        functionName,
        args: [],
      });
      passing = compareTxData(txData, expectedTxData, abi);

      console.log(
        `[Test] ${functionName}: ${index + 1}: `,
        passing ? "passing ✅" : "failing ❌"
      );
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

    let passing = true;
    const functionName = "delegateNodes";
    const abi = parseAbi(ABIS[functionName]);

    // Delegate two nodes to EigenYields
    const operatorAddress =
      NETWORK === "mainnet"
        ? "0x5accc90436492f24e6af278569691e2c942a676d"
        : "0x5accc90436492f24e6af278569691e2c942a676d";

    await delegateNodes(
      ["3", "4"],
      [operatorAddress, operatorAddress],
      [
        {
          signature:
            "0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff",
          expiry: 0,
        },
        {
          signature:
            "0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff",
          expiry: 0,
        },
      ],
      [
        "0x0000000000000000000000000000000000000000000000000000000000000000",
        "0x0000000000000000000000000000000000000000000000000000000000000000",
      ]
    );

    // Get proposed tx
    const pendingTx = (
      await apiKit.getPendingTransactions(process.env.MULTISIG_PUBLIC_KEY, {
        limit: 1,
      })
    ).results[0];

    const txData = pendingTx.data as `0x${string}`;
    const expectedTxData = encodeFunctionData({
      abi,
      functionName,
      args: [
        ["3", "4"],
        [operatorAddress, operatorAddress],
        [
          [
            "0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff",
            0n,
          ],
          [
            "0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff",
            0n,
          ],
        ],
        [
          "0x0000000000000000000000000000000000000000000000000000000000000000",
          "0x0000000000000000000000000000000000000000000000000000000000000000",
        ],
      ],
    });
    passing = compareTxData(txData, expectedTxData, abi);

    console.log(
      `[Test] ${functionName}: `,
      passing ? "passing ✅" : "failing ❌"
    );
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

    let passing = true;
    const functionName = "stakeAssetsToNodes";
    const abi = parseAbi(ABIS[functionName]);

    const stEthAddress =
      NETWORK === "mainnet"
        ? "0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84"
        : "0x3f1c547b21f65e10480de3ad8e19faac46c95034";

    // Stake assets to first and second nodes
    const allocation: NodeAllocation[] = [
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

    await stakeAssetsToNodes(allocation);

    // Get proposed tx
    const pendingTx = (
      await apiKit.getPendingTransactions(process.env.MULTISIG_PUBLIC_KEY, {
        limit: 1,
      })
    ).results[0];

    const txData = pendingTx.data as `0x${string}`;
    const expectedTxData = encodeFunctionData({
      abi,
      functionName,
      args: [
        [
          [
            0n,
            [stEthAddress],
            ["2500000000000000000"].map((amount) => BigInt(amount)),
          ],
          [
            1n,
            [stEthAddress],
            ["2500000000000000000"].map((amount) => BigInt(amount)),
          ],
        ],
      ],
    });
    passing = compareTxData(txData, expectedTxData, abi);

    console.log(
      `[Test] ${functionName}: `,
      passing ? "passing ✅" : "failing ❌"
    );
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

    let passing = true;
    const functionName = "stakeAssetsToNode";
    const abi = parseAbi(ABIS[functionName]);

    const stEthAddress =
      NETWORK === "mainnet"
        ? "0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84"
        : "0x3f1c547b21f65e10480de3ad8e19faac46c95034";

    const args: [string, string[], string[]] = [
      "2",
      [stEthAddress],
      ["3000000000000000000"],
    ];

    // Stake assets to third node
    await stakeAssetsToNode(...args);

    // Get proposed tx
    const pendingTx = (
      await apiKit.getPendingTransactions(process.env.MULTISIG_PUBLIC_KEY, {
        limit: 1,
      })
    ).results[0];

    const txData = pendingTx.data as `0x${string}`;
    const expectedTxData = encodeFunctionData({
      abi,
      functionName,
      args,
    });
    passing = compareTxData(txData, expectedTxData, abi);

    console.log(
      `[Test] ${functionName}: `,
      passing ? "passing ✅" : "failing ❌"
    );
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

    let passing = true;
    const functionName = "undelegateNodes";
    const abi = parseAbi(ABIS[functionName]);

    const args: [string[]] = [["0", "1"]];

    // Undelegate two nodes
    await undelegateNodes(...args);

    // Get proposed tx
    const pendingTx = (
      await apiKit.getPendingTransactions(process.env.MULTISIG_PUBLIC_KEY, {
        limit: 1,
      })
    ).results[0];

    const txData = pendingTx.data as `0x${string}`;
    const expectedTxData = encodeFunctionData({
      abi,
      functionName,
      args,
    });
    passing = compareTxData(txData, expectedTxData, abi);

    console.log(
      `[Test] ${functionName}: `,
      passing ? "passing ✅" : "failing ❌"
    );
  } catch (error) {
    console.log(error);
  }
}

// --- Helper functions ---

/**
 * Compares two transaction data strings to determine if they represent the same function call.
 * Works with complex parameter types including arrays, structs, and nested data.
 *
 * @param actualTxData
 * @param expectedTxData
 * @param abiRegistry
 * @returns
 */
function compareTxData(
  actualTxData: `0x${string}`,
  expectedTxData: `0x${string}`,
  abi: Abi
): boolean {
  console.log("Comparing actual: ");
  console.log(actualTxData);
  console.log("against expected: ");
  console.log(expectedTxData);
  if (actualTxData === expectedTxData) {
    return true;
  }

  const actualSelector = actualTxData.slice(0, 10);
  const expectedSelector = expectedTxData.slice(0, 10);

  if (actualSelector !== expectedSelector) {
    console.log("Function selectors don't match");
    return false;
  }

  const actualDecodedData = decodeFunctionData({
    abi,
    data: actualTxData,
  });
  const expectedDecodedData = decodeFunctionData({
    abi,
    data: expectedTxData,
  });

  if (actualDecodedData.functionName === expectedDecodedData.functionName) {
    return compareArgs(actualDecodedData.args, expectedDecodedData.args);
  }

  return false;
}

/**
 * Deep compares two argument arrays or objects, handling nested structures
 *
 * @param args1
 * @param args2
 * @returns
 */
function compareArgs(args1, args2) {
  if (args1 === args2) return true;
  if (args1 == null || args2 == null) return false;

  if (Array.isArray(args1) && Array.isArray(args2)) {
    if (args1.length !== args2.length) return false;

    for (let i = 0; i < args1.length; i++) {
      if (!compareArgs(args1[i], args2[i])) return false;
    }

    return true;
  }

  if (typeof args1 === "object" && typeof args2 === "object") {
    const keys1 = Object.keys(args1);
    const keys2 = Object.keys(args2);

    if (keys1.length !== keys2.length) return false;

    for (const key of keys1) {
      if (!keys2.includes(key)) return false;
      if (!compareArgs(args1[key], args2[key])) return false;
    }

    return true;
  }

  if (typeof args1 === "bigint" && typeof args2 === "bigint") {
    return args1 === args2;
  }

  return String(args1) === String(args2);
}
