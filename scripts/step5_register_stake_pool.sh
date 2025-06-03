#!/usr/bin/env bash

echo "Registering a stake pool on the Cardano testnet..."
echo "Now, you need to input 3 parameters of your pool: pool pledge, pool cost, and pool margin."
echo "--------------------------------------------------------"

# Get Pool pledge
while true; do
  read -p "Please input pool pledge (The unit is lovelace. This number must be a integer >= 0), e.g., 100000000000: " POOL_PLEDGE
  if [[ "$POOL_PLEDGE" =~ ^[0-9]+$ ]] && [ "$POOL_PLEDGE" -ge 0 ]; then
    break
else
    echo "Invalid input: pool pledge must be an integer greater than or equal to 0, please re-enter."
  fi
done

# Get pool-cost
while true; do
    read -p "Please input pool cost (The unit is lovelace. The number must be an integer >= 340,000,000), e.g., 345000000: " POOL_COST
    if [[ "$POOL_COST" =~ ^[0-9]+$ ]] && [ "$POOL_COST" -ge 340000000 ]; then
        break
    else
        echo "Invalid input: pool cost must be an integer greater than or equal to 340,000,000, please re-enter."
    fi
done

# Get pool-margin
while true; do
    read -p "Please input pool margin (must be a number >= 0 and < 1, e.g., 0.15): " POOL_MARGIN
    if [[ "$POOL_MARGIN" =~ ^[0-9]+(\.[0-9]+)?$ ]] && \
         (( $(echo "$POOL_MARGIN >= 0" | bc -l) )) && \
         (( $(echo "$POOL_MARGIN < 1" | bc -l) )); then
        break
    else
        echo "Invalid input: pool margin must be a number greater than or equal to 0 and less than 1, please re-enter."
    fi
done

# Final output
echo " Parameter input completed:"
echo " pool-pledge = $POOL_PLEDGE"
echo " pool-cost   = $POOL_COST"
echo " pool-margin = $POOL_MARGIN"


TESTNET_MAGIC="--testnet-magic 2025"
SOCKET_PATH="--socket-path ${CNODE_HOME}/sockets/node.socket"

UTXO_KEYS_PATH=~/keys/utxo-keys
POOL_KEYS_PATH=~/keys/pool-keys
TXS_PATH=~/txs

# rm ~/UZH-Cardano-Network/poolMetaDataHash.txt

# Find the minimum pool cost --> (minPoolCost: 340000000):
minPoolCost=$(cat $CNODE_HOME/files/params.json | jq -r .minPoolCost)
echo minPoolCost: ${minPoolCost}


# Generate the Pool Metadata hash:
cardano-cli babbage stake-pool metadata-hash --pool-metadata-file ~/UZH-Cardano-Network/md.json > ~/UZH-Cardano-Network/poolMetaDataHash.txt


# Create a "registration certificate" for the stake pool:
#    --> Here we are pledging 1000000 ADA with a fixed pool cost of 345 ADA and a pool margin of 15%.
cardano-cli babbage stake-pool registration-certificate \
    --cold-verification-key-file $POOL_KEYS_PATH/node.vkey \
    --vrf-verification-key-file $POOL_KEYS_PATH/vrf.vkey \
    --pool-pledge $POOL_PLEDGE \
    --pool-cost $POOL_COST \
    --pool-margin $POOL_MARGIN \
    --pool-reward-account-verification-key-file $UTXO_KEYS_PATH/stake.vkey \
    --pool-owner-stake-verification-key-file $UTXO_KEYS_PATH/stake.vkey \
    $TESTNET_MAGIC \
    --single-host-pool-relay 130.60.24.200 \
    --pool-relay-port 6000 \
    --metadata-url ~/UZH-Cardano-Network/md.json \
    --metadata-hash $(cat ~/UZH-Cardano-Network/poolMetaDataHash.txt) \
    --out-file $POOL_KEYS_PATH/pool.cert \
    2>&1 | grep -v "WARNING:"


# 16.5. Pledge stake to your stake pool:
#    --> This operation creates a delegation certificate which "delegates" funds from all stake addresses associated with key stake.vkey to the pool belonging to cold key node.vkey.    
#    --> A stake pool owner`s promise to fund their own pool is called Pledge.
#        --> Your balance needs to be greater than the pledge amount.
#        --> You pledge funds are not moved anywhere. In this guide example, the pledge remains in the stake pool owner`s keys, specifically payment.addr
#        --> Failing to fulfill pledge will result in missed block minting opportunities and your delegators would miss rewards.
#        --> Your pledge is not locked up. You are free to transfer your funds.
cardano-cli babbage stake-address stake-delegation-certificate \
    --stake-verification-key-file $UTXO_KEYS_PATH/stake.vkey \
    --cold-verification-key-file $POOL_KEYS_PATH/node.vkey \
    --out-file $POOL_KEYS_PATH/delegation.cert \
    2>&1 | grep -v "WARNING:"


# cardano-cli babbage stake-address stake-delegation-certificate \
#     --stake-verification-key-file $UTXO_KEYS_PATH/stake.vkey \
#     --stake-pool-id $(cardano-cli babbage stake-pool id --cold-verification-key-file $POOL_KEYS_PATH/node.vkey ) \
#     --out-file $POOL_KEYS_PATH/delegation.cert


# Find the tip of the blockchain to set the invalid-hereafter parameter properly:
currentSlot=$(cardano-cli query tip $TESTNET_MAGIC $SOCKET_PATH| jq -r '.slot')
echo Current Slot: $currentSlot


# Find your balance and UTXOs:
cardano-cli query utxo --address $(cat $UTXO_KEYS_PATH/payment.addr) $TESTNET_MAGIC $SOCKET_PATH  > $TXS_PATH/fullUtxo2.out
tail -n +3 $TXS_PATH/fullUtxo2.out | sort -k3 -nr > $TXS_PATH/balance2.out


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
done < $TXS_PATH/balance2.out 


txcnt=$(cat $TXS_PATH/balance2.out | wc -l)
echo Total available ADA balance: ${total_balance}
echo Number of UTXOs: ${txcnt}


# Find the deposit fee for a pool:
stakePoolDeposit=$(cat $CNODE_HOME/files/params.json | jq -r '.stakePoolDeposit')
echo stakePoolDeposit: $stakePoolDeposit

cardano-cli babbage transaction build \
    $TESTNET_MAGIC \
    $SOCKET_PATH \
    ${tx_in} \
    --tx-out $(cat $UTXO_KEYS_PATH/payment.addr)+${stakePoolDeposit}  \
    --change-address $(cat $UTXO_KEYS_PATH/payment.addr) \
    --invalid-hereafter $(( ${currentSlot} + 10000)) \
    --certificate-file $POOL_KEYS_PATH/pool.cert \
    --certificate-file $POOL_KEYS_PATH/delegation.cert \
    --out-file $TXS_PATH/tx2.raw \
    2>&1 | grep -v "WARNING:"



# Sign the transaction:
cardano-cli babbage transaction sign \
    --tx-body-file $TXS_PATH/tx2.raw \
    --signing-key-file $UTXO_KEYS_PATH/payment.skey \
    --signing-key-file $POOL_KEYS_PATH/node.skey \
    --signing-key-file $UTXO_KEYS_PATH/stake.skey \
    $TESTNET_MAGIC\
    --out-file $TXS_PATH/tx2.signed \
    2>&1 | grep -v "WARNING:"


# Send the transaction:
#    --> Output should be aas follows: "Transaction successfully submitted."
cardano-cli babbage transaction submit \
    --tx-file $TXS_PATH/tx2.signed \
    $TESTNET_MAGIC \
    $SOCKET_PATH \
    2>&1 | grep -v "WARNING:"
