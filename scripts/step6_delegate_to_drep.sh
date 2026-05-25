#!/usr/bin/env bash
#
# step6_register_drep_delegation.sh
#
# Register a vote delegation certificate. Since the Conway era, a stake credential
# must first set vote delegation before it can withdraw staking rewards, participate
# in governance snapshot statistics, etc.
#
# Usage:
#   ./step6_register_drep_delegation.sh                  # default always-abstain
#   ./step6_register_drep_delegation.sh abstain          # same as above
#   ./step6_register_drep_delegation.sh no-confidence    # always vote no confidence
#   ./step6_register_drep_delegation.sh drep <DREP_ID>   # delegate to specific DRep
#
# DREP_ID can be bech32 (drep1...) or hex key hash or hex script hash.
# The script will auto-detect and pass the correct cardano-cli parameter.

set -euo pipefail

# ---------- environment ----------
TESTNET_MAGIC="--testnet-magic 42"
SOCKET_PATH="--socket-path ${CNODE_HOME}/sockets/node.socket"

UTXO_KEYS_PATH=~/keys/utxo-keys
TXS_PATH=~/txs
mkdir -p "$TXS_PATH"

PAYMENT_ADDR=$(cat "$UTXO_KEYS_PATH/payment.addr")
STAKE_ADDR=$(cat "$UTXO_KEYS_PATH/stake.addr")

# ---------- arguments ----------
MODE=${1:-abstain}

case "$MODE" in
    abstain)
        DELEG_FLAG="--always-abstain"
        DELEG_DESC="alwaysAbstain"
        ;;
    no-confidence)
        DELEG_FLAG="--always-no-confidence"
        DELEG_DESC="alwaysNoConfidence"
        ;;
    drep)
        if [ "$#" -lt 2 ]; then
            echo "Error: 'drep' mode requires a DRep ID."
            echo "Usage: $0 drep <DREP_ID>"
            exit 1
        fi
        DREP_ID=$2
        # auto-detect DREP ID type by prefix or length
        if [[ "$DREP_ID" =~ ^drep_script1 ]]; then
            DELEG_FLAG="--drep-script-hash $DREP_ID"
        elif [[ "$DREP_ID" =~ ^drep1 ]]; then
            DELEG_FLAG="--drep-key-hash $DREP_ID"
        elif [[ "$DREP_ID" =~ ^[0-9a-fA-F]{56}$ ]]; then
            # 28-byte hex hash，默认按 key hash 处理（脚本 hash 同长度，无法自动区分）
            DELEG_FLAG="--drep-key-hash $DREP_ID"
        else
            echo "Error: unrecognized DRep ID format: $DREP_ID"
            echo "Expected: drep1... / drep_script1... / 56-char hex"
            exit 1
        fi
        DELEG_DESC="DRep $DREP_ID"
        ;;
    *)
        echo "Usage: $0 [abstain | no-confidence | drep <DREP_ID>]"
        exit 1
        ;;
esac

echo "===================================="
echo "Vote delegation target: $DELEG_DESC"
echo "Stake address:          $STAKE_ADDR"
echo "Payment address:        $PAYMENT_ADDR"
echo "===================================="

# ---------- query stake address status ----------
stake_info=$(cardano-cli query stake-address-info \
    --address "$STAKE_ADDR" \
    $TESTNET_MAGIC $SOCKET_PATH)

is_registered=$(echo "$stake_info" | jq -r 'if length > 0 then "yes" else "no" end')

if [[ "$is_registered" != "yes" ]]; then
    echo "Error: stake address is not registered yet. Run step4 first."
    exit 1
fi

current_vote_deleg=$(echo "$stake_info" | jq -r '.[0].voteDelegation // "none"')
if [[ "$current_vote_deleg" != "none" && "$current_vote_deleg" != "null" ]]; then
    echo "Note: stake credential already has vote delegation: $current_vote_deleg"
    echo "Submitting will overwrite the existing delegation."
fi

# ---------- generate vote delegation certificate ----------
VOTE_DELEG_CERT="$UTXO_KEYS_PATH/vote-deleg.cert"

cardano-cli conway stake-address vote-delegation-certificate \
    --stake-verification-key-file "$UTXO_KEYS_PATH/stake.vkey" \
    $DELEG_FLAG \
    --out-file "$VOTE_DELEG_CERT" \
    2>&1 | grep -v "WARNING:" || true

echo "Vote delegation certificate written: $VOTE_DELEG_CERT"

# ---------- query current slot ----------
currentSlot=$(cardano-cli query tip $TESTNET_MAGIC $SOCKET_PATH | jq -r '.slot')
echo "Current Slot: $currentSlot"

# ---------- query UTXO ----------
cardano-cli query utxo \
    --address "$PAYMENT_ADDR" \
    $TESTNET_MAGIC $SOCKET_PATH \
    --out-file "$TXS_PATH/utxo_drep.json"

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
done < <(jq -c 'to_entries[]' "$TXS_PATH/utxo_drep.json")

txcnt=$(jq 'length' "$TXS_PATH/utxo_drep.json")
echo "Total available lovelace balance: ${total_balance}"
echo "Number of UTXOs: ${txcnt}"

if [[ -z "$tx_in" ]]; then
    echo "Error: no spendable UTXO at $PAYMENT_ADDR"
    exit 1
fi

# ---------- Build / Sign / Submit ----------
cardano-cli conway transaction build \
    $tx_in \
    --change-address "$PAYMENT_ADDR" \
    --certificate-file "$VOTE_DELEG_CERT" \
    --invalid-hereafter $((currentSlot + 10000)) \
    --witness-override 2 \
    $TESTNET_MAGIC $SOCKET_PATH \
    --out-file "$TXS_PATH/tx_drep.raw" \
    2>&1 | grep -v "WARNING:" || true

cardano-cli conway transaction sign \
    --tx-body-file "$TXS_PATH/tx_drep.raw" \
    --signing-key-file "$UTXO_KEYS_PATH/payment.skey" \
    --signing-key-file "$UTXO_KEYS_PATH/stake.skey" \
    $TESTNET_MAGIC \
    --out-file "$TXS_PATH/tx_drep.signed" \
    2>&1 | grep -v "WARNING:" || true

TXID=$(cardano-cli conway transaction txid --tx-file "$TXS_PATH/tx_drep.signed" \
    | jq -r '.txhash // .')
echo "TxID: $TXID"

cardano-cli conway transaction submit \
    --tx-file "$TXS_PATH/tx_drep.signed" \
    $TESTNET_MAGIC $SOCKET_PATH \
    2>&1 | grep -v "WARNING:" || true

# ---------- Archive sent transaction ----------
rm -f "$TXS_PATH/tx_drep.raw"
mv "$TXS_PATH/tx_drep.signed" "$TXS_PATH/tx_drep.${TXID}.sent"

echo ""
echo "===================================="
echo "Vote delegation submitted."
echo "Archived as: tx_drep.${TXID}.sent"
echo ""
echo "Verify with:"
echo "  cardano-cli query stake-address-info \\"
echo "      --address \"\$(cat $UTXO_KEYS_PATH/stake.addr)\" \\"
echo "      $TESTNET_MAGIC $SOCKET_PATH"
echo ""
echo "===================================="