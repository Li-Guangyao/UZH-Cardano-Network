#!/usr/bin/env bash
set -euo pipefail

# 用法：./send_all_ada.sh <RECEIVER_ADDRESS>
if [ "$#" -ne 1 ]; then
    echo "Usage: ./send_all_ada.sh <RECEIVER_ADDRESS>"
    exit 1
fi

RECEIVER_ADDR=$1

# 基本地址格式校验
if ! [[ "$RECEIVER_ADDR" =~ ^addr(_test)?[0-9a-z]+$ ]]; then
    echo "Error: invalid Cardano address: $RECEIVER_ADDR"
    exit 1
fi

# 环境检查
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
echo "To:     $RECEIVER_ADDR (all funds)"

# ---------- 查询 UTXO（JSON 格式） ----------
cardano-cli query utxo \
    --address "$FROM_ADDR" \
    $TESTNET_MAGIC $SOCKET_PATH \
    --out-file "$TXS_PATH/utxo_back.json"

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
done < <(jq -c 'to_entries[]' "$TXS_PATH/utxo_back.json")

txcnt=$(jq 'length' "$TXS_PATH/utxo_back.json")
echo "Total available lovelace balance: $total_balance"
echo "Number of UTXOs: $txcnt"

if [[ -z "$tx_in" ]]; then
    echo "Error: no spendable UTXO at $FROM_ADDR"
    exit 1
fi

# ---------- Build ----------
# 不指定 --tx-out，把所有 change 给 RECEIVER，等于"扣掉 fee 后全转给对方"
cardano-cli conway transaction build \
    $tx_in \
    --change-address "$RECEIVER_ADDR" \
    $TESTNET_MAGIC $SOCKET_PATH \
    --out-file "$TXS_PATH/tx_back.raw" \
    2> >(grep -v "WARNING:" >&2)

[[ -s "$TXS_PATH/tx_back.raw" ]] || { echo "build failed"; exit 1; }

# ---------- Sign ----------
cardano-cli conway transaction sign \
    --tx-body-file "$TXS_PATH/tx_back.raw" \
    --signing-key-file "$UTXO_KEYS_PATH/payment.skey" \
    $TESTNET_MAGIC \
    --out-file "$TXS_PATH/tx_back.signed" \
    2> >(grep -v "WARNING:" >&2)

[[ -s "$TXS_PATH/tx_back.signed" ]] || { echo "sign failed"; exit 1; }

# ---------- TxID ----------
TXID=$(cardano-cli conway transaction txid \
    --tx-file "$TXS_PATH/tx_back.signed" \
    | jq -r '.txhash // .')
echo "----------transaction id----------"
echo "$TXID"
echo "----------------------------------"

# ---------- Submit ----------
cardano-cli conway transaction submit \
    --tx-file "$TXS_PATH/tx_back.signed" \
    $TESTNET_MAGIC $SOCKET_PATH \
    2> >(grep -v "WARNING:" >&2)

# ---------- 归档 ----------
rm -f "$TXS_PATH/tx_back.raw"
mv "$TXS_PATH/tx_back.signed" "$TXS_PATH/tx_back.${TXID}.sent"
echo "Done. Signed tx archived as tx_back.${TXID}.sent"