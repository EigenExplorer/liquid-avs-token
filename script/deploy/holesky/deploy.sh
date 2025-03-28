#!/bin/bash

#-----------------------------------------------------------------------------------------------------
# README
#-----------------------------------------------------------------------------------------------------

# Instructions:
# To load env file: source .env
# To run this script (make sure terminal is at the root directory `/liquid-avs-token`):
#  1. chmod +x script/deploy/holesky/deploy.sh
#  2. script/deploy/holesky/deploy.sh
# If writing update to GH, when prompted for password, input your access token (not your GH pass)

#-----------------------------------------------------------------------------------------------------
# SETUP
#-----------------------------------------------------------------------------------------------------

# Check for required env vars
if [ -z "$DEPLOYER_PRIVATE_KEY" ]; then
    echo "[Deploy] Error: DEPLOYER_PRIVATE_KEY environment variable is not set"
    exit 0
fi

if [ -z "$RPC_URL" ]; then
    echo "[Deploy] Error: RPC_URL environment variable is not set"
    exit 0
fi

# Deployment info (edit this)
LAT_NAME="xeigenda"
DEPLOYMENT_NAME="v1"

# Configuration
CHAIN="holesky"
GITHUB_REPO="Eigenexplorer/lat-deployments"
GITHUB_BRANCH="dev"
DEPLOYMENT_CONFIG_FILE="${LAT_NAME}.anvil.config.json"
DEPLOYMENT_CONFIG_PATH="script/configs/$CHAIN/$DEPLOYMENT_CONFIG_FILE"
OUTPUT_PATH="script/outputs/$CHAIN/deployment_data.json"
ABI_PATH="script/outputs/$CHAIN/abi"

mkdir -p script/outputs/${CHAIN}
mkdir -p script/outputs/${CHAIN}/abi

#-----------------------------------------------------------------------------------------------------
# DEPLOY
#-----------------------------------------------------------------------------------------------------

echo "[Deploy] Deploying ${LAT_NAME} on ${CHAIN}..."

forge script --via-ir --optimize true script/deploy/$CHAIN/Deploy.s.sol:Deploy \
    --rpc-url $RPC_URL --broadcast \
    --verify --etherscan-api-key $ETHERSCAN_API_KEY \
    --private-key $DEPLOYER_PRIVATE_KEY \
    --sig "run(string)" \
    -- $DEPLOYMENT_CONFIG_FILE

#-----------------------------------------------------------------------------------------------------
# GITHUB INTEGRATION
#-----------------------------------------------------------------------------------------------------

# Check if GitHub token is available
if [ -z "$GITHUB_ACCESS_TOKEN" ]; then
    echo "[Deploy] Deployment complete. Github updation was disabled."
    exit 0
fi

if [ -z "$GITHUB_REPO" ]; then
    echo "[Deploy] Error: GITHUB_REPO environment variable is not set"
    exit 0
fi

echo "[Deploy] Writing deployment details to GitHub..."

# Clone repo
TEMP_DIR=$(mktemp -d)
git clone --depth 1 --branch $GITHUB_BRANCH "https://${GITHUB_ACCESS_TOKEN}@github.com/${GITHUB_REPO}.git" $TEMP_DIR
if [ $? -ne 0 ]; then
    echo "[Deploy] Error: Failed to clone repo"
    rm -rf $TEMP_DIR
    exit 1
fi

# Write config and output files
mkdir -p "$TEMP_DIR/$CHAIN/$LAT_NAME/$DEPLOYMENT_NAME"
mkdir -p "$TEMP_DIR/$CHAIN/$LAT_NAME/$DEPLOYMENT_NAME/abi"

if [ -f "$DEPLOYMENT_CONFIG_PATH" ]; then
    cp "$DEPLOYMENT_CONFIG_PATH" "$TEMP_DIR/$CHAIN/$LAT_NAME/$DEPLOYMENT_NAME/config.json"
else
    echo "[Deploy] Error: Config file not found at $DEPLOYMENT_CONFIG_FILE"
    rm -rf $TEMP_DIR
    exit 1
fi
if [ -f "$OUTPUT_PATH" ]; then
    cp $OUTPUT_PATH "$TEMP_DIR/$CHAIN/$LAT_NAME/$DEPLOYMENT_NAME/info.json"
else
    echo "[Deploy] Error: Output file not found at $OUTPUT_PATH"
    rm -rf $TEMP_DIR
    exit 1
fi
if [ -d "$ABI_PATH" ]; then
    cp $ABI_PATH/*.json "$TEMP_DIR/$CHAIN/$LAT_NAME/$DEPLOYMENT_NAME/abi/"
else
    echo "[Deploy] Error: ABI directory not found at $ABI_PATH"
    rm -rf $TEMP_DIR
    exit 1
fi

# Push to repo
cd $TEMP_DIR
git config user.name "Gowtham"
git config user.email "gowtham@eigenexplorer.com"
git add .
git commit -m "feat: new deployment $LAT_NAME/$DEPLOYMENT_NAME on $CHAIN"
git push

# Clean up
cd - > /dev/null
rm -rf $TEMP_DIR

echo "[Deploy] Deployment complete and $GITHUB_REPO repo updated."