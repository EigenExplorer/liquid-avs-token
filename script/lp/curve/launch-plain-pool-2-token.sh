#!/bin/bash

#-----------------------------------------------------------------------------------------------------
# README
#-----------------------------------------------------------------------------------------------------

# This script launches a 2-token plain pool to Curve and adds initial liquidity following 4 steps:
#  1. Convert ETH to WETH (optional)
#  2. Deploy Curve pool
#  3. Deploy gauge
#  4. Add liquidity

# Instructions:
# To setup a local node (on a separate terminal instance): anvil --fork-url $RPC_URL
# Edit the script where "User action" is marked
# To run this script (make sure terminal is at the root directory `/liquid-avs-token`):
#  1. chmod +x script/lp/curve/launch-plain-pool-2-token.sh
#  2. script/lp/curve/launch-plain-pool-2-token.sh
# Make sure you have sufficient ETH and tokens in your deployer account

#-----------------------------------------------------------------------------------------------------
# SETUP
#-----------------------------------------------------------------------------------------------------
# Auto-load environment variables
if [ -f .env ]; then
    source .env
    echo "[Script] Environment variables loaded from .env"
else
    echo "[Script] Error: .env file not found"
    exit 1
fi

# Check for required env vars
if [ -z "$LP_DEPLOYER_PRIVATE_KEY" ]; then
    echo "[Script] Error: LP_DEPLOYER_PRIVATE_KEY environment variable is not set"
    exit 0
fi

if [ -z "$RPC_URL" ]; then
    echo "[Script] Error: RPC_URL environment variable is not set"
    exit 0
fi


# User action (1/3): Edit pool configuration
POOL_CONFIG_FILE_NAME="xeigenda-eth-weth"
LAT_ADDRESS="0xLatAddress" # should match pool config
CHAIN="mainnet"
RPC_URL= $RPC_URL # "http://127.0.0.1:8545" for local

# User action (2/3): Set liquidity parameters
TOKEN_AMOUNTS='["1000000000000000000","1000000000000000000"]'  # [1 token1, 1 WETH] - adjust decimals accordingly

# User action (3/3): Set ETH<>WETH conversion amount
ETH_TO_CONVERT="2000000000000000000"  # should be >= sum of WETH needed for liquidity

# Configuration
DEPLOYER_PRIVATE_KEY=$LP_DEPLOYER_PRIVATE_KEY
CONFIG_PATH="./configs/${POOL_CONFIG_FILE_NAME}.json"
OUTPUT_FOLDER="./outputs"
TOKEN_ADDRESSES="[${LAT_ADDRESS},"0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2"]"  # [LAT, WETH]
IS_METAPOOL=false

# Create output directories
mkdir -p $OUTPUT_FOLDER

# Get chain ID from RPC
CHAIN_ID=$(cast chain-id --rpc-url $RPC_URL 2>/dev/null)
if [ $? -ne 0 ]; then
    echo "[Script] Error: Unable to connect to RPC at $RPC_URL"
    echo "[Script] Make sure anvil is running: anvil --fork-url \$RPC_URL"
    exit 1
fi
echo "[Script] Chain ID: $CHAIN_ID"

# Validate config file exists
if [ ! -f "$CONFIG_PATH" ]; then
    echo "[Script] Error: Config file not found at $CONFIG_PATH"
    echo "[Script] Please create the config file or update POOL_CONFIG_FILE_NAME"
    exit 1
fi

#-----------------------------------------------------------------------------------------------------
# STEP 1: CONVERT ETH TO WETH (if needed)
#-----------------------------------------------------------------------------------------------------

echo "[Deploy] Converting ETH to WETH..."

forge script script/lp/curve/tasks/ConvertEthToWeth.s.sol:ConvertEthToWeth \
    --rpc-url $RPC_URL --broadcast \
    --private-key $DEPLOYER_PRIVATE_KEY \
    --sig "run(uint256)" \
    -- $ETH_TO_CONVERT \
    --value ${ETH_TO_CONVERT} \
    -v

if [ $? -ne 0 ]; then
    echo "[Script] Error: Failed to convert ETH to WETH"
    exit 1
fi

#-----------------------------------------------------------------------------------------------------
# STEP 2: DEPLOY CURVE POOL
#-----------------------------------------------------------------------------------------------------

echo "[Deploy] Deploying Curve Pool..."

POOL_DEPLOY_OUTPUT=$(forge script script/lp/curve/DeployPlainPool.s.sol:DeployPlainPool \
    --rpc-url $RPC_URL --broadcast \
    --private-key $DEPLOYER_PRIVATE_KEY \
    --sig "run(string)" \
    -- $POOL_CONFIG_FILE_NAME \
    -v 2>&1)

if [ $? -ne 0 ]; then
    echo "[Script] Error: Failed to deploy Curve pool"
    echo "$POOL_DEPLOY_OUTPUT"
    exit 1
fi

# Extract pool address from output
POOL_ADDRESS=$(echo "$POOL_DEPLOY_OUTPUT" | grep -o "Plain Pool deployed at: 0x[a-fA-F0-9]\{40\}" | grep -o "0x[a-fA-F0-9]\{40\}")

if [ -z "$POOL_ADDRESS" ]; then
    echo "[Script] Error: Could not extract pool address from deployment output"
    echo "$POOL_DEPLOY_OUTPUT"
    exit 1
fi

echo "[Deploy] Pool deployed at: $POOL_ADDRESS"

#-----------------------------------------------------------------------------------------------------
# STEP 3: DEPLOY GAUGE
#-----------------------------------------------------------------------------------------------------

echo "[Deploy] Deploying Gauge for Pool..."

GAUGE_DEPLOY_OUTPUT=$(forge script script/lp/curve/DeployGauge.s.sol:DeployGauge \
    --rpc-url $RPC_URL --broadcast \
    --private-key $DEPLOYER_PRIVATE_KEY \
    --sig "run(address,string)" \
    -- $POOL_ADDRESS $POOL_CONFIG_FILE_NAME \
    -v 2>&1)

if [ $? -ne 0 ]; then
    echo "[Script] Error: Failed to deploy gauge"
    echo "$GAUGE_DEPLOY_OUTPUT"
    exit 1
fi

# Extract gauge address from output
GAUGE_ADDRESS=$(echo "$GAUGE_DEPLOY_OUTPUT" | grep -o "Gauge deployed at: 0x[a-fA-F0-9]\{40\}" | grep -o "0x[a-fA-F0-9]\{40\}")

if [ -z "$GAUGE_ADDRESS" ]; then
    echo "[Script] Error: Could not extract gauge address from deployment output"
    echo "$GAUGE_DEPLOY_OUTPUT"
    exit 1
fi

echo "[Deploy] Gauge deployed at: $GAUGE_ADDRESS"

#-----------------------------------------------------------------------------------------------------
# STEP 4: ADD LIQUIDITY
#-----------------------------------------------------------------------------------------------------

echo "[Liquidity] Adding Liquidity to Pool..."

LIQUIDITY_OUTPUT=$(forge script script/lp/curve/tasks/AddLiquidity.s.sol:AddLiquidity \
    --rpc-url $RPC_URL --broadcast \
    --private-key $DEPLOYER_PRIVATE_KEY \
    --sig "run(address,address[],uint256[],bool)" \
    -- $POOL_ADDRESS $TOKEN_ADDRESSES $TOKEN_AMOUNTS $IS_METAPOOL \
    -v 2>&1)

if [ $? -ne 0 ]; then
    echo "[Script] Error: Failed to add liquidity"
    echo "$LIQUIDITY_OUTPUT"
    exit 1
fi

# Extract LP tokens received
LP_TOKENS=$(echo "$LIQUIDITY_OUTPUT" | grep -o "LP Tokens received: [0-9]\+" | grep -o "[0-9]\+")

echo "[Liquidity] LP Tokens received: $LP_TOKENS"

#-----------------------------------------------------------------------------------------------------
# SUMMARY
#-----------------------------------------------------------------------------------------------------

echo ""
echo "==============================================================================="
echo "LAUNCH COMPLETE"
echo "==============================================================================="
echo "Pool Address:  $POOL_ADDRESS"
echo "Gauge Address: $GAUGE_ADDRESS"
echo "Config File:   $POOL_CONFIG_FILE_NAME.json"
echo "Chain ID:      $CHAIN_ID"
echo "RPC URL:       $RPC_URL"
echo 
echo "Output files saved to:"
echo "- Pool:  $OUTPUT_FOLDER/${POOL_CONFIG_FILE_NAME}-result.json"
echo "- Gauge: $OUTPUT_FOLDER/${POOL_CONFIG_FILE_NAME}-gauge.json"
echo "==============================================================================="
