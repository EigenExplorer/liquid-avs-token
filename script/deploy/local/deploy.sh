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

#-----------------------------------------------------------------------------------------------------
# SETUP
#-----------------------------------------------------------------------------------------------------

# Check for deployer private key
if [ -z "$DEPLOYER_PRIVATE_KEY" ]; then
    echo "DEPLOYER_PRIVATE_KEY environment variable is not set."
    exit 0
fi

# Deployment info (edit this)
LAT_NAME="xeigenda"
DEPLOYMENT_NAME="v1"
CHAIN="holesky"

# Configuration
GITHUB_REPO="Eigenexplorer/lat-deployments-test"
GITHUB_BRANCH="dev"
RPC_URL="http://127.0.0.1:8545"
NETWORK_CONFIG_FILE="${CHAIN}.json"
DEPLOYMENT_CONFIG_FILE="${LAT_NAME}_${CHAIN}.anvil.config.json"
OUTPUT_PATH="script/outputs/local/${CHAIN}_deployment_data.json"

mkdir -p script/outputs/local

#-----------------------------------------------------------------------------------------------------
# DEPLOY
#-----------------------------------------------------------------------------------------------------

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
    echo "Github update disabled"
    echo "Deployment complete"
    exit 0
fi

# Clone repo
TEMP_DIR=$(mktemp -d)
git clone --depth 1 --branch $GITHUB_BRANCH "https://${GITHUB_ACCESS_TOKEN}@github.com/${GITHUB_REPO}.git" $TEMP_DIR
if [ $? -ne 0 ]; then
    echo "Error: Failed to clone repo"
    rm -rf $TEMP_DIR
    exit 1
fi

# Write config and output files
mkdir -p "$TEMP_DIR/$CHAIN/$LAT_NAME/$DEPLOYMENT_NAME"
if [ -f "$DEPLOYMENT_CONFIG_FILE" ]; then
    cp "script/configs/local/$DEPLOYMENT_CONFIG_FILE" "$TEMP_DIR/$CHAIN/$LAT_NAME/$DEPLOYMENT_NAME/config.json"
else
    echo "Error: Config file not found at $DEPLOYMENT_CONFIG_FILE"
    rm -rf $TEMP_DIR
    exit 1
fi
if [ -f "$OUTPUT_PATH" ]; then
    cp $OUTPUT_PATH "$TEMP_DIR/$CHAIN/$LAT_NAME/$DEPLOYMENT_NAME/output.json"
else
    echo "Error: Output file not found at $OUTPUT_PATH"
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

echo "Deployment complete and $GITHUB_REPO repo updated"