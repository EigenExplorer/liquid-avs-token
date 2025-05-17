#!/bin/bash

#-----------------------------------------------------------------------------------------------------
# README
#-----------------------------------------------------------------------------------------------------

# Instructions:
# To setup a local node (on a separate terminal instance): anvil --fork-url $RPC_URL
# Edit the script where "User action" is marked
# To run this script (make sure terminal is at the root directory `/liquid-avs-token`):
#  1. chmod +x script/deploy/local/deploy.sh
#  2. script/deploy/local/deploy.sh
# If writing update to GH, when prompted for password, input your access token (not your GH password)

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

# User action (1/2): Edit deployment info
LAT_NAME="xeigenda"
DEPLOYMENT_NAME="v1"
CHAIN="holesky"

# User action (2/2): Copy relevant config file from `/configs/holesky` or `/configs/mainnet` folders into `/configs/local`
# Note: Make sure to update the `roles` object in the config according to the objectives
DEPLOYMENT_CONFIG_FILE="${LAT_NAME}.anvil.config.json"

# Configuration
DEPLOYER_PRIVATE_KEY="0x47e179ec197488593b187f80a00eb0da91f1b9d0b13f8733639f19c30a34926a"
GITHUB_REPO="Eigenexplorer/lat-deployments-test"
GITHUB_BRANCH="dev"
RPC_URL="http://127.0.0.1:8545"
NETWORK_CONFIG_FILE="${CHAIN}.json"
DEPLOYMENT_CONFIG_PATH="script/configs/local/$DEPLOYMENT_CONFIG_FILE"
OUTPUT_FOLDER_PATH="script/outputs/local"
OUTPUT_PATH="$OUTPUT_FOLDER_PATH/deployment_data.json"
ABI_PATH="$OUTPUT_FOLDER_PATH/abi"

# Create output directories
mkdir -p $OUTPUT_FOLDER_PATH
mkdir -p $ABI_PATH

# Get chain ID from RPC
CHAIN_ID=$(cast chain-id --rpc-url $RPC_URL)
echo "[Script] Chain ID: $CHAIN_ID"

#-----------------------------------------------------------------------------------------------------
# DEPLOY
#-----------------------------------------------------------------------------------------------------

echo "[Deploy] Deploying ${LAT_NAME} on ${CHAIN}..."

forge script --via-ir --optimize true script/deploy/local/Deploy.s.sol:Deploy \
    --rpc-url $RPC_URL --broadcast \
    --private-key $DEPLOYER_PRIVATE_KEY \
    --sig "run(string,string)" \
    -- $DEPLOYMENT_CONFIG_FILE $CHAIN

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

# Write abi files
echo "[Deploy] Copying specific contract ABIs from out folder..."

# Define the abi folders to copy from out folder
OUT_DIR="out"
CONTRACT_FOLDERS=(
    "LiquidToken.sol"
    "LiquidTokenManager.sol"
    "StakerNodeCoordinator.sol"
    "StakerNode.sol"
    "TokenRegistryOracle.sol"
)

# Copy each contract folder's ABI files to the ABI directory
for CONTRACT in "${CONTRACT_FOLDERS[@]}"; do
    CONTRACT_PATH="$OUT_DIR/$CONTRACT"
    
    if [ -d "$CONTRACT_PATH" ]; then
        echo "[Deploy] Copying ABIs from $CONTRACT_PATH"
        
        find "$CONTRACT_PATH" -name "*.json" -exec cp {} "$ABI_PATH/" \;
        find "$CONTRACT_PATH" -name "*.json" -exec cp {} "$TEMP_DIR/$CHAIN/$LAT_NAME/$DEPLOYMENT_NAME/abi/" \;
    else
        echo "[Deploy] Warning: Contract directory not found at $CONTRACT_PATH"
    fi
done

# Copy any existing ABI files (as a fallback)
if [ -d "$ABI_PATH" ] && [ "$(ls -A $ABI_PATH)" ]; then
    cp $ABI_PATH/*.json "$TEMP_DIR/$CHAIN/$LAT_NAME/$DEPLOYMENT_NAME/abi/" 2>/dev/null || true
    echo "[Deploy] Copied existing ABI files to GitHub repo"
else
    echo "[Deploy] Note: No existing ABI files found in $ABI_PATH"
fi

# Check if any ABI files were copied
if [ ! "$(ls -A $TEMP_DIR/$CHAIN/$LAT_NAME/$DEPLOYMENT_NAME/abi/)" ]; then
    echo "[Deploy] Warning: No ABI files were copied. The GitHub repo will not contain ABI files."
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