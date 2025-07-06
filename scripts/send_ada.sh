#!/usr/bin/env bash

# Check the number of input arguments
if [ "$#" -ne 2 ]; then
    echo "You must provide exactly two arguments: ./send_ada.sh <AMOUNT_IN_LOVELACE> <ADDRESS>"
    exit 1
fi

TESTNET_MAGIC="--testnet-magic 2025"
SOCKET_PATH="--socket-path ${CNODE_HOME}/sockets/node.socket"

set -euo pipefail


FAUCET_AMOUNT=$1
SEND_ADDR=$2

UTXO_KEYS_PATH=~/keys/utxo-keys
POOL_KEYS_PATH=~/keys/pool-keys
TXS_PATH=~/txs

mkdir -p $TXS_PATH

# Find your balance and UTXOs:
cardano-cli query utxo --address $(cat $UTXO_KEYS_PATH/payment.addr) $TESTNET_MAGIC $SOCKET_PATH  > $TXS_PATH/fullUtxo_faucet.out
tail -n +3 $TXS_PATH/fullUtxo_faucet.out | sort -k3 -nr > $TXS_PATH/balance_faucet.out
cat $TXS_PATH/balance_faucet.out

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
done < $TXS_PATH/balance_faucet.out 

txcnt=$(cat $TXS_PATH/balance_faucet.out | wc -l)
echo Total available ADA balance: ${total_balance}
echo Number of UTXOs: ${txcnt}


cardano-cli babbage transaction build \
    ${tx_in} \
    --tx-out $SEND_ADDR+$FAUCET_AMOUNT \
    --change-address $(cat $UTXO_KEYS_PATH/payment.addr) \
    $TESTNET_MAGIC \
    --out-file $TXS_PATH/tx_faucet.raw \
    2>&1 | grep -v "WARNING:"

cardano-cli babbage transaction sign \
    --tx-body-file $TXS_PATH/tx_faucet.raw \
    --out-file $TXS_PATH/tx_faucet.signed \
    --signing-key-file $UTXO_KEYS_PATH/payment.skey \
    2>&1 | grep -v "WARNING:"

cardano-cli babbage transaction txid --tx-file $TXS_PATH/tx_faucet.signed 2>&1 | grep -v "WARNING:"

cardano-cli babbage transaction submit --tx-file $TXS_PATH/tx_faucet.signed $TESTNET_MAGIC 2>&1 | grep -v "WARNING:"

rm $TXS_PATH/tx_faucet.raw
mv $TXS_PATH/tx_faucet.signed $TXS_PATH/tx_faucet.sent
