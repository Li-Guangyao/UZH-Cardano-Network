#!/usr/bin/env bash
# set -euo pipefail

TESTNET_MAGIC="--testnet-magic 42"
SOCKET_PATH="--socket-path ${CNODE_HOME}/sockets/node.socket"

UTXO_KEYS_PATH=~/keys/utxo-keys
POOL_KEYS_PATH=~/keys/pool-keys
TXS_PATH=~/txs

mkdir -p $TXS_PATH


# obtain the "protocol parameters":
cardano-cli query protocol-parameters \
    $SOCKET_PATH\
    $TESTNET_MAGIC\
    --out-file $CNODE_HOME/files/params.json

stakeAddressDeposit=$(jq -r '.stakeAddressDeposit' $CNODE_HOME/files/params.json)

# Create a certificate, stake.cert, using the stake.vkey:
cardano-cli conway stake-address registration-certificate \
    --stake-verification-key-file $UTXO_KEYS_PATH/stake.vkey \
    --key-reg-deposit-amt $stakeAddressDeposit \
    --out-file $UTXO_KEYS_PATH/stake.cert \
    2>&1 | grep -v "WARNING:"

# Find your balance and UTXOs (JSON 格式)
cardano-cli query utxo \
    --address $(cat $UTXO_KEYS_PATH/payment.addr) \
    $TESTNET_MAGIC $SOCKET_PATH \
    --out-file $TXS_PATH/utxo.json


# 用 jq 提取所有无 datum 的 UTXO
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
done < <(jq -c 'to_entries[]' $TXS_PATH/utxo.json)

txcnt=$(jq 'length' $TXS_PATH/utxo.json)
echo "Total available lovelace balance: ${total_balance}"
echo "Number of UTXOs: ${txcnt}"


# Find the amount of the deposit required to register a stake address:
stakeAddressDeposit=$(cat $CNODE_HOME/files/params.json | jq -r '.stakeAddressDeposit')
echo stakeAddressDeposit : $stakeAddressDeposit


# Run the build-raw transaction command:
#    --> The invalid-hereafter value must be greater than the current tip. In this example, we use current slot + 10000:
currentSlot=$(cardano-cli query tip  $TESTNET_MAGIC $SOCKET_PATH | jq -r '.slot')
echo Current Slot: $currentSlot


cardano-cli conway transaction build \
  ${tx_in} \
  --change-address $(cat $UTXO_KEYS_PATH/payment.addr) \
  --certificate-file $UTXO_KEYS_PATH/stake.cert \
   $TESTNET_MAGIC $SOCKET_PATH \
  --out-file $TXS_PATH/tx1.raw \
  2>&1 | grep -v "WARNING:"

# Sign the transaction with both the payment and stake secret keys:
cardano-cli conway transaction sign \
    --tx-body-file $TXS_PATH/tx1.raw \
    --signing-key-file $UTXO_KEYS_PATH/payment.skey \
    --signing-key-file $UTXO_KEYS_PATH/stake.skey \
     $TESTNET_MAGIC \
    --out-file $TXS_PATH/tx1.signed \
    2>&1 | grep -v "WARNING:"

# Send the signed transaction:
#    --> Output should be aas follows: "Transaction successfully submitted."
cardano-cli conway transaction submit \
    --tx-file $TXS_PATH/tx1.signed \
     $TESTNET_MAGIC $SOCKET_PATH \
     2>&1 | grep -v "WARNING:"