#!/usr/bin/env bash
set -euo pipefail

# 用法：./send_ada.sh <ADDRESS> <AMOUNT_IN_LOVELACE>
if [ "$#" -ne 2 ]; then
    echo "Usage: ./send_ada.sh <ADDRESS> <AMOUNT_IN_LOVELACE>"
    echo "Example: ./send_ada.sh addr_test1qzyxs... 1000000000"
    exit 1
fi

SEND_ADDR=$1
FAUCET_AMOUNT=$2

if ! [[ "$FAUCET_AMOUNT" =~ ^[0-9]+$ ]]; then
    echo "Error: AMOUNT must be a positive integer (lovelace), got: $FAUCET_AMOUNT"
    exit 1
fi

if ! [[ "$SEND_ADDR" =~ ^addr(_test)?[0-9a-z]+$ ]]; then
    echo "Error: ADDRESS does not look like a bech32 Cardano address, got: $SEND_ADDR"
    exit 1
fi

if [[ -z "${CNODE_HOME:-}" ]]; then
    echo "Error: \$CNODE_HOME is not set"
    exit 1
fi

TESTNET_MAGIC="--testnet-magic 42"
SOCKET_PATH="--socket-path ${CNODE_HOME}/sockets/node.socket"

UTXO_KEYS_PATH=~/keys/utxo-keys
TXS_PATH=~/txs
mkdir -p "$TXS_PATH"

FROM_ADDR=$(cat "$UTXO_KEYS_PATH/payment.addr")
echo "From:   $FROM_ADDR"
echo "To:     $SEND_ADDR"
echo "Amount: $FAUCET_AMOUNT lovelace"

# ---------- 查询 UTXO ----------
cardano-cli query utxo \
    --address "$FROM_ADDR" \
    $TESTNET_MAGIC $SOCKET_PATH \
    --out-file "$TXS_PATH/utxo_faucet.json"

tx_in=""
total_balance=0
while IFS= read -r line; do
    utxo=$(echo "$line" | jq -r '.key')
    amount=$(echo "$line" | jq -r '.value.value.lovelace')
    is_special=$(echo "$line" | jq -r '
        (.value.datum // 
         .value.inlineDatum // 
         .value.inlineDatumRaw // 
         .value.datumhash // 
         .value.referenceScript // 
         empty)')
    
    if [[ -z "$is_special" && "$amount" =~ ^[0-9]+$ ]]; then
        tx_in="${tx_in} --tx-in ${utxo}"
        total_balance=$((total_balance + amount))
    fi
done < <(jq -c 'to_entries[]' "$TXS_PATH/utxo_faucet.json")

txcnt=$(jq 'length' "$TXS_PATH/utxo_faucet.json")
echo "Total available lovelace balance: $total_balance"
echo "Number of UTXOs: $txcnt"

if [[ -z "$tx_in" ]]; then
    echo "Error: no spendable (datum-less) UTXO found at $FROM_ADDR"
    exit 1
fi

if (( total_balance < FAUCET_AMOUNT )); then
    echo "Error: insufficient funds (have $total_balance, need $FAUCET_AMOUNT)"
    exit 1
fi

# ---------- Build ----------
cardano-cli conway transaction build \
    $tx_in \
    --tx-out "${SEND_ADDR}+${FAUCET_AMOUNT}" \
    --change-address "$FROM_ADDR" \
    $TESTNET_MAGIC $SOCKET_PATH \
    --out-file "$TXS_PATH/tx_faucet.raw" \
    2> >(grep -v "WARNING:" >&2)

[[ -s "$TXS_PATH/tx_faucet.raw" ]] || { echo "build failed"; exit 1; }

# ---------- Sign ----------
cardano-cli conway transaction sign \
    --tx-body-file "$TXS_PATH/tx_faucet.raw" \
    --signing-key-file "$UTXO_KEYS_PATH/payment.skey" \
    $TESTNET_MAGIC \
    --out-file "$TXS_PATH/tx_faucet.signed" \
    2> >(grep -v "WARNING:" >&2)

[[ -s "$TXS_PATH/tx_faucet.signed" ]] || { echo "sign failed"; exit 1; }

# ---------- TxID ----------
TXID=$(cardano-cli conway transaction txid \
    --tx-file "$TXS_PATH/tx_faucet.signed" \
    | jq -r '.txhash // .')
echo "TxID: $TXID"

# ---------- Submit ----------
cardano-cli conway transaction submit \
    --tx-file "$TXS_PATH/tx_faucet.signed" \
    $TESTNET_MAGIC $SOCKET_PATH \
    2> >(grep -v "WARNING:" >&2)

# ---------- 归档 ----------
rm -f "$TXS_PATH/tx_faucet.raw"
mv "$TXS_PATH/tx_faucet.signed" "$TXS_PATH/tx_faucet.${TXID}.sent"
echo "Done. Signed tx archived as tx_faucet.${TXID}.sent"