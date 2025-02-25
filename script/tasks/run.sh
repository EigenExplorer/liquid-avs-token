#!/bin/bash

#-----------------------------------------------------------------------------------------------------
# README
#-----------------------------------------------------------------------------------------------------

# With this script, we simulate a staker depositing funds and the re-staking manager (admin) deploying them to EigenLayer with the following steps:
#  1. Deploy all LAT contracts with stETH token/strategy registered
#  2. Restaking manager creates four staker nodes
#  3. Restaking manager delegates nodes to an EigenLayer Operator
#  4. Staker deposits stETH by interfacing with `LiquidToken`
#  5. Restaking manager stakes the user's funds to three nodes
#  6. Restaking manager undelegates the fourth node

# End-state verification:
#  1. Three nodes are delegated and the fourth one is not
#  2. First two nodes hold 25% of deposited funds each
#  3. Third node holds 30% of deposited funds and the last one holds none
#  4. `LiquidToken` holds 20% of deposited funds
#  5. Staker holds no stETH and 10 stETH worth of LAT

# Task files tested:
#  1. SNC_CreateStakerNodes
#  2. LTM_DelegateNodes
#  3. LTM_StakeAssetsToNodes
#  4. LTM_StakeAssetsToNode
#  5. LTM_UndelegateNodes

# Instructions:
# To load env file: source .env
# To setup a local node (on a separate terminal instance): anvil --fork-url $RPC_URL
# To run this script (make sure terminal is at the root directory `/liquid-avs-token`):
#  1. chmod +x script/tasks/run.sh
#  2. script/tasks/run.sh

#-----------------------------------------------------------------------------------------------------
# SETUP
#-----------------------------------------------------------------------------------------------------

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
DEPLOYER_PRIVATE_KEY="${DEPLOYER_PRIVATE_KEY:-0x47e179ec197488593b187f80a00eb0da91f1b9d0b13f8733639f19c30a34926a}"
ADMIN_PRIVATE_KEY="${ADMIN_PRIVATE_KEY:-0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80}"
OUTPUT_PATH_MAINNET="script/outputs/local/mainnet_deployment_data.json"

#-----------------------------------------------------------------------------------------------------
# ACTION
#-----------------------------------------------------------------------------------------------------

# Deploy contracts
forge script --via-ir script/deploy/local/DeployMainnet.s.sol:DeployMainnet \
    --rpc-url $RPC_URL --broadcast \
    --private-key $DEPLOYER_PRIVATE_KEY \
    --sig "run(string memory networkConfigFileName,string memory deployConfigFileName)" \
    -- "mainnet.json" "deploy_mainnet.anvil.config.json"

# Extract contract addresses from deployment output
LIQUID_TOKEN=$(jq -r '.addresses.liquidToken' $OUTPUT_PATH_MAINNET)
LIQUID_TOKEN_MANAGER=$(jq -r '.addresses.liquidTokenManager' $OUTPUT_PATH_MAINNET)
STAKER_NODE_COORDINATOR=$(jq -r '.addresses.stakerNodeCoordinator' $OUTPUT_PATH_MAINNET)
STETH_TOKEN=$(jq -r '.tokens.token0_address' $OUTPUT_PATH_MAINNET)

# Create four Staker Nodes
NODE_IDS=$(forge script --via-ir script/tasks/SNC_CreateStakerNodes.s.sol:CreateStakerNodes \
    --rpc-url $RPC_URL --broadcast \
    --private-key $ADMIN_PRIVATE_KEY \
    --sig "run(string memory configFileName,uint256 count)" \
    -- "/local/mainnet_deployment_data.json" 4 2>&1 | \
    grep "uint256\[\]" | sed -E 's/.*\[([0-9, ]+)\].*/\1/g')

# Delegate all nodes to EigenYields
EIGENYIELDS_OPERATOR_ADDRESS="0x5accc90436492f24e6af278569691e2c942a676d"
OPERATORS="[$EIGENYIELDS_OPERATOR_ADDRESS,$EIGENYIELDS_OPERATOR_ADDRESS,$EIGENYIELDS_OPERATOR_ADDRESS,$EIGENYIELDS_OPERATOR_ADDRESS]"
forge script --via-ir script/tasks/LTM_DelegateNodes.s.sol:DelegateNodes \
    --rpc-url $RPC_URL --broadcast \
    --private-key $ADMIN_PRIVATE_KEY \
    --sig "run(string,uint256[],address[],(bytes,uint256)[],bytes32[])" \
    -- "/local/mainnet_deployment_data.json" "[$NODE_IDS]" $OPERATORS "[]" "[]"

# Create a test user to play the role of staker
TEST_USER_PRIVATE_KEY="${TEST_USER_PRIVATE_KEY:-0x7c852118294e51e653712a81e05800f419141751be58f605c371e15141b007a6}"
TEST_USER=$(cast wallet address --private-key $TEST_USER_PRIVATE_KEY)

# Staker deposits stETH into `LiquidToken`
DEPOSIT_AMOUNT=10000000000000000000
cast send $STETH_TOKEN --private-key $TEST_USER_PRIVATE_KEY --value $DEPOSIT_AMOUNT
STAKER_STETH_INITIAL_BALANCE=$(cast call $STETH_TOKEN "balanceOf(address)(uint256)" $TEST_USER | awk '{print $1}' | cast --from-wei)
cast send $STETH_TOKEN --private-key $TEST_USER_PRIVATE_KEY "approve(address,uint256)" $LIQUID_TOKEN $DEPOSIT_AMOUNT
cast send $LIQUID_TOKEN --private-key $TEST_USER_PRIVATE_KEY "deposit(address[],uint256[],address)" \
    "[$STETH_TOKEN]" "[$DEPOSIT_AMOUNT]" $TEST_USER

# Stake assets to two nodes
NODE_IDS="[$(echo $NODE_IDS | tr -d ' ')]"
NODE_1=$(echo $NODE_IDS | jq '.[0]')
NODE_2=$(echo $NODE_IDS | jq '.[1]')
ALLOCATIONS="[(${NODE_1},[${STETH_TOKEN}],[2500000000000000000]),(${NODE_2},[${STETH_TOKEN}],[2500000000000000000])]"
forge script --via-ir script/tasks/LTM_StakeAssetsToNodes.s.sol:StakeAssetsToNodes \
    --rpc-url $RPC_URL --broadcast \
    --private-key $ADMIN_PRIVATE_KEY \
    --sig "run(string,(uint256,address[],uint256[])[])" \
    -- "/local/mainnet_deployment_data.json" $ALLOCATIONS

# Stake assets to third node
NODE_3=$(echo $NODE_IDS | jq '.[2]')
forge script --via-ir script/tasks/LTM_StakeAssetsToNode.s.sol:StakeAssetsToNode \
    --rpc-url $RPC_URL --broadcast \
    --private-key $ADMIN_PRIVATE_KEY \
    --sig "run(string,uint256,address[],uint256[])" \
    -- "/local/mainnet_deployment_data.json" $NODE_3 "[$STETH_TOKEN]" "[3000000000000000000]"

# Undelegate fourth node
NODE_4=$(echo $NODE_IDS | jq '.[3]')
forge script --via-ir script/tasks/LTM_UndelegateNodes.s.sol:UndelegateNodes \
    --rpc-url $RPC_URL --broadcast \
    --private-key $ADMIN_PRIVATE_KEY \
    --sig "run(string memory configFileName,uint256[] memory nodeIds)" \
    -- "/local/mainnet_deployment_data.json" "[$NODE_4]"

#-----------------------------------------------------------------------------------------------------
# VERIFICATION
#-----------------------------------------------------------------------------------------------------

# Prep all state info
TOTAL_DEPOSIT=$(echo $DEPOSIT_AMOUNT | cast --from-wei)

NODE_1_ADDRESS=$(cast call $STAKER_NODE_COORDINATOR "getNodeById(uint256)(address)" $NODE_1)
NODE_1_OPERATOR_DELEGATION=$(cast call $NODE_1_ADDRESS "getOperatorDelegation()(address)")
NODE_1_STAKED_BALANCE=$(cast call $LIQUID_TOKEN_MANAGER "getStakedAssetBalanceNode(address,uint256)" $STETH_TOKEN $NODE_1 | cast --to-dec | cast --from-wei)

NODE_2_ADDRESS=$(cast call $STAKER_NODE_COORDINATOR "getNodeById(uint256)(address)" $NODE_2)
NODE_2_OPERATOR_DELEGATION=$(cast call $NODE_2_ADDRESS "getOperatorDelegation()(address)")
NODE_2_STAKED_BALANCE=$(cast call $LIQUID_TOKEN_MANAGER "getStakedAssetBalanceNode(address,uint256)" $STETH_TOKEN $NODE_2 | cast --to-dec | cast --from-wei)

NODE_3_ADDRESS=$(cast call $STAKER_NODE_COORDINATOR "getNodeById(uint256)(address)" $NODE_3)
NODE_3_OPERATOR_DELEGATION=$(cast call $NODE_3_ADDRESS "getOperatorDelegation()(address)")
NODE_3_STAKED_BALANCE=$(cast call $LIQUID_TOKEN_MANAGER "getStakedAssetBalanceNode(address,uint256)" $STETH_TOKEN $NODE_3 | cast --to-dec | cast --from-wei)

NODE_4_ADDRESS=$(cast call $STAKER_NODE_COORDINATOR "getNodeById(uint256)(address)" $NODE_4)
NODE_4_OPERATOR_DELEGATION=$(cast call $NODE_4_ADDRESS "getOperatorDelegation()(address)")
NODE_4_STAKED_BALANCE=$(cast call $LIQUID_TOKEN_MANAGER "getStakedAssetBalanceNode(address,uint256)" $STETH_TOKEN $NODE_4 | cast --to-dec | cast --from-wei)

LIQUID_TOKEN_BALANCE=$(cast call $STETH_TOKEN "balanceOf(address)(uint256)" $LIQUID_TOKEN | awk '{print $1}' | cast --from-wei)
STAKER_LAT_BALANCE=$(cast call $LIQUID_TOKEN "balanceOf(address)(uint256)" $TEST_USER | awk '{print $1}' | cast --from-wei)
STAKER_STETH_FINAL_BALANCE=$(cast call $STETH_TOKEN "balanceOf(address)(uint256)" $TEST_USER | awk '{print $1}' | cast --from-wei)
STAKER_STETH_BALANCE_CHANGE=$(echo "$STAKER_STETH_INITIAL_BALANCE - $STAKER_STETH_FINAL_BALANCE" | bc)

# Log output
echo "------------------------------------------------------------------"
echo "End-state verification"
echo "------------------------------------------------------------------"
echo "1. Three nodes are delegated and the fourth one is not"
echo "Node $NODE_1 delegation: $NODE_1_OPERATOR_DELEGATION"
echo "Node $NODE_2 delegation: $NODE_2_OPERATOR_DELEGATION"
echo "Node $NODE_3 delegation: $NODE_3_OPERATOR_DELEGATION"
echo "Node $NODE_4 delegation: $NODE_4_OPERATOR_DELEGATION"
echo
echo "2. First two nodes hold 25% of deposited funds each"
echo "Total deposit amount: $TOTAL_DEPOSIT"
echo "Node $NODE_1 staked balance: $NODE_1_STAKED_BALANCE"
echo "Node $NODE_2 staked balance: $NODE_2_STAKED_BALANCE"
echo
echo "3. Third node holds 30% of deposited funds and the last one holds none"
echo "Total deposit amount: $TOTAL_DEPOSIT"
echo "Node $NODE_3 staked balance: $NODE_3_STAKED_BALANCE"
echo "Node $NODE_4 staked balance: $NODE_4_STAKED_BALANCE"
echo
echo "4. LiquidToken holds 20% of deposited funds"
echo "Total deposit amount: $TOTAL_DEPOSIT"
echo "LiquidToken balance: $LIQUID_TOKEN_BALANCE"
echo
echo "5. Staker holds 10 stETH less and 10 stETH worth of LAT"
echo "Staker stETH balance change: $STAKER_STETH_BALANCE_CHANGE"
echo "Staker LAT balance: $STAKER_LAT_BALANCE"
echo "------------------------------------------------------------------"