import { LIQUID_TOKEN_ADDRESS } from "../utils/forge";
import {
  type NodeAllocation,
  stakeAssetsToNodes,
} from "../tasks/stakeAssetsToNodes";

interface LATResponse {
  address: string;
  assets: { asset: string; balance: string; queuedBalance: string }[];
}

interface TokensResponse {
  data: {
    address: string;
    strategyAddress: string;
    decimals: number;
    pricePerUnit: string;
    volatilityThreshold: string;
  }[];
}

interface StakerNodesResponse {
  stakerNodes: {
    address: string;
    nodeId: number;
    operatorDelegation: string;
    assets: {
      nodeAddress: string;
      asset: string;
      strategy: string;
      stakedAmount: string;
      eigenLayerShares: string;
    }[];
  }[];
}

const LAT_API_URL = process.env.LAT_API_URL;
const MIN_ALLOCATION_ETH = 0.5;

/**
 * Workflow for staking unstaked assets in the `LiquidToken` contract across nodes
 * Rules:
 * - Use 80% of funds for staking and leave 20% for withdrawals
 * - Even split of all asset amounts across all nodes
 * - Min allocation of 0.5 of the asset
 *
 * @returns
 */
export async function stakeUnstakedAssets() {
  try {
    // API: Fetch unstaked assets and amounts
    const latResponse = await fetch(
      `${LAT_API_URL}/lat/${LIQUID_TOKEN_ADDRESS}`
    );

    if (!latResponse.ok) {
      throw new Error(
        `Failed to fetch LAT data: ${latResponse.status} ${latResponse.statusText}`
      );
    }

    const latData = (await latResponse.json()) as LATResponse;
    const unstakedAssets = latData.assets;

    // API: Fetch nodes and their delegations
    const nodesResponse = await fetch(
      `${LAT_API_URL}/lat/${LIQUID_TOKEN_ADDRESS}/staker-nodes`
    );

    if (!nodesResponse.ok) {
      throw new Error(
        `Failed to fetch staker nodes: ${nodesResponse.status} ${nodesResponse.statusText}`
      );
    }

    const nodesData = (await nodesResponse.json()) as StakerNodesResponse;
    const nodes = nodesData.stakerNodes;

    // Filter out nodes that are not delegated
    const delegatedNodes = nodes.filter(
      (node) =>
        node.operatorDelegation !== "0x0000000000000000000000000000000000000000"
    );

    if (delegatedNodes.length === 0) return [];

    // API: Fetch token data
    const tokensResponse = await fetch(
      `${LAT_API_URL}/lat/${LIQUID_TOKEN_ADDRESS}/tokens`
    );

    if (!tokensResponse.ok) {
      throw new Error(
        `Failed to fetch token data: ${tokensResponse.status} ${tokensResponse.statusText}`
      );
    }

    const tokensData = (await tokensResponse.json()) as TokensResponse;
    const tokenInfoMap = new Map(
      tokensData.data.map((token) => [token.address.toLowerCase(), token])
    );

    const allocations: NodeAllocation[] = [];

    for (const asset of unstakedAssets) {
      // Get token info to account for decimals
      const tokenInfo = tokenInfoMap.get(asset.asset.toLowerCase());

      if (!tokenInfo) continue;

      // Allocate 80% of the available balance for staking
      const balance = BigInt(asset.balance);
      const stakingAmount = (balance * BigInt(80)) / BigInt(100);

      if (stakingAmount <= 0) continue;

      // Calculate even distribution across all nodes
      const amountPerNode = stakingAmount / BigInt(delegatedNodes.length);

      // Calculate minimum allocation
      const minAllocationWei = BigInt(
        Math.floor(MIN_ALLOCATION_ETH * 10 ** tokenInfo.decimals)
      );

      // Check if amount per node is below minimum allocation
      if (amountPerNode < minAllocationWei) continue;

      // Create allocations for all nodes
      for (const node of delegatedNodes) {
        const existingAllocation = allocations.find(
          (alloc) => alloc.nodeId === node.nodeId.toString()
        );

        if (existingAllocation) {
          existingAllocation.assets.push(asset.asset);
          existingAllocation.amounts.push(amountPerNode.toString());
        } else {
          allocations.push({
            nodeId: node.nodeId.toString(),
            assets: [asset.asset],
            amounts: [amountPerNode.toString()],
          });
        }
      }
    }

    // If no allocations, exit early
    if (allocations.length === 0) return [];

    // Create proposals to stake assets to nodes
    const proposals = await stakeAssetsToNodes(allocations);

    // Log all tx proposals
    for (const proposal of proposals) {
      console.log(proposal);
    }
  } catch (error) {
    console.log("Error: ", error);
  }
}
