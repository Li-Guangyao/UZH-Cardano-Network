#!/usr/bin/env bash
set -euo pipefail

TESTNET_MAGIC="--testnet-magic 42"
SOCKET_PATH="--socket-path ${CNODE_HOME}/sockets/node.socket"

UTXO_KEYS_PATH=~/keys/utxo-keys
POOL_KEYS_PATH=~/keys/pool-keys
TXS_PATH=~/txs
mkdir -p "$TXS_PATH"

# ---------- query stake address info ----------
stakePoolRewards=$(cardano-cli query stake-address-info \
    $TESTNET_MAGIC $SOCKET_PATH \
    --address "$(< $UTXO_KEYS_PATH/stake.addr)" \
    | jq -r '.[0].rewardAccountBalance // 0')
echo "stakePoolRewards: $stakePoolRewards"

if [[ "$stakePoolRewards" -eq 0 ]]; then
    echo "No rewards to withdraw."
    exit 0
fi

# ---------- query current slot ----------
currentSlot=$(cardano-cli query tip $TESTNET_MAGIC $SOCKET_PATH | jq -r '.slot')
echo "Current Slot: $currentSlot"

# ---------- query UTXO (JSON format) ----------
cardano-cli query utxo \
    --address "$(cat $UTXO_KEYS_PATH/payment.addr)" \
    $TESTNET_MAGIC $SOCKET_PATH \
    --out-file "$TXS_PATH/utxo3.json"

tx_in=""
total_balance=0
while IFS= read -r line; do
    utxo=$(echo "$line" | jq -r '.key')
    amount=$(echo "$line" | jq -r '.value.value.lovelace')
    has_datum=$(echo "$line" | jq -r '.value.datum // .value.inlineDatum // .value.datumhash // empty')

    if [[ -z "$has_datum" && "$amount" =~ ^[0-9]+$ ]]; then
        tx_in="${tx_in} --tx-in ${utxo}"
        total_balance=$((total_balance + amount))
    fi
done < <(jq -c 'to_entries[]' "$TXS_PATH/utxo3.json")

txcnt=$(jq 'length' "$TXS_PATH/utxo3.json")
echo "Total available lovelace balance: ${total_balance}"
echo "Number of UTXOs: ${txcnt}"

if [[ -z "$tx_in" ]]; then
    echo "Error: no spendable UTXO at payment address"
    exit 1
fi

# ---------- Build / Sign / Submit ----------
cardano-cli conway transaction build \
    $SOCKET_PATH \
    $TESTNET_MAGIC \
    $tx_in \
    --withdrawal "$(cat $UTXO_KEYS_PATH/stake.addr)+${stakePoolRewards}" \
    --change-address "$(cat $UTXO_KEYS_PATH/payment.addr)" \
    --witness-override 2 \
    --out-file "$TXS_PATH/tx3.raw" \
    2>&1 | grep -v "WARNING:" || true

cardano-cli conway transaction sign \
    --tx-body-file "$TXS_PATH/tx3.raw" \
    --signing-key-file "$UTXO_KEYS_PATH/payment.skey" \
    --signing-key-file "$UTXO_KEYS_PATH/stake.skey" \
    $TESTNET_MAGIC \
    --out-file "$TXS_PATH/tx3.signed" \
    2>&1 | grep -v "WARNING:" || true

TXID=$(cardano-cli conway transaction txid --tx-file "$TXS_PATH/tx3.signed")
echo "TxID: $TXID"

cardano-cli conway transaction submit \
    --tx-file "$TXS_PATH/tx3.signed" \
    $TESTNET_MAGIC $SOCKET_PATH \
    2>&1 | grep -v "WARNING:" || true

echo "Withdrawal submitted."