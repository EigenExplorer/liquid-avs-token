#!/bin/bash
# This script pushes deployment data to GitHub
GITHUB_TOKEN="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"
GITHUB_REPO="EigenExplorer/liquid-avs-token"
GITHUB_BRANCH="lat-deployments-test"
GITHUB_PATH="script/outputs/local/local_deployment_data.json"
DEPLOYMENT_DATA_PATH="script/outputs/local/local_deployment_data.json"

# Encode the content to base64
CONTENT=$(base64 -i $DEPLOYMENT_DATA_PATH)

# Create the request body
REQUEST_BODY="{\"message\":\"Update deployment data for local\",\"branch\":\"$GITHUB_BRANCH\",\"content\":\"$CONTENT\"}"

# Make the API call
curl -X PUT "https://api.github.com/repos/$GITHUB_REPO/contents/$GITHUB_PATH" -H "Authorization: token $GITHUB_TOKEN" -H "Accept: application/vnd.github.v3+json" -d "$REQUEST_BODY" --silent