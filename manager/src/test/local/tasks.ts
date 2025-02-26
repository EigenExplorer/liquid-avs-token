import "dotenv/config";

import { createStakerNodes } from "../../tasks/createStakerNodes";
import { delegateNodes } from "../../tasks/delegateNodes";
import { stakeAssetsToNode } from "../../tasks/stakeAssetsToNode";
import { undelegateNodes } from "../../tasks/undelegateNodes";
import { DEPLOYMENT, NETWORK } from "../../utils/forge";
import {
  type NodeAllocation,
  stakeAssetsToNodes,
} from "../../tasks/stakeAssetsToNodes";

export async function testCreateStakerNodes() {
  try {
    if (DEPLOYMENT !== "local") throw new Error("Deployment is not local");

    // Create five staker nodes
    const proposals = await createStakerNodes(5);

    // Log all proposals created
    for (const proposal of proposals) {
      console.log(proposal);
    }
  } catch {}
}

export async function testDelegateNodes() {
  try {
    if (DEPLOYMENT !== "local") throw new Error("Deployment is not local");

    // Delegate five nodes to EigenYields
    const operatorAddress =
      NETWORK === "mainnet"
        ? "0x5accc90436492f24e6af278569691e2c942a676d"
        : "0x5accc90436492f24e6af278569691e2c942a676d";

    const proposals = await delegateNodes(
      ["0", "1", "2", "3", "4"],
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

    // Log all proposals created
    for (const proposal of proposals) {
      console.log(proposal);
    }
  } catch {}
}

export async function testStakeAssetsToNodes() {
  try {
    if (DEPLOYMENT !== "local") throw new Error("Deployment is not local");

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

    const proposals = await stakeAssetsToNodes(allocations);

    // Log all proposals created
    for (const proposal of proposals) {
      console.log(proposal);
    }
  } catch {}
}

export async function testStakeAssetsToNode() {
  try {
    if (DEPLOYMENT !== "local") throw new Error("Deployment is not local");

    const stEthAddress =
      NETWORK === "mainnet"
        ? "0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84"
        : "0x3f1c547b21f65e10480de3ad8e19faac46c95034";

    // Stake assets to third node
    const proposals = await stakeAssetsToNode(
      "2",
      [stEthAddress],
      ["3000000000000000000"]
    );

    // Log all proposals created
    for (const proposal of proposals) {
      console.log(proposal);
    }
  } catch {}
}

export async function testUndelegateNodes() {
  try {
    if (DEPLOYMENT !== "local") throw new Error("Deployment is not local");

    // Undelegate fourth and fifth nodes
    const proposals = await undelegateNodes(["3", "4"]);

    // Log all proposals created
    for (const proposal of proposals) {
      console.log(proposal);
    }
  } catch {}
}

export async function testRun() {
  await testCreateStakerNodes();
  await testDelegateNodes();
  await testStakeAssetsToNodes();
  await testStakeAssetsToNode();
  await testUndelegateNodes();
}
