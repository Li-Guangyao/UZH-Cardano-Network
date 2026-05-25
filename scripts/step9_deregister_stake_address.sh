#!/usr/bin/env bash
set -euo pipefail

TESTNET_MAGIC="--testnet-magic 42"
SOCKET_PATH="--socket-path ${CNODE_HOME}/sockets/node.socket"

UTXO_KEYS_PATH=~/keys/utxo-keys
POOL_KEYS_PATH=~/keys/pool-keys
TXS_PATH=~/txs
mkdir -p "$TXS_PATH"

PAYMENT_ADDR=$(cat "$UTXO_KEYS_PATH/payment.addr")
STAKE_ADDR=$(cat "$UTXO_KEYS_PATH/stake.addr")

# ---------- sync check ----------
SYNC=$(cardano-cli query tip $TESTNET_MAGIC $SOCKET_PATH | jq -r '.syncProgress')
if [[ "$SYNC" != "100.00" ]]; then
    echo "syncProgress: $SYNC ... please wait for sync."
    exit 1
fi

# ---------- query stake address status：registered？rewards？how much deposit？ ----------
stake_info=$(cardano-cli query stake-address-info \
    --address "$STAKE_ADDR" \
    $TESTNET_MAGIC $SOCKET_PATH)

if [[ "$(echo "$stake_info" | jq 'length')" == "0" ]]; then
    echo "Error: stake address is not registered (or already deregistered)."
    exit 1
fi

REWARDS=$(echo "$stake_info" | jq -r '.[0].rewardAccountBalance // 0')
echo "Reward balance: $REWARDS lovelace"

# dereg 时退回的押金必须等于注册时的金额
# 优先读 ledger 实际记录值，否则 fallback 到当前 protocol params
DEPOSIT=$(echo "$stake_info" | jq -r '.[0].deposit // empty')
if [[ -z "$DEPOSIT" || "$DEPOSIT" == "null" ]]; then
    cardano-cli query protocol-parameters \
        $TESTNET_MAGIC $SOCKET_PATH \
        --out-file "$CNODE_HOME/files/params.json"
    DEPOSIT=$(jq -r '.stakeAddressDeposit' "$CNODE_HOME/files/params.json")
fi
echo "Stake address deposit to refund: $DEPOSIT lovelace"

# ---------- generate deregistration certificate ----------
cardano-cli conway stake-address deregistration-certificate \
    --stake-verification-key-file "$UTXO_KEYS_PATH/stake.vkey" \
    --key-reg-deposit-amt "$DEPOSIT" \
    --out-file "$UTXO_KEYS_PATH/stake.dereg" \
    2>&1 | grep -v "WARNING:" || true

# ---------- query UTXO ----------
cardano-cli query utxo \
    --address "$PAYMENT_ADDR" \
    $TESTNET_MAGIC $SOCKET_PATH \
    --out-file "$TXS_PATH/utxo5.json"

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
done < <(jq -c 'to_entries[]' "$TXS_PATH/utxo5.json")

txcnt=$(jq 'length' "$TXS_PATH/utxo5.json")
echo "Total UTXO balance: $total_balance lovelace"
echo "Number of UTXOs: $txcnt"

if [[ -z "$tx_in" ]]; then
    echo "Error: no spendable UTXO at $PAYMENT_ADDR"
    exit 1
fi

# ---------- construct build arguments: add --withdrawal only if rewards exist ----------
build_args=(
    $tx_in
    --change-address "$PAYMENT_ADDR"
    $TESTNET_MAGIC
    $SOCKET_PATH
    --certificate-file "$UTXO_KEYS_PATH/stake.dereg"
    --witness-override 2
    --out-file "$TXS_PATH/tx5.raw"
)

if [[ "$REWARDS" =~ ^[0-9]+$ && "$REWARDS" -gt 0 ]]; then
    echo "Withdrawing $REWARDS lovelace of rewards in the same tx."
    build_args+=(--withdrawal "${STAKE_ADDR}+${REWARDS}")
fi

cardano-cli conway transaction build "${build_args[@]}" \
    2>&1 | grep -v "WARNING:" || true

# ---------- Sign ----------
cardano-cli conway transaction sign \
    --tx-body-file "$TXS_PATH/tx5.raw" \
    --signing-key-file "$UTXO_KEYS_PATH/payment.skey" \
    --signing-key-file "$UTXO_KEYS_PATH/stake.skey" \
    $TESTNET_MAGIC \
    --out-file "$TXS_PATH/tx5.signed" \
    2>&1 | grep -v "WARNING:" || true

echo "----------transaction id----------"
cardano-cli conway transaction txid --tx-file "$TXS_PATH/tx5.signed" \
    | jq -r '.txhash // .'
echo "----------------------------------"

# ---------- Submit ----------
cardano-cli conway transaction submit \
    --tx-file "$TXS_PATH/tx5.signed" \
    $TESTNET_MAGIC $SOCKET_PATH \
    2>&1 | grep -v "WARNING:" || true