#!/bin/sh
set -eu

NM=${1:?usage: check_riscv64_freestanding_archive.sh <llvm-nm> <archive>}
ARCHIVE=${2:?usage: check_riscv64_freestanding_archive.sh <llvm-nm> <archive>}
SYMBOLS=$("$NM" --defined-only --extern-only "$ARCHIVE")

for symbol in \
  ctt_eth_evm_bls12381_g1add \
  ctt_eth_evm_bls12381_g2add \
  ctt_eth_evm_bls12381_g1msm \
  ctt_eth_evm_bls12381_g2msm \
  ctt_eth_evm_bls12381_pairingcheck \
  ctt_eth_evm_bls12381_map_fp_to_g1 \
  ctt_eth_evm_bls12381_map_fp2_to_g2 \
  ctt_eth_evm_bn254_g1add \
  ctt_eth_evm_bn254_g1mul \
  ctt_eth_evm_bn254_ecpairingcheck \
  ctt_eth_zkvm_secp256k1_verify \
  ctt_eth_zkvm_secp256k1_ecrecover \
  ctt_eth_kzg_context_new_embedded \
  ctt_eth_evm_kzg_point_evaluation
do
  if ! printf '%s\n' "$SYMBOLS" | awk -v symbol="$symbol" '$NF == symbol { found = 1 } END { exit !found }'; then
    printf 'missing guest ABI symbol: %s\n' "$symbol" >&2
    exit 1
  fi
done

if printf '%s\n' "$SYMBOLS" | awk '$NF ~ /(parallel|threadpool)/ { print; found = 1 } END { exit !found }'; then
  printf 'freestanding archive exports parallel or threadpool API symbols\n' >&2
  exit 1
fi

for symbol in panic rawoutput
do
  count=$(printf '%s\n' "$SYMBOLS" | awk -v symbol="$symbol" '$NF == symbol { count++ } END { print count + 0 }')
  if [ "$count" -gt 1 ]; then
    printf 'freestanding archive contains %s duplicate definitions of %s\n' "$count" "$symbol" >&2
    exit 1
  fi
done
