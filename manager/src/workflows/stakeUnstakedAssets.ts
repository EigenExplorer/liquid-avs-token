import {
  getPendingProposals,
  isContractOurs,
  LIQUID_TOKEN_ADDRESS,
} from "../utils/forge";
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
  }[];
}

interface StakerNodesResponse {
  stakerNodes: {
    address: string;
    nodeId: number;
    operatorDelegation: string;
    assets: {
      asset: string;
    }[];
  }[];
}

const LAT_API_URL = process.env.LAT_API_URL;

/**
 * Workflow for staking unstaked assets in the `LiquidToken` contract across nodes
 * Policy:
 * - Even split of all asset amounts across all nodes
 *
 * @returns
 */
export async function stakeUnstakedAssets() {
  try {
    // Check if the multisig has any pending proposals for this LAT
    const pendingProposals = await getPendingProposals();
    for (const proposal of pendingProposals) {
      if (isContractOurs(proposal.to.toLowerCase())) {
        throw new Error(
          `Cannot execute workflow due to existing pending tx for this LAT at nonce ${proposal.nonce}`
        );
      }
    }

    // LAT API: Fetch unstaked assets and amounts
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

    // LAT API: Fetch nodes and their delegations
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

    // LAT API: Fetch token data
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

      const balance = BigInt(asset.balance);
      const stakingAmount = (balance * BigInt(995)) / BigInt(1000); // allow 0.5% margin of error

      if (stakingAmount <= 0) continue;

      // Calculate even distribution across all nodes
      const amountPerNode = stakingAmount / BigInt(delegatedNodes.length);

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
    await stakeAssetsToNodes(allocations);

    console.log("[Manager] Stake unstaked assets complete");
  } catch (error) {
    console.log("[Manager] Error: ", error.message);
    throw error;
  }
}
