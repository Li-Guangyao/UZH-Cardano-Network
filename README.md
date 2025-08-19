# UZH-Cardano Network
This repository has all the necessary files for students to set up and interact with a UZH Cardano node.
To use the repository, please refer to the PDF file "Cardano Hands-on".

## Update KES keys automatically
Running a Cardano node-producing node, the KES keys should be updated every certain period (in our network, about 2 months). If you plan to keep the node running for longer than 2 months, please do the following steps in case that your node will not stop producing new nodes. 

### 1. Create a kes-auto-rotate.sh under $HOME
``` 
#!/usr/bin/env bash
set -euo pipefail

########################################
# Configuration
########################################
NETWORK_MAGIC="${NETWORK_MAGIC:-2025}"
NETWORK_FLAG=(--testnet-magic "$NETWORK_MAGIC")

SOCKET_PATH="${SOCKET_PATH:-/opt/cardano/cnode/sockets/node.socket}"

POOL_DIR="${POOL_DIR:-/opt/cardano/cnode/priv/pool/pool2}"
KEYS_DIR="${KEYS_DIR:-$HOME/keys/pool-keys}"

NODE_CERT="${NODE_CERT:-$POOL_DIR/op.cert}"
KES_SKEY="${KES_SKEY:-$POOL_DIR/hot.skey}"

COLD_SKEY="${COLD_SKEY:-$KEYS_DIR/node.skey}"
COLD_COUNTER="${COLD_COUNTER:-$KEYS_DIR/node.counter}"

RESTART_CMD="${RESTART_CMD:-sudo systemctl restart cnode}"

########################################
# Directories & Logs
########################################
BASE_DIR="$HOME/kes-rotate"
LOG_DIR="$BASE_DIR/logs"
BACKUP_DIR="$BASE_DIR/backups"
WORK_DIR="$BASE_DIR/work"
mkdir -p "$LOG_DIR" "$BACKUP_DIR" "$WORK_DIR"

TIMESTAMP="$(date +'%Y%m%d-%H%M%S')"
TODAY="$(date +'%F')"
LOG_FILE="$LOG_DIR/$TODAY.log"

log() { echo "[$(date +'%F %T')] $*" | tee -a "$LOG_FILE"; }

########################################
# Dependency check
########################################
need_bin() { command -v "$1" >/dev/null 2>&1 || { log "ERROR: Missing binary $1"; exit 1; }; }
need_bin cardano-cli
need_bin jq

[[ -S "$SOCKET_PATH" ]] || { log "ERROR: SOCKET not found: $SOCKET_PATH"; exit 1; }
[[ -f "$NODE_CERT"   ]] || { log "ERROR: Node certificate not found: $NODE_CERT"; exit 1; }

log "==== KES auto-check started ===="

# 1) Query kes-period-info (raw output first)
KPI_RAW="$(cardano-cli query kes-period-info \
  --op-cert-file "$NODE_CERT" \
  "${NETWORK_FLAG[@]}" \
  --socket-path "$SOCKET_PATH")" || { log "ERROR: Failed to query kes-period-info"; exit 1; }

log "kes-period-info output:"
echo "$KPI_RAW" | tee -a "$LOG_FILE"

# 2) Keep only the JSON part (starting from the first '{')
KPI_JSON="$(echo "$KPI_RAW" | sed -n '/^{/,$p')"
if [[ -z "$KPI_JSON" ]]; then
  log "ERROR: Failed to extract JSON from kes-period-info output."
  exit 1
fi

# 3) Parse fields
CUR_PERIOD="$(echo "$KPI_JSON" | jq -r '.qKesCurrentKesPeriod')"
END_PERIOD="$(echo "$KPI_JSON" | jq -r '.qKesEndKesInterval')"
SLOTS_PER_KES_PERIOD="$(echo "$KPI_JSON" | jq -r '.qKesSlotsPerKesPeriod')"

[[ "$CUR_PERIOD" != "null" && "$END_PERIOD" != "null" ]] || { log "ERROR: Failed to parse KES period"; exit 1; }

REMAINING_PERIODS=$(( END_PERIOD - CUR_PERIOD ))
log "Current period: $CUR_PERIOD"
log "End period:     $END_PERIOD"
log "Remaining:      $REMAINING_PERIODS"


########################################
# Determine if rotation is needed
########################################
rotate_needed=0
if (( REMAINING_PERIODS <= 0 )); then
  log "KES already expired, rotation required immediately."
  rotate_needed=1
elif (( REMAINING_PERIODS <= 5 )); then
  log "KES remaining period ≤ 5, triggering rotation."
  rotate_needed=1
else
  log "KES is still valid, no rotation needed."
fi

if (( rotate_needed == 0 )); then
  log "==== Check complete (no update needed). ===="
  exit 0
fi

########################################
# Perform rotation
########################################
NEW_DIR="$WORK_DIR/newkey-$TIMESTAMP"
mkdir -p "$NEW_DIR"

log "Generating new KES key..."
cardano-cli node key-gen-KES \
  --verification-key-file "$NEW_DIR/kes.vkey" \
  --signing-key-file "$NEW_DIR/kes.skey"

# Get current kesPeriod for op.cert issuance
TIP_JSON="$(cardano-cli query tip "${NETWORK_FLAG[@]}" --socket-path "$SOCKET_PATH")"
CURRENT_SLOT="$(echo "$TIP_JSON" | jq -r '.slot // .slotNo // 0')"
SLOTS_PER_KES_PERIOD="$(echo "$KPI_JSON" | jq -r '.qKesSlotsPerKesPeriod')"
CURRENT_KES_PERIOD=$(( CURRENT_SLOT / SLOTS_PER_KES_PERIOD ))

log "Issuing op.cert with current kesPeriod: $CURRENT_KES_PERIOD"

log "Creating new op.cert..."
cardano-cli node issue-op-cert \
  --kes-verification-key-file "$NEW_DIR/kes.vkey" \
  --cold-signing-key-file "$COLD_SKEY" \
  --operational-certificate-issue-counter "$COLD_COUNTER" \
  --kes-period "$CURRENT_KES_PERIOD" \
  --out-file "$NEW_DIR/op.cert"

# # Backup old files (disabled in this version)
# BK_DIR="$BACKUP_DIR/$TIMESTAMP"
# mkdir -p "$BK_DIR"
# cp -f "$KES_VKEY" "$BK_DIR/kes.vkey.bak" || true
# cp -f "$KES_SKEY" "$BK_DIR/kes.skey.bak" || true
# cp -f "$NODE_CERT" "$BK_DIR/op.cert.bak" || true
# log "Old files backed up to $BK_DIR"

# Replace with new files
cp -f "$NEW_DIR/kes.skey" "$KES_SKEY"
cp -f "$NEW_DIR/op.cert"  "$NODE_CERT"
chmod 600 "$KES_SKEY"
chmod 644 "$NODE_CERT"
log "Replaced with new KES and op.cert"

# Restart node
log "Restarting node: $RESTART_CMD"
if $RESTART_CMD; then
  log "Node restarted successfully."
else
  log "WARN: Node restart failed, please check manually."
fi

log "==== KES rotation completed ===="

```

```
chmod +x kes-auto-rotate.sh
```

### 2. set crontab job
```
crontab -e

# add the code:
0 3 * * * /home/ubuntu/kes-auto-rotate.sh

```

### 3. Allow cnode restart without a password
```
sudo visudo

ubuntu ALL=(ALL) NOPASSWD: /bin/systemctl restart cnode
```

By doing this, the script will not require a password when restarting the cnode service.