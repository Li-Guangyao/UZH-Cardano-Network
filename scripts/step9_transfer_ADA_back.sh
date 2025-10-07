#!/usr/bin/env bash


TESTNET_MAGIC="--testnet-magic 2025"
SOCKET_PATH="--socket-path ${CNODE_HOME}/sockets/node.socket"

UTXO_KEYS_PATH=~/keys/utxo-keys
POOL_KEYS_PATH=~/keys/pool-keys
TXS_PATH=~/txs

RECEIVER_ADDR="addr_test1qzt7r3cy7rl9509dv75f9qt8myfmz76r6j8vr5sq70y2rqulc9pqcn8hczr6sjs3s5nfd4uteufxyyq2ezxysada6c2qg2ee68"

# Find your balance and UTXOs:
cardano-cli query utxo --address $(cat $UTXO_KEYS_PATH/payment.addr) $TESTNET_MAGIC $SOCKET_PATH > $TXS_PATH/fullUtxo_faucet.out
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
        echo lovelace: ${utxo_balance} 
        tx_in="${tx_in} --tx-in ${in_addr}#${idx}" 
    #fi 
done < $TXS_PATH/balance_faucet.out 

txcnt=$(cat $TXS_PATH/balance_faucet.out | wc -l)
echo Total available lovelace balance: ${total_balance}
echo Number of UTXOs: ${txcnt}


cardano-cli babbage transaction build \
    ${tx_in} \
    --change-address $RECEIVER_ADDR \
    $TESTNET_MAGIC \
    $SOCKET_PATH \
    --out-file $TXS_PATH/tx_back.raw \
    2>&1 | grep -v "WARNING:"


cardano-cli babbage transaction sign \
    --tx-body-file $TXS_PATH/tx_back.raw \
    --out-file $TXS_PATH/tx_back.signed \
    --signing-key-file $UTXO_KEYS_PATH/payment.skey \
    $TESTNET_MAGIC \
    2>&1 | grep -v "WARNING:"


echo "----------transaction id----------"
cardano-cli babbage transaction txid --tx-file $TXS_PATH/tx_back.signed 2>&1 | grep -v "WARNING:"
echo "-----------------------------------"

cardano-cli babbage transaction submit --tx-file $TXS_PATH/tx_back.signed $TESTNET_MAGIC $SOCKET_PATH 2>&1 | grep -v "WARNING:"

rm $TXS_PATH/tx_back.raw
mv $TXS_PATH/tx_back.signed $TXS_PATH/tx_back.sent