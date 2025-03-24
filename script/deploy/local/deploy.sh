#!/bin/bash

#-----------------------------------------------------------------------------------------------------
# README
#-----------------------------------------------------------------------------------------------------

# Instructions:
# To load env file: source .env
# To setup a local node (on a separate terminal instance): anvil --fork-url $RPC_URL
# To run this script (make sure terminal is at the root directory `/liquid-avs-token`):
#  1. chmod +x script/deploy/local/deploy.sh
#  2. script/deploy/local/deploy.sh
# If writing update to GH, when prompted for password, input your access token (not your GH pass)

#-----------------------------------------------------------------------------------------------------
# SETUP
#-----------------------------------------------------------------------------------------------------

# Deployment info (edit this)
LAT_NAME="xeigenda"
DEPLOYMENT_NAME="v1"
CHAIN="holesky"

# Configuration
DEPLOYER_PRIVATE_KEY="${DEPLOYER_PRIVATE_KEY:-0x47e179ec197488593b187f80a00eb0da91f1b9d0b13f8733639f19c30a34926a}"
GITHUB_REPO="Eigenexplorer/lat-deployments-test"
GITHUB_BRANCH="dev"
RPC_URL="http://127.0.0.1:8545"
NETWORK_CONFIG_FILE="${CHAIN}.json"
DEPLOYMENT_CONFIG_FILE="${LAT_NAME}_${CHAIN}.anvil.config.json"
DEPLOYMENT_CONFIG_PATH="script/configs/local/$DEPLOYMENT_CONFIG_FILE"
OUTPUT_PATH="script/outputs/local/deployment_data.json"
ABI_PATH="script/outputs/local/abi"

mkdir -p script/outputs/local
mkdir -p script/outputs/local/abi

#-----------------------------------------------------------------------------------------------------
# DEPLOY
#-----------------------------------------------------------------------------------------------------

echo "[Deploy] Deploying ${LAT_NAME} on ${CHAIN}..."

forge script --via-ir --optimize true script/deploy/local/DeployHolesky.s.sol:DeployHolesky \
    --rpc-url $RPC_URL --broadcast \
    --private-key $DEPLOYER_PRIVATE_KEY \
    --sig "run(string,string)" \
    -- $NETWORK_CONFIG_FILE $DEPLOYMENT_CONFIG_FILE

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