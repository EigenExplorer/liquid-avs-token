#!/bin/bash

#-----------------------------------------------------------------------------------------------------
# README
#-----------------------------------------------------------------------------------------------------

# With this script, we simulate a staker depositing funds and the re-staking manager (admin) deploying them
# to EigenLayer with the following steps:
#  1. Deploy all LAT contracts with stETH token/strategy registered
#  2. Restaking manager creates five staker nodes
#  3. Restaking manager delegates nodes to an EigenLayer Operator
#  4. Update token prices via price updater
#  5. Two stakers deposit stETH & rETH by interfacing with `LiquidToken`
#  6. Restaking manager stakes the users' funds to the first three nodes
#  7. Restaking manager undelegates the fourth and fifth nodes

# End-state verification:
#  1. Three nodes are delegated, fourth and fifth are not
#  2. First two nodes hold 25% of deposited funds each
#  3. Third node holds 30% of deposited funds, fourth and fifth hold none
#  4. `LiquidToken` holds 20% of deposited funds
#  5. Stakers hold no original tokens and equivalent LAT
#  6. Each token had 2 price updates each

# Task files tested:
#  1. SNC_CreateStakerNodes
#  2. LTM_DelegateNodes
#  3. LTM_StakeAssetsToNodes
#  4. LTM_StakeAssetsToNode
#  5. LTM_UndelegateNodes

# Task files not tested:
#  1. TRO_UpdatePrices (consider using these tasks in price-updater v2)

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
RPC_URL="http://127.0.0.1:8545"
DEPLOYER_PRIVATE_KEY="${DEPLOYER_PRIVATE_KEY:-0x47e179ec197488593b187f80a00eb0da91f1b9d0b13f8733639f19c30a34926a}"
ADMIN_PRIVATE_KEY="${ADMIN_PRIVATE_KEY:-0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80}"
PRICE_UPDATER_PRIVATE_KEY="${PRICE_UPDATER_PRIVATE_KEY:-0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a}"
OUTPUT_PATH_MAINNET="script/outputs/local/mainnet_deployment_data.json"

#-----------------------------------------------------------------------------------------------------
# ACTION
#-----------------------------------------------------------------------------------------------------

# Create output directory if it doesn't exist
mkdir -p script/outputs/local

# Deploy contracts
forge script --via-ir script/deploy/local/DeployMainnet.s.sol:DeployMainnet \
    --rpc-url $RPC_URL --broadcast \
    --private-key $DEPLOYER_PRIVATE_KEY \
    --sig "run(string,string)" \
    -- "mainnet.json" "xeigenda_mainnet.anvil.config.json"

# Extract contract addresses from deployment output
LIQUID_TOKEN=$(jq -r '.proxyAddress' $OUTPUT_PATH_MAINNET)
LIQUID_TOKEN_MANAGER=$(jq -r '.contractDeployments.proxy.liquidTokenManager.address' $OUTPUT_PATH_MAINNET)
STAKER_NODE_COORDINATOR=$(jq -r '.contractDeployments.proxy.stakerNodeCoordinator.address' $OUTPUT_PATH_MAINNET)
STETH_TOKEN=$(jq -r '.tokens["0"].address' $OUTPUT_PATH_MAINNET)
RETH_TOKEN=$(jq -r '.tokens["1"].address' $OUTPUT_PATH_MAINNET)

# Create five Staker Nodes
NODE_IDS=$(forge script --via-ir script/tasks/SNC_CreateStakerNodes.s.sol:CreateStakerNodes \
    --rpc-url $RPC_URL --broadcast \
    --private-key $ADMIN_PRIVATE_KEY \
    --sig "run(string,uint256)" \
    -- "/local/mainnet_deployment_data.json" 5 2>&1 | \
    grep "uint256\[\]" | sed -E 's/.*\[([0-9, ]+)\].*/\1/g')

# Delegate all nodes to EigenYields
EIGENYIELDS_OPERATOR_ADDRESS="0x5accc90436492f24e6af278569691e2c942a676d"
OPERATORS="[$EIGENYIELDS_OPERATOR_ADDRESS,$EIGENYIELDS_OPERATOR_ADDRESS,$EIGENYIELDS_OPERATOR_ADDRESS,$EIGENYIELDS_OPERATOR_ADDRESS,$EIGENYIELDS_OPERATOR_ADDRESS]"
forge script --via-ir script/tasks/LTM_DelegateNodes.s.sol:DelegateNodes \
    --rpc-url $RPC_URL --broadcast \
    --private-key $ADMIN_PRIVATE_KEY \
    --sig "run(string,uint256[],address[],(bytes,uint256)[],bytes32[])" \
    -- "/local/mainnet_deployment_data.json" "[$NODE_IDS]" $OPERATORS "[]" "[]"

# Update prices of stETH and rETH individually
TOKEN_REGISTRY_ORACLE=$(jq -r '.contractDeployments.proxy.tokenRegistryOracle.address' $OUTPUT_PATH_MAINNET)
STETH_INITIAL_PRICE=$(cast call $TOKEN_REGISTRY_ORACLE "getRate(address)(uint256)" $STETH_TOKEN)
STETH_INITIAL_PRICE_CLEAN=$(echo $STETH_INITIAL_PRICE | tr -d '[]' | sed 's/e[0-9]*//' | awk '{print $1}')
STETH_INITIAL_PRICE_ETH=$(cast --from-wei $STETH_INITIAL_PRICE_CLEAN)
RETH_INITIAL_PRICE=$(cast call $TOKEN_REGISTRY_ORACLE "getRate(address)(uint256)" $RETH_TOKEN)
RETH_INITIAL_PRICE_CLEAN=$(echo $RETH_INITIAL_PRICE | tr -d '[]' | sed 's/e[0-9]*//' | awk '{print $1}')
RETH_INITIAL_PRICE_ETH=$(cast --from-wei $RETH_INITIAL_PRICE_CLEAN)
NEW_STETH_PRICE="1020000000000000000"
cast send $TOKEN_REGISTRY_ORACLE --private-key $PRICE_UPDATER_PRIVATE_KEY "updateRate(address,uint256)" $STETH_TOKEN $NEW_STETH_PRICE
NEW_RETH_PRICE="1070000000000000000"
cast send $TOKEN_REGISTRY_ORACLE --private-key $PRICE_UPDATER_PRIVATE_KEY "updateRate(address,uint256)" $RETH_TOKEN $NEW_RETH_PRICE
STETH_UPDATED_PRICE_1=$(cast call $TOKEN_REGISTRY_ORACLE "getRate(address)(uint256)" $STETH_TOKEN)
STETH_UPDATED_PRICE_1_CLEAN=$(echo $STETH_UPDATED_PRICE_1 | tr -d '[]' | sed 's/e[0-9]*//' | awk '{print $1}')
STETH_UPDATED_PRICE_1_ETH=$(cast --from-wei $STETH_UPDATED_PRICE_1_CLEAN)
RETH_UPDATED_PRICE_1=$(cast call $TOKEN_REGISTRY_ORACLE "getRate(address)(uint256)" $RETH_TOKEN)
RETH_UPDATED_PRICE_1_CLEAN=$(echo $RETH_UPDATED_PRICE_1 | tr -d '[]' | sed 's/e[0-9]*//' | awk '{print $1}')
RETH_UPDATED_PRICE_1_ETH=$(cast --from-wei $RETH_UPDATED_PRICE_1_CLEAN)

# Update prices of stETH and rETH in a single transaction
NEW_STETH_PRICE_2="1030000000000000000"
NEW_RETH_PRICE_2="1080000000000000000"
cast send $TOKEN_REGISTRY_ORACLE --private-key $PRICE_UPDATER_PRIVATE_KEY "batchUpdateRates(address[],uint256[])" "[$STETH_TOKEN,$RETH_TOKEN]" "[$NEW_STETH_PRICE_2,$NEW_RETH_PRICE_2]"
STETH_UPDATED_PRICE_2=$(cast call $TOKEN_REGISTRY_ORACLE "getRate(address)(uint256)" $STETH_TOKEN)
STETH_UPDATED_PRICE_2_CLEAN=$(echo $STETH_UPDATED_PRICE_2 | tr -d '[]' | sed 's/e[0-9]*//' | awk '{print $1}')
STETH_UPDATED_PRICE_2_ETH=$(cast --from-wei $STETH_UPDATED_PRICE_2_CLEAN)
RETH_UPDATED_PRICE_2=$(cast call $TOKEN_REGISTRY_ORACLE "getRate(address)(uint256)" $RETH_TOKEN)
RETH_UPDATED_PRICE_2_CLEAN=$(echo $RETH_UPDATED_PRICE_2 | tr -d '[]' | sed 's/e[0-9]*//' | awk '{print $1}')
RETH_UPDATED_PRICE_2_ETH=$(cast --from-wei $RETH_UPDATED_PRICE_2_CLEAN)

# Store these values for verification output
STETH_INITIAL_PRICE_FOR_VERIFY=$STETH_INITIAL_PRICE_ETH
RETH_INITIAL_PRICE_FOR_VERIFY=$RETH_INITIAL_PRICE_ETH
STETH_PRICE_AFTER_FIRST_UPDATE=$STETH_UPDATED_PRICE_1_ETH
RETH_PRICE_AFTER_FIRST_UPDATE=$RETH_UPDATED_PRICE_1_ETH
STETH_PRICE_AFTER_SECOND_UPDATE=$STETH_UPDATED_PRICE_2_ETH
RETH_PRICE_AFTER_SECOND_UPDATE=$RETH_UPDATED_PRICE_2_ETH

# Create two test users to play the role of staker
TEST_USER_1_PRIVATE_KEY="${TEST_USER_1_PRIVATE_KEY:-0x7c852118294e51e653712a81e05800f419141751be58f605c371e15141b007a6}"
TEST_USER_1=$(cast wallet address --private-key $TEST_USER_1_PRIVATE_KEY)
TEST_USER_2_PRIVATE_KEY="${TEST_USER_2_PRIVATE_KEY:-0x47e179ec197488593b187f80a00eb0da91f1b9d0b13f8733639f19c30a34926a}"
TEST_USER_2=$(cast wallet address --private-key $TEST_USER_2_PRIVATE_KEY)

# Staker 1 deposits stETH into `LiquidToken`
STAKER_1_STETH_DEPOSIT_AMOUNT=25000000000000000000
cast send $STETH_TOKEN --private-key $TEST_USER_1_PRIVATE_KEY --value $STAKER_1_STETH_DEPOSIT_AMOUNT
STAKER_1_STETH_INITIAL_BALANCE=$(cast call $STETH_TOKEN "balanceOf(address)(uint256)" $TEST_USER_1 | awk '{print $1}' | cast --from-wei)
cast send $STETH_TOKEN --private-key $TEST_USER_1_PRIVATE_KEY "approve(address,uint256)" $LIQUID_TOKEN $STAKER_1_STETH_DEPOSIT_AMOUNT
cast send $LIQUID_TOKEN --private-key $TEST_USER_1_PRIVATE_KEY "deposit(address[],uint256[],address)" \
    "[$STETH_TOKEN]" "[$STAKER_1_STETH_DEPOSIT_AMOUNT]" $TEST_USER_1

# Staker 2 deposits stETH & rETH into `LiquidToken`
STAKER_2_STETH_DEPOSIT_AMOUNT=5000000000000000000
cast send $STETH_TOKEN --private-key $TEST_USER_2_PRIVATE_KEY --value $STAKER_2_STETH_DEPOSIT_AMOUNT
STAKER_2_STETH_INITIAL_BALANCE=$(cast call $STETH_TOKEN "balanceOf(address)(uint256)" $TEST_USER_2 | awk '{print $1}' | cast --from-wei)
cast send $STETH_TOKEN --private-key $TEST_USER_2_PRIVATE_KEY "approve(address,uint256)" $LIQUID_TOKEN $STAKER_2_STETH_DEPOSIT_AMOUNT
STAKER_2_RETH_DEPOSIT_AMOUNT=20000000000000000000
RETH_WHALE="0x3ad1b118813e71a6b2683fcb2044122fe195ac36"
cast rpc anvil_impersonateAccount $RETH_WHALE
cast send $RETH_TOKEN --unlocked --from $RETH_WHALE "transfer(address,uint256)" $TEST_USER_2 $STAKER_2_RETH_DEPOSIT_AMOUNT * 10
cast rpc anvil_stopImpersonatingAccount $RETH_WHALE
STAKER_2_RETH_INITIAL_BALANCE=$(cast call $RETH_TOKEN "balanceOf(address)(uint256)" $TEST_USER_2 | awk '{print $1}' | cast --from-wei)
cast send $RETH_TOKEN --private-key $TEST_USER_2_PRIVATE_KEY "approve(address,uint256)" $LIQUID_TOKEN $STAKER_2_RETH_DEPOSIT_AMOUNT
cast send $LIQUID_TOKEN --private-key $TEST_USER_2_PRIVATE_KEY "deposit(address[],uint256[],address)" \
    "[$STETH_TOKEN,$RETH_TOKEN]" "[$STAKER_2_STETH_DEPOSIT_AMOUNT,$STAKER_2_RETH_DEPOSIT_AMOUNT]" $TEST_USER_2

# Stake assets to two nodes
NODE_IDS="[$(echo $NODE_IDS | tr -d ' ')]"
NODE_1=$(echo $NODE_IDS | jq '.[0]')
NODE_2=$(echo $NODE_IDS | jq '.[1]')
ALLOCATIONS="[(${NODE_1},[${STETH_TOKEN},${RETH_TOKEN}],[7500000000000000000,5000000000000000000]),(${NODE_2},[${STETH_TOKEN},${RETH_TOKEN}],[7500000000000000000,5000000000000000000])]"
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
    -- "/local/mainnet_deployment_data.json" $NODE_3 "[$STETH_TOKEN,$RETH_TOKEN]" "[9000000000000000000,6000000000000000000]"

# Undelegate fourth and fifth nodes
NODE_4=$(echo $NODE_IDS | jq '.[3]')
NODE_5=$(echo $NODE_IDS | jq '.[4]')
forge script --via-ir script/tasks/LTM_UndelegateNodes.s.sol:UndelegateNodes \
    --rpc-url $RPC_URL --broadcast \
    --private-key $ADMIN_PRIVATE_KEY \
    --sig "run(string,uint256[])" \
    -- "/local/mainnet_deployment_data.json" "[$NODE_4,$NODE_5]"

#-----------------------------------------------------------------------------------------------------
# VERIFICATION
#-----------------------------------------------------------------------------------------------------

# Prep all state info
STAKER_1_STETH_DEPOSIT_AMOUNT=$(echo $STAKER_1_STETH_DEPOSIT_AMOUNT | cast --from-wei)
STAKER_2_STETH_DEPOSIT_AMOUNT=$(echo $STAKER_2_STETH_DEPOSIT_AMOUNT | cast --from-wei)
STAKER_2_RETH_DEPOSIT_AMOUNT=$(echo $STAKER_2_RETH_DEPOSIT_AMOUNT | cast --from-wei)
TOTAL_STETH_DEPOSIT=$(echo "$STAKER_1_STETH_DEPOSIT_AMOUNT + $STAKER_2_STETH_DEPOSIT_AMOUNT" | bc)
TOTAL_RETH_DEPOSIT=$STAKER_2_RETH_DEPOSIT_AMOUNT

NODE_1_ADDRESS=$(cast call $STAKER_NODE_COORDINATOR "getNodeById(uint256)(address)" $NODE_1)
NODE_1_OPERATOR_DELEGATION=$(cast call $NODE_1_ADDRESS "getOperatorDelegation()(address)")
NODE_1_STAKED_STETH_BALANCE=$(cast call $LIQUID_TOKEN_MANAGER "getStakedAssetBalanceNode(address,uint256)" $STETH_TOKEN $NODE_1 | cast --to-dec | cast --from-wei)
NODE_1_STAKED_RETH_BALANCE=$(cast call $LIQUID_TOKEN_MANAGER "getStakedAssetBalanceNode(address,uint256)" $RETH_TOKEN $NODE_1 | cast --to-dec | cast --from-wei)

NODE_2_ADDRESS=$(cast call $STAKER_NODE_COORDINATOR "getNodeById(uint256)(address)" $NODE_2)
NODE_2_OPERATOR_DELEGATION=$(cast call $NODE_2_ADDRESS "getOperatorDelegation()(address)")
NODE_2_STAKED_STETH_BALANCE=$(cast call $LIQUID_TOKEN_MANAGER "getStakedAssetBalanceNode(address,uint256)" $STETH_TOKEN $NODE_2 | cast --to-dec | cast --from-wei)
NODE_2_STAKED_RETH_BALANCE=$(cast call $LIQUID_TOKEN_MANAGER "getStakedAssetBalanceNode(address,uint256)" $RETH_TOKEN $NODE_2 | cast --to-dec | cast --from-wei)

NODE_3_ADDRESS=$(cast call $STAKER_NODE_COORDINATOR "getNodeById(uint256)(address)" $NODE_3)
NODE_3_OPERATOR_DELEGATION=$(cast call $NODE_3_ADDRESS "getOperatorDelegation()(address)")
NODE_3_STAKED_STETH_BALANCE=$(cast call $LIQUID_TOKEN_MANAGER "getStakedAssetBalanceNode(address,uint256)" $STETH_TOKEN $NODE_3 | cast --to-dec | cast --from-wei)
NODE_3_STAKED_RETH_BALANCE=$(cast call $LIQUID_TOKEN_MANAGER "getStakedAssetBalanceNode(address,uint256)" $RETH_TOKEN $NODE_3 | cast --to-dec | cast --from-wei)

NODE_4_ADDRESS=$(cast call $STAKER_NODE_COORDINATOR "getNodeById(uint256)(address)" $NODE_4)
NODE_4_OPERATOR_DELEGATION=$(cast call $NODE_4_ADDRESS "getOperatorDelegation()(address)")
NODE_4_STAKED_STETH_BALANCE=$(cast call $LIQUID_TOKEN_MANAGER "getStakedAssetBalanceNode(address,uint256)" $STETH_TOKEN $NODE_4 | cast --to-dec | cast --from-wei)
NODE_4_STAKED_RETH_BALANCE=$(cast call $LIQUID_TOKEN_MANAGER "getStakedAssetBalanceNode(address,uint256)" $RETH_TOKEN $NODE_4 | cast --to-dec | cast --from-wei)

NODE_5_ADDRESS=$(cast call $STAKER_NODE_COORDINATOR "getNodeById(uint256)(address)" $NODE_5)
NODE_5_OPERATOR_DELEGATION=$(cast call $NODE_5_ADDRESS "getOperatorDelegation()(address)")
NODE_5_STAKED_STETH_BALANCE=$(cast call $LIQUID_TOKEN_MANAGER "getStakedAssetBalanceNode(address,uint256)" $STETH_TOKEN $NODE_5 | cast --to-dec | cast --from-wei)
NODE_5_STAKED_RETH_BALANCE=$(cast call $LIQUID_TOKEN_MANAGER "getStakedAssetBalanceNode(address,uint256)" $RETH_TOKEN $NODE_5 | cast --to-dec | cast --from-wei)

LIQUID_TOKEN_STETH_BALANCE=$(cast call $STETH_TOKEN "balanceOf(address)(uint256)" $LIQUID_TOKEN | awk '{print $1}' | cast --from-wei)
LIQUID_TOKEN_RETH_BALANCE=$(cast call $RETH_TOKEN "balanceOf(address)(uint256)" $LIQUID_TOKEN | awk '{print $1}' | cast --from-wei)

STAKER_1_LAT_BALANCE=$(cast call $LIQUID_TOKEN "balanceOf(address)(uint256)" $TEST_USER_1 | awk '{print $1}' | cast --from-wei)
STAKER_1_STETH_FINAL_BALANCE=$(cast call $STETH_TOKEN "balanceOf(address)(uint256)" $TEST_USER_1 | awk '{print $1}' | cast --from-wei)
STAKER_1_STETH_BALANCE_CHANGE=$(echo "$STAKER_1_STETH_INITIAL_BALANCE - $STAKER_1_STETH_FINAL_BALANCE" | bc)

STAKER_2_LAT_BALANCE=$(cast call $LIQUID_TOKEN "balanceOf(address)(uint256)" $TEST_USER_2 | awk '{print $1}' | cast --from-wei)
STAKER_2_STETH_FINAL_BALANCE=$(cast call $STETH_TOKEN "balanceOf(address)(uint256)" $TEST_USER_2 | awk '{print $1}' | cast --from-wei)
STAKER_2_STETH_BALANCE_CHANGE=$(echo "$STAKER_2_STETH_INITIAL_BALANCE - $STAKER_2_STETH_FINAL_BALANCE" | bc)
STAKER_2_RETH_FINAL_BALANCE=$(cast call $RETH_TOKEN "balanceOf(address)(uint256)" $TEST_USER_2 | awk '{print $1}' | cast --from-wei)
STAKER_2_RETH_BALANCE_CHANGE=$(echo "$STAKER_2_RETH_INITIAL_BALANCE - $STAKER_2_RETH_FINAL_BALANCE" | bc)

TOTAL_STETH_STAKED=$(echo "$NODE_1_STAKED_STETH_BALANCE + $NODE_2_STAKED_STETH_BALANCE + $NODE_3_STAKED_STETH_BALANCE" | bc)
TOTAL_RETH_STAKED=$(echo "$NODE_1_STAKED_RETH_BALANCE + $NODE_2_STAKED_RETH_BALANCE + $NODE_3_STAKED_RETH_BALANCE" | bc)
NODE_1_STETH_PERCENT=$(echo "scale=2; $NODE_1_STAKED_STETH_BALANCE * 100 / $TOTAL_STETH_DEPOSIT" | bc)
NODE_1_RETH_PERCENT=$(echo "scale=2; $NODE_1_STAKED_RETH_BALANCE * 100 / $TOTAL_RETH_DEPOSIT" | bc)
NODE_2_STETH_PERCENT=$(echo "scale=2; $NODE_2_STAKED_STETH_BALANCE * 100 / $TOTAL_STETH_DEPOSIT" | bc)
NODE_2_RETH_PERCENT=$(echo "scale=2; $NODE_2_STAKED_RETH_BALANCE * 100 / $TOTAL_RETH_DEPOSIT" | bc)
NODE_3_STETH_PERCENT=$(echo "scale=2; $NODE_3_STAKED_STETH_BALANCE * 100 / $TOTAL_STETH_DEPOSIT" | bc)
NODE_3_RETH_PERCENT=$(echo "scale=2; $NODE_3_STAKED_RETH_BALANCE * 100 / $TOTAL_RETH_DEPOSIT" | bc)
LIQUID_TOKEN_STETH_PERCENT=$(echo "scale=2; $LIQUID_TOKEN_STETH_BALANCE * 100 / $TOTAL_STETH_DEPOSIT" | bc)
LIQUID_TOKEN_RETH_PERCENT=$(echo "scale=2; $LIQUID_TOKEN_RETH_BALANCE * 100 / $TOTAL_RETH_DEPOSIT" | bc)

# Log output
echo "------------------------------------------------------------------"
echo "End-state verification"
echo "------------------------------------------------------------------"
echo "1. Three nodes are delegated, fourth and fifth are not"
echo "Node $NODE_1 delegation: $NODE_1_OPERATOR_DELEGATION"
echo "Node $NODE_2 delegation: $NODE_2_OPERATOR_DELEGATION"
echo "Node $NODE_3 delegation: $NODE_3_OPERATOR_DELEGATION"
echo "Node $NODE_4 delegation: $NODE_4_OPERATOR_DELEGATION"
echo "Node $NODE_5 delegation: $NODE_5_OPERATOR_DELEGATION"
echo
echo "2. First two nodes hold 25% of deposited funds each"
echo "Total stETH deposit: $TOTAL_STETH_DEPOSIT"
echo "Total rETH deposit: $TOTAL_RETH_DEPOSIT"
echo "Node $NODE_1 staked stETH balance: $NODE_1_STAKED_STETH_BALANCE ($NODE_1_STETH_PERCENT%)"
echo "Node $NODE_1 staked rETH balance: $NODE_1_STAKED_RETH_BALANCE ($NODE_1_RETH_PERCENT%)"
echo "Node $NODE_2 staked stETH balance: $NODE_2_STAKED_STETH_BALANCE ($NODE_2_STETH_PERCENT%)"
echo "Node $NODE_2 staked rETH balance: $NODE_2_STAKED_RETH_BALANCE ($NODE_2_RETH_PERCENT%)"
echo
echo "3. Third node holds 30% of deposited funds, fourth and fifth hold none"
echo "Node $NODE_3 staked stETH balance: $NODE_3_STAKED_STETH_BALANCE ($NODE_3_STETH_PERCENT%)"
echo "Node $NODE_3 staked rETH balance: $NODE_3_STAKED_RETH_BALANCE ($NODE_3_RETH_PERCENT%)"
echo "Node $NODE_4 staked stETH balance: $NODE_4_STAKED_STETH_BALANCE"
echo "Node $NODE_4 staked rETH balance: $NODE_4_STAKED_RETH_BALANCE"
echo "Node $NODE_5 staked stETH balance: $NODE_5_STAKED_STETH_BALANCE"
echo "Node $NODE_5 staked rETH balance: $NODE_5_STAKED_RETH_BALANCE"
echo
echo "4. LiquidToken holds 20% of deposited funds"
echo "LiquidToken stETH balance: $LIQUID_TOKEN_STETH_BALANCE ($LIQUID_TOKEN_STETH_PERCENT%)"
echo "LiquidToken rETH balance: $LIQUID_TOKEN_RETH_BALANCE ($LIQUID_TOKEN_RETH_PERCENT%)"
echo
echo "5. Stakers hold no original tokens and equivalent LAT"
echo "Staker 1 stETH balance change: $STAKER_1_STETH_BALANCE_CHANGE"
echo "Staker 1 LAT balance: $STAKER_1_LAT_BALANCE"
echo "Staker 2 stETH balance change: $STAKER_2_STETH_BALANCE_CHANGE"
echo "Staker 2 rETH balance change: $STAKER_2_RETH_BALANCE_CHANGE"
echo "Staker 2 LAT balance: $STAKER_2_LAT_BALANCE"
echo 
echo "6. Each token had 2 price updates each"
echo "stETH: $STETH_INITIAL_PRICE_ETH → $STETH_UPDATED_PRICE_1_ETH → $STETH_UPDATED_PRICE_2_ETH ETH"
echo "rETH:  $RETH_INITIAL_PRICE_ETH → $RETH_UPDATED_PRICE_1_ETH → $RETH_UPDATED_PRICE_2_ETH ETH"
echo "------------------------------------------------------------------"