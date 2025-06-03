#!/bin/bash

# === Config ===
BASE_API_ENDPOINT="http://http://130.60.24.200:81"
API_ENDPOINT="$BASE_API_ENDPOINT/upload"
NETWORK_DIR=~/UZH-Cardano-Network
SCRIPT_FILE="$NETWORK_DIR/scripts/step5_register_stake_pool.sh"
METADATA_FILE="$NETWORK_DIR/md.json"
URL_OUTPUT_FILE="$NETWORK_DIR/metadataurl.txt"

# === Input ===
read -p "Enter pool name ( <50 chars), e.g., Tom's staking pool: " NAME
read -p "Enter description ( ≤255 chars), e.g., This pool has a low margin cost!: " DESCRIPTION
read -p "Enter ticker (3-9 UPPERCASE letters or digits), e.g., TOM: " TICKER
read -p "Enter homepage (must start with https), e.g., https://www.blockchain.uzh.ch/: " HOMEPAGE

# === Validation ===
[[ ${#NAME} -gt 50 ]] && echo "Name too long." && exit 1
[[ ${#DESCRIPTION} -gt 255 ]] && echo "Description too long." && exit 1
[[ ! $TICKER =~ ^[A-Z0-9]{3,9}$ ]] && echo "Invalid ticker format." && exit 1
[[ ! $HOMEPAGE =~ ^https://.*$ ]] && echo "Homepage must start with https." && exit 1

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
