#!/usr/bin/env bash

TESTNET_MAGIC="--testnet-magic 2025"
SOCKET_PATH="--socket-path ${CNODE_HOME}/sockets/node.socket"

#PAYMENT_KEY_PREFIX=~/keys/utxo-keys/payment
UTXO_KEYS_PATH=~/keys/utxo-keys
POOL_KEYS_PATH=~/keys/pool-keys
TXS_PATH=~/txs

stakePoolRewards="$(cardano-cli conway query stake-address-info $TESTNET_MAGIC --address $(< $UTXO_KEYS_PATH/stake.addr) | jq .[].rewardAccountBalance)"
echo stakePoolRewards: $stakePoolRewards


# Find the tip of the blockchain to set the invalid-hereafter parameter properly:
currentSlot=$(cardano-cli query tip $TESTNET_MAGIC  | jq -r '.slot')
echo Current Slot: $currentSlot


# Find your balance and UTXOs:
cardano-cli query utxo --address $(cat $UTXO_KEYS_PATH/payment.addr) $TESTNET_MAGIC  > $TXS_PATH/fullUtxo3.out
tail -n +3 $TXS_PATH/fullUtxo3.out | sort -k3 -nr > $TXS_PATH/balance3.out
cat $TXS_PATH/balance3.out
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
        echo ADA: ${utxo_balance} 
        tx_in="${tx_in} --tx-in ${in_addr}#${idx}" 
    fi 
done < $TXS_PATH/balance3.out 

txcnt=$(cat $TXS_PATH/balance3.out | wc -l)
echo Total available ADA balance: ${total_balance}
echo Number of UTXOs: ${txcnt}


cardano-cli babbage transaction build \
    $SOCKET_PATH \
    $TESTNET_MAGIC  \
    ${tx_in} \
    --withdrawal $(cat $UTXO_KEYS_PATH/stake.addr)+${stakePoolRewards} \
    --change-address $(cat $UTXO_KEYS_PATH/payment.addr) \
    --witness-override 2 \
    --out-file $TXS_PATH/tx3.raw \
    2>&1 | grep -v "WARNING:"


# Sign the transaction:
cardano-cli babbage transaction sign \
    --tx-body-file $TXS_PATH/tx3.raw \
    --signing-key-file $UTXO_KEYS_PATH/payment.skey \
    --signing-key-file $UTXO_KEYS_PATH/stake.skey \
    $TESTNET_MAGIC \
    --out-file $TXS_PATH/tx3.signed \
    2>&1 | grep -v "WARNING:"



# Send the transaction:
#    --> Output should be aas follows: "Transaction successfully submitted."
cardano-cli babbage transaction submit \
    --tx-file $TXS_PATH/tx3.signed \
    $TESTNET_MAGIC \
    $SOCKET_PATH \
    2>&1 | grep -v "WARNING:"