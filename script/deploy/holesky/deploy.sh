#!/bin/bash

#-----------------------------------------------------------------------------------------------------
# README
#-----------------------------------------------------------------------------------------------------

# Instructions:
# To load env file: source .env
# To run this script (make sure terminal is at the root directory `/liquid-avs-token`):
#  1. chmod +x script/deploy/holesky/deploy.sh
#  2. script/deploy/holesky/deploy.sh

#-----------------------------------------------------------------------------------------------------
# SETUP
#-----------------------------------------------------------------------------------------------------

# Check for deployer private key
if [ -z "$DEPLOYER_PRIVATE_KEY" ]; then
    echo "DEPLOYER_PRIVATE_KEY environment variable is not set."
    exit 0
fi

if [ -z "$RPC_URL" ]; then
    echo "RPC_URL environment variable is not set."
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
OUTPUT_PATH="script/outputs/${CHAIN}/deployment_data.json"

mkdir -p script/outputs/${CHAIN}

#-----------------------------------------------------------------------------------------------------
# DEPLOY
#-----------------------------------------------------------------------------------------------------

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
    cp "script/configs/$CHAIN/$DEPLOYMENT_CONFIG_FILE" "$TEMP_DIR/$CHAIN/$LAT_NAME/$DEPLOYMENT_NAME/config.json"
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