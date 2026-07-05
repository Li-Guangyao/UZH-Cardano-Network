#!/usr/bin/env bash

TESTNET_MAGIC="--testnet-magic 42"
SOCKET_PATH="--socket-path ${CNODE_HOME}/sockets/node.socket"

UTXO_KEYS_PATH=~/keys/utxo-keys
POOL_KEYS_PATH=~/keys/pool-keys
TXS_PATH=~/txs


# Blockchain must be synced
SYNC=$(cardano-cli query tip $TESTNET_MAGIC $SOCKET_PATH | jq -r '.syncProgress')

if [[ "$SYNC" != "100.00" ]]; then
    echo "syncProgress: $SYNC ... please wait for the node to sync and then try again."
    return 1 2>/dev/null || exit 1
fi

CURRENT_EPOCH=$(cardano-cli query tip $TESTNET_MAGIC $SOCKET_PATH | jq '.epoch')
echo current epoch: ${CURRENT_EPOCH}

poolRetireMaxEpoch=$(cat $CNODE_HOME/files//params.json | jq -r '.poolRetireMaxEpoch')
echo poolRetireMaxEpoch: ${poolRetireMaxEpoch}

minRetirementEpoch=$(( ${CURRENT_EPOCH} + 1 ))
maxRetirementEpoch=$(( ${CURRENT_EPOCH} + ${poolRetireMaxEpoch} ))

echo earliest epoch for retirement is: ${minRetirementEpoch}
echo latest epoch for retirement is: ${maxRetirementEpoch}



# Create a stake de-registration certificate:
cardano-cli conway stake-pool deregistration-certificate \
    --cold-verification-key-file $POOL_KEYS_PATH/node.vkey \
    --epoch $((${CURRENT_EPOCH} + 1)) \
    --out-file $TXS_PATH/pool.dereg \
    2>&1 | grep -v "WARNING:"


# ---------- 查询 UTXO（JSON 格式） ----------
cardano-cli query utxo \
    --address "$(cat $UTXO_KEYS_PATH/payment.addr)" \
    $TESTNET_MAGIC $SOCKET_PATH \
    --out-file "$TXS_PATH/utxo4.json"

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
done < <(jq -c 'to_entries[]' "$TXS_PATH/utxo4.json")

txcnt=$(jq 'length' "$TXS_PATH/utxo4.json")
echo "Total available lovelace balance: ${total_balance}"
echo "Number of UTXOs: ${txcnt}"



currentSlot=$(cardano-cli query tip $TESTNET_MAGIC  $SOCKET_PATH | jq -r '.slot')
echo Current Slot: $currentSlot


# Build the transaction:
cardano-cli conway transaction build \
    ${tx_in} \
    --change-address $(cat $UTXO_KEYS_PATH/payment.addr) \
    $TESTNET_MAGIC \
    $SOCKET_PATH \
    --invalid-hereafter $(( ${currentSlot} + 10000)) \
    --certificate-file $TXS_PATH/pool.dereg \
    --witness-override 2 \
    --out-file $TXS_PATH/tx4.raw \
    2>&1 | grep -v "WARNING:"


# Sign the transaction:
cardano-cli conway transaction sign \
    --tx-body-file $TXS_PATH/tx4.raw \
    --signing-key-file $UTXO_KEYS_PATH/payment.skey \
    --signing-key-file $POOL_KEYS_PATH/node.skey \
    $TESTNET_MAGIC  \
    --out-file $TXS_PATH/tx4.signed \
    2>&1 | grep -v "WARNING:"


echo "----------transaction id:----------"
cardano-cli conway transaction txid --tx-file $TXS_PATH/tx4.signed \
    2>&1 | grep -v "WARNING:"
echo "-----------------------------------"


# Send the transaction:
#    --> Output should be as follows: "Transaction successfully submitted."
cardano-cli conway transaction submit \
    --tx-file $TXS_PATH/tx4.signed $TESTNET_MAGIC $SOCKET_PATH \
    2>&1 | grep -v "WARNING:"
