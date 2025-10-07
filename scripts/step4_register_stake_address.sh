#!/usr/bin/env bash

TESTNET_MAGIC="--testnet-magic 2025"
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


# Create a certificate, stake.cert, using the stake.vkey:
cardano-cli babbage stake-address registration-certificate \
    --stake-verification-key-file $UTXO_KEYS_PATH/stake.vkey \
    --out-file $UTXO_KEYS_PATH/stake.cert \
    2>&1 | grep -v "WARNING:"

# Find your balance and UTXOs.
#cd $TXS_PATH
cardano-cli query utxo --address $(cat $UTXO_KEYS_PATH/payment.addr) $TESTNET_MAGIC $SOCKET_PATH > $TXS_PATH/fullUtxo1.out
tail -n +3 $TXS_PATH/fullUtxo1.out | sort -k3 -nr > $TXS_PATH/balance1.out
#cat $TXS_PATH/balance1.out

tx_in=""
total_balance=0
while read -r utxo; do 
    type=$(awk '{ print $6 }' <<< "${utxo}") 
    if [[ ${type} == 'TxOutDatumNone' ]] 
    then 
        in_addr=$(awk '{ print $1 }' <<< "${utxo}") 
        idx=$(awk '{ print $2 }' <<< "${utxo}") 
        utxo_balance=$(awk '{ print $3 }' <<< "${utxo}") 
        total_balance=$((${total_balance}+${utxo_balance})) 
        echo TxHash: ${in_addr}#${idx} 
        echo lovelace: ${utxo_balance} 
        tx_in="${tx_in} --tx-in ${in_addr}#${idx}" 
    fi 
done < $TXS_PATH/balance1.out 

txcnt=$(cat $TXS_PATH/balance1.out | wc -l)
echo Total available lovelace balance: ${total_balance}
echo Number of UTXOs: ${txcnt}


# Find the amount of the deposit required to register a stake address:
stakeAddressDeposit=$(cat $CNODE_HOME/files/params.json | jq -r '.stakeAddressDeposit')
echo stakeAddressDeposit : $stakeAddressDeposit


# Run the build-raw transaction command:
#    --> The invalid-hereafter value must be greater than the current tip. In this example, we use current slot + 10000:
currentSlot=$(cardano-cli query tip  $TESTNET_MAGIC $SOCKET_PATH | jq -r '.slot')
echo Current Slot: $currentSlot


cardano-cli babbage transaction build \
  ${tx_in} \
  --change-address $(cat $UTXO_KEYS_PATH/payment.addr) \
  --certificate-file $UTXO_KEYS_PATH/stake.cert \
   $TESTNET_MAGIC $SOCKET_PATH \
  --out-file $TXS_PATH/tx1.raw \
  2>&1 | grep -v "WARNING:"

# Sign the transaction with both the payment and stake secret keys:
cardano-cli babbage transaction sign \
    --tx-body-file $TXS_PATH/tx1.raw \
    --signing-key-file $UTXO_KEYS_PATH/payment.skey \
    --signing-key-file $UTXO_KEYS_PATH/stake.skey \
     $TESTNET_MAGIC \
    --out-file $TXS_PATH/tx1.signed \
    2>&1 | grep -v "WARNING:"

# Send the signed transaction:
#    --> Output should be aas follows: "Transaction successfully submitted."
cardano-cli babbage transaction submit \
    --tx-file $TXS_PATH/tx1.signed \
     $TESTNET_MAGIC $SOCKET_PATH \
     2>&1 | grep -v "WARNING:"