#!/bin/bash

# With this script, we simulate a staker depositing funds and the re-staking manager (admin) deploying them to EigenLayer with the following steps:
#  1. Deploy all LAT contracts with stETH token/strategy registered
#  2. Restaking manager creates four staker nodes
#  3. Restaking manager delegates nodes to an EigenLayer Operator
#  4. Staker deposits stETH by interfacing with `LiquidToken`
#  5. Restaking manager stakes the user's funds to three nodes
#  6. Restaking manager undelegates the fourth node

# End-state verification:
# 1. Three nodes are delegated and the fourth one is not
# 2. Nodes 1 and 2 hold 25% of deposited funds each
# 3. Node 3 holds 30% of deposited funds
# 4. `LiquidToken` holds 20% of deposited funds
# 5. Staker holds no stETH

# Task files tested:
#  1. SNC_CreateStakerNodes
#  2. LTM_DelegateNodes
#  3. LTM_StakeAssetsToNodes
#  4. LTM_StakeAssetsToNode
#  5. LTM_UndelegateNodes

# To run this script:
# 1. anvil --fork-url $RPC_URL (setup local node on a separate terminal instance)
# 2. chmod +x script/tasks/run.sh
# 3. script/tasks/run.sh

# Check for required dependencies
if ! command -v jq &> /dev/null; then
    echo "Error: jq is required but not installed."
    echo "Please install jq to continue:"
    echo "  - On Ubuntu/Debian: sudo apt-get install jq"
    echo "  - On Mac: brew install jq"
    echo "  - Other systems: https://stedolan.github.io/jq/download/"
    exit 1
fi

# Environment configuration
RPC_URL="127.0.0.1:8545"
ADMIN_PRIVATE_KEY="${ADMIN_PRIVATE_KEY:-0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80}"
ADMIN=$(cast wallet address --private-key $ADMIN_PRIVATE_KEY)
OUTPUT_PATH_MAINNET="../outputs/local/mainnet_deployment_data.json"

# Deploy contracts
forge script --via-ir script/deploy/local/DeployMainnet.s.sol:DeployMainnet \
    --rpc-url $RPC_URL --broadcast \
    --sig "run(string memory networkConfigFileName,string memory deployConfigFileName)" \
    -- "mainnet.json" "deploy_mainnet.anvil.config.json"

# Extract contract addresses from deployment output
LIQUID_TOKEN=$(jq -r '.addresses.liquidToken' $OUTPUT_PATH_MAINNET)
LIQUID_TOKEN_MANAGER=$(jq -r '.addresses.liquidTokenManager' $OUTPUT_PATH_MAINNET)
STETH_TOKEN=$(jq -r '.tokens.token0_address' $OUTPUT_PATH_MAINNET)

# Create four Staker Nodes
NODE_IDS=$(forge script --via-ir script/tasks/SNC_CreateStakerNodes.s.sol:CreateStakerNodes \
    --rpc-url $RPC_URL --broadcast \
    --sig "run(string memory configFileName,uint256 count)" \
    -- "/local/mainnet_deployment_data.json" 4)

# Delegate all nodes to EigenYields
OPERATORS="[\"0x5accc90436492f24e6af278569691e2c942a676d\"]"
forge script --via-ir script/tasks/LTM_DelegateNodes.s.sol:DelegateNodes \
    --rpc-url $RPC_URL --broadcast \
    --sig "run(string memory configFileName,uint256[] memory nodeIds,address[] memory operators,ISignatureUtils.SignatureWithExpiry[] calldata approverSignatureAndExpiries,bytes32[] calldata approverSalts)" \
    -- "/local/mainnet_deployment_data.json" "[$(echo $NODE_IDS | tr -d '[]')]" $OPERATORS "[]" "[]"

# Create a test user to play the role of staker
TEST_USER_KEY="${TEST_USER_PRIVATE_KEY:-0x7c852118294e51e653712a81e05800f419141751be58f605c371e15141b007a6}"
TEST_USER=$(cast wallet address --private-key $TEST_USER_KEY)

# Staker deposits stETH into `LiquidToken`
LIDO_SUBMIT="0xa76a7d0d06754e4106e351f4a3F91A0F916F6980"
cast send $LIDO_SUBMIT --value 10ether --private-key $TEST_USER_KEY
cast send $STETH_TOKEN "approve(address,uint256)" $LIQUID_TOKEN 10000000000000000000 --private-key $TEST_USER_KEY
cast send $LIQUID_TOKEN "deposit(address[],uint256[],address)" \
    "[$STETH_TOKEN]" \
    "[10000000000000000000]" \
    $TEST_USER \
    --private-key $TEST_USER_KEY

# Stake assets to two nodes
NODE_1=$(echo $NODE_IDS | jq '.[0]')
NODE_2=$(echo $NODE_IDS | jq '.[1]')
ALLOCATIONS="[
  {
    \"nodeId\": $NODE_1,
    \"assets\": [\"$STETH_TOKEN\"],
    \"amounts\": [\"2500000000000000000\"]
  },
  {
    \"nodeId\": $NODE_2,
    \"assets\": [\"$STETH_TOKEN\"],
    \"amounts\": [\"2500000000000000000\"]
  }
]"
forge script --via-ir script/tasks/LTM_StakeAssetsToNodes.s.sol:StakeAssetsToNodes \
    --rpc-url $RPC_URL --broadcast \
    --sig "run(string memory configFileName,LiquidTokenManager.NodeAllocation[] calldata allocations)" \
    -- "/local/mainnet_deployment_data.json" "$ALLOCATIONS"

# Stake assets to third node
NODE_3=$(echo $NODE_IDS | jq '.[2]')
ASSETS="[\"$STETH_TOKEN\"]"
AMOUNTS="[\"3000000000000000000\"]"
forge script --via-ir script/tasks/LTM_StakeAssetsToNode.s.sol:StakeAssetsToNode \
    --rpc-url $RPC_URL --broadcast \
    --sig "run(string memory configFileName,uint256 nodeId,IERC20[] memory assets,uint256[] memory amounts)" \
    -- "/local/mainnet_deployment_data.json" "$NODE_3" "$ASSETS" "$AMOUNTS"

# Undelegate fourth node
NODE_4=$(echo $NODE_IDS | jq '.[3]')
forge script --via-ir script/tasks/LTM_UndelegateNodes.s.sol:UndelegateNodes \
    --rpc-url $RPC_URL --broadcast \
    --sig "run(string memory configFileName,uint256[] memory nodeIds)" \
    -- "/local/mainnet_deployment_data.json" "[$NODE_4]"
