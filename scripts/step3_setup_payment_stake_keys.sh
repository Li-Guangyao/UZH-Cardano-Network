#!/usr/bin/env bash

# Payment keys are used to send and receive payments and stake keys are used to manage stake delegations.

TESTNET_MAGIC="--testnet-magic 2025"

UTXO_KEYS_PATH=~/keys/utxo-keys
POOL_KEYS_PATH=~/keys/pool-keys
mkdir -p $UTXO_KEYS_PATH
mkdir -p $POOL_KEYS_PATH

# Create a new "payment key pair":
cardano-cli address key-gen \
    --verification-key-file $UTXO_KEYS_PATH/payment.vkey \
    --signing-key-file $UTXO_KEYS_PATH/payment.skey


# Create a new "stake address key pair":
cardano-cli conway stake-address key-gen \
    --verification-key-file $UTXO_KEYS_PATH/stake.vkey \
    --signing-key-file $UTXO_KEYS_PATH/stake.skey


# Create your "stake address" from the stake address verification key:
cardano-cli conway stake-address build \
    --stake-verification-key-file $UTXO_KEYS_PATH/stake.vkey \
    --out-file $UTXO_KEYS_PATH/stake.addr \
    $TESTNET_MAGIC


# **************=============================================================================================================================================**************
# ************** =====>>>>>>>> Build a "payment address" for the payment key payment.vkey which will delegate to the stake address, stake.vkey <<<<<<<<===== **************:
# **************=============================================================================================================================================**************

#cd $UTXO_KEYS_PATH
cardano-cli address build \
    --payment-verification-key-file $UTXO_KEYS_PATH/payment.vkey \
    --stake-verification-key-file $UTXO_KEYS_PATH/stake.vkey \
    --out-file $UTXO_KEYS_PATH/payment.addr \
    $TESTNET_MAGIC


echo Your payment address is: $(cat $UTXO_KEYS_PATH/payment.addr)

