#!/bin/bash

# === Config ===
BASE_API_ENDPOINT="http://130.60.24.200:81"
API_ENDPOINT="$BASE_API_ENDPOINT/upload"
NETWORK_DIR=~/UZH-Cardano-Network
SCRIPT_FILE="$NETWORK_DIR/scripts/step5_register_stake_pool.sh"
METADATA_FILE="$NETWORK_DIR/md.json"
URL_OUTPUT_FILE="$NETWORK_DIR/metadataurl.txt"

# === Input & Validation ===

while true; do
    read -p "Enter pool name ( <50 chars), e.g., Tom staking pool: " NAME
    if [[ ${#NAME} -le 50 ]]; then
        break
    else
        echo "Name too long. Please enter a name with less than 50 characters."
    fi
done

while true; do
    read -p "Enter description ( ≤255 chars), e.g., This pool has a low margin cost!: " DESCRIPTION
    if [[ ${#DESCRIPTION} -le 255 ]]; then
        break
    else
        echo "Description too long. Please enter a description with 255 characters or fewer."
    fi
done

while true; do
    read -p "Enter ticker (3-9 UPPERCASE letters or digits), e.g., TOMPOOL: " TICKER
    if [[ $TICKER =~ ^[A-Z0-9]{3,9}$ ]]; then
        break
    else
        echo "Invalid ticker format. Please use 3-9 uppercase letters or digits."
    fi
done

while true; do
    read -p "Enter homepage (must start with https, press Enter for default https://www.blockchain.uzh.ch): " HOMEPAGE
    # Set default homepage if empty
    if [[ -z "$HOMEPAGE" ]]; then
        HOMEPAGE="https://www.blockchain.uzh.ch"
    fi
    # Remove leading/trailing spaces from HOMEPAGE
    HOMEPAGE="$(echo "$HOMEPAGE" | xargs)"
    if [[ $HOMEPAGE =~ ^https://.*$ ]]; then
        break
    else
        echo "Homepage input invalid. Must start with https://"
    fi
done

# === Create JSON ===
mkdir -p "$NETWORK_DIR"
cat > "$METADATA_FILE" <<EOF
{
  "name": "$NAME",
  "description": "$DESCRIPTION",
  "ticker": "$TICKER",
  "homepage": "$HOMEPAGE"
}
EOF
echo "Metadata JSON created at $METADATA_FILE"

# === Upload JSON ===
echo "Uploading metadata file..."
RESPONSE=$(curl -s -F "file=@$METADATA_FILE" "$API_ENDPOINT")
URL=$(echo "$RESPONSE" | jq -r '.url')

if [[ "$URL" == "null" || -z "$URL" ]]; then
    echo "Upload failed. Response: $RESPONSE"
    exit 1
fi

FULL_URL="$BASE_API_ENDPOINT$URL"
echo "Metadata URL: $FULL_URL"

# === Save URL ===
echo "$FULL_URL" > "$URL_OUTPUT_FILE"
echo "Saved to $URL_OUTPUT_FILE"

# === Update stake pool script ===
if [[ -f "$SCRIPT_FILE" ]]; then
    sed -i -E "s|--metadata-url[[:space:]]+[^[:space:]]+|--metadata-url $FULL_URL|g" "$SCRIPT_FILE"
    echo "Updated metadata URL in $SCRIPT_FILE"
else
    echo "stake-pool script not found at $SCRIPT_FILE"
    exit 1
fi
