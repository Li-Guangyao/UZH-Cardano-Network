#!/usr/bin/env bash

TESTNET_MAGIC="--testnet-magic 2025"
SOCKET_PATH="--socket-path ${CNODE_HOME}/sockets/node.socket"


UTXO_KEYS_PATH=~/keys/utxo-keys
POOL_KEYS_PATH=~/keys/pool-keys
TXS_PATH=~/txs


# Blochchain must be synced !
SYNC=$(cardano-cli query tip $TESTNET_MAGIC | jq '.syncProgress')

if [ $SYNC != "\"100.00\"" ]; then
    echo -e "\nsyncProgress: $SYNC ... please wait for the node to sync and then try again.\n"
    return 1
fi


cardano-cli babbage stake-address deregistration-certificate \
    --stake-verification-key-file $UTXO_KEYS_PATH/stake.vkey \
    --out-file $TXS_PATH/stake.dereg \
    2>&1 | grep -v "WARNING:"


# Find your balance and UTXOs:
cardano-cli query utxo --address $(cat $UTXO_KEYS_PATH/payment.addr) $TESTNET_MAGIC $SOCKET_PATH > $TXS_PATH/fullUtxo5.out
tail -n +3 $TXS_PATH/fullUtxo5.out | sort -k3 -nr > $TXS_PATH/balance5.out
#cat $TXS_PATH/balance5.out


tx_in=""
total_balance=0
while read -r utxo; do 
    #type=$(awk '{ print $6 }' <<< "${utxo}") 
    #if [[ ${type} == 'TxOutDatumNone' ]] 
    #then 
        in_addr=$(awk '{ print $1 }' <<< "${utxo}") 
        idx=$(awk '{ print $2 }' <<< "${utxo}") 
        utxo_balance=$(awk '{ print $3 }' <<< "${utxo}") 
        total_balance=$((${total_balance}+${utxo_balance})) 
        echo TxHash: ${in_addr}#${idx} 
        echo ADA: ${utxo_balance} 
        tx_in="${tx_in} --tx-in ${in_addr}#${idx}" 
    #fi 
done < $TXS_PATH/balance5.out 


# txcnt=$(cat $TXS_PATH/balance5.out | wc -l)
# echo Total available ADA balance: ${total_balance}
# echo Number of UTXOs: ${txcnt}

stakePoolRewards=$(cardano-cli query stake-address-info $TESTNET_MAGIC $SOCKET_PATH --address $(cat $UTXO_KEYS_PATH/stake.addr) | jq -r '.[0].rewardAccountBalance')
echo stakePoolRewards: $stakePoolRewards

# currentSlot=$(cardano-cli query tip $TESTNET_MAGIC | jq -r '.slot')
# echo Current Slot: $currentSlot

# keyDeposit=$(cardano-cli query protocol-parameters   --cardano-mode   $TESTNET_MAGIC | jq '.stakeAddressDeposit')
# echo key deposit: $keyDeposit


# Build the transaction:
cardano-cli babbage transaction build \
    ${tx_in} \
    --change-address $(cat $UTXO_KEYS_PATH/payment.addr) \
    $TESTNET_MAGIC \
    $SOCKET_PATH \
    --withdrawal $(cat $UTXO_KEYS_PATH/stake.addr)+${stakePoolRewards} \
    --certificate-file $TXS_PATH/stake.dereg \
    --witness-override 2 \
    --out-file $TXS_PATH/tx5.raw \
    2>&1 | grep -v "WARNING:"


# Sign the transaction:
cardano-cli babbage transaction sign \
    --tx-body-file $TXS_PATH/tx5.raw \
    --signing-key-file $UTXO_KEYS_PATH/payment.skey \
    --signing-key-file $UTXO_KEYS_PATH/stake.skey \
    $TESTNET_MAGIC \
    --out-file $TXS_PATH/tx5.signed \
    2>&1 | grep -v "WARNING:"


echo "----------transaction id----------"
cardano-cli babbage transaction txid --tx-file $TXS_PATH/tx5.signed 2>&1 | grep -v "WARNING:"
echo "-----------------------------------"


# Send the transaction:
#    --> Output should be as follows: "Transaction successfully submitted."
cardano-cli babbage transaction submit --tx-file $TXS_PATH/tx5.signed $TESTNET_MAGIC $SOCKET_PATH \
    2>&1 | grep -v "WARNING:"