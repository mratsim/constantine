# Constantine-backed protocols

This folder stores protocols implemented on top of Constantine.

It also provides low-level "Named math objects" like named elliptic curves or fields.

Warning ⚠️:
    The low-level APIs have no stability guarantee.
    Use high-level protocols which are designed according to a stable specs
    and with misuse resistance in mind.

<!-- TOC -->

- [Constantine-backed protocols](#constantine-backed-protocols)
    - [Ethereum Consensus Layer](#ethereum-consensus-layer)
        - [BLS signatures](#bls-signatures)
            - [Performance](#performance)
        - [BLS12-381 Key Derivation for wallets](#bls12-381-key-derivation-for-wallets)
        - [KZG commitments for EIP-4844](#kzg-commitments-for-eip-4844)
            - [Performance](#performance)
    - [Ethereum Execution Layer](#ethereum-execution-layer)
        - [Ethereum Virtual Machine](#ethereum-virtual-machine)
            - [Performance](#performance)
        - [IPA for Verkle Tries](#ipa-for-verkle-tries)

<!-- /TOC -->

## Ethereum Consensus Layer

### BLS signatures

Constantine implements the full BLS signatures used in CL clients.
Batch verification is also parallelized.

Specs:
- https://github.com/ethereum/consensus-specs/blob/v1.4.0/specs/phase0/beacon-chain.md#bls-signatures
- https://www.ietf.org/archive/id/draft-irtf-cfrg-bls-signature-05.html

#### Performance

source, serial bench from https://github.com/mratsim/constantine/pull/279#issuecomment-1746433431
- 1.19x faster signing than BLST
- 1.25x faster verification

### BLS12-381 Key Derivation for wallets

Specs:
- https://eips.ethereum.org/EIPS/eip-2333

### KZG commitments for EIP-4844

Constantine implements the full Ethereum KZG API in Nim, C, Rust, Go for CL clients.
It is also fully parallelized.

Specs:
- https://github.com/ethereum/consensus-specs/blob/v1.4.0/specs/deneb/polynomial-commitments.md

#### Performance

https://github.com/mratsim/constantine/pull/304#issuecomment-1844795359

|             Bench              | c-kzg-4844 (serial) | go-kzg-4844 (serial) | go-kzg-4844 (parallel) | constantine (serial) | constantine (parallel) |
|:------------------------------:|:-------------------:|:--------------------:|:----------------------:|:--------------------:|:----------------------:|
|     blob_to_kzg_commitment     |      37.773 ms      |          -           |        5.823 ms        |      23.765 ms       |        4.425 ms        |
|       compute_kzg_proof        |      39.945 ms      |          -           |        7.146 ms        |      24.255 ms       |        4.710 ms        |
|     compute_blob_kzg_proof     |      40.212 ms      |          -           |        7.205 ms        |      24.288 ms       |        4.794 ms        |
|        verify_kzg_proof        |      0.915 ms       |       0.923 ms       |           -            |       0.782 ms       |           -            |
|     verify_blob_kzg_proof      |      1.531 ms       |          -           |        1.390 ms        |       1.266 ms       |        1.113 ms        |
| verify_blob_kzg_proof_batch 1  |      1.528 ms       |       1.392 ms       |        1.405 ms        |       1.286 ms       |        1.130 ms        |
| verify_blob_kzg_proof_batch 2  |      2.589 ms       |       3.233 ms       |        1.591 ms        |       2.006 ms       |        1.152 ms        |
| verify_blob_kzg_proof_batch 4  |      4.553 ms       |       4.671 ms       |        1.914 ms        |       3.437 ms       |        1.250 ms        |
| verify_blob_kzg_proof_batch 8  |      8.446 ms       |       7.410 ms       |        2.738 ms        |       6.115 ms       |        1.891 ms        |
| verify_blob_kzg_proof_batch 16 |      16.228 ms      |      12.734 ms       |        3.542 ms        |      11.567 ms       |        3.091 ms        |
| verify_blob_kzg_proof_batch 32 |      32.016 ms      |      23.048 ms       |        7.215 ms        |      21.779 ms       |        6.764 ms        |
| verify_blob_kzg_proof_batch 64 |      63.415 ms      |      43.224 ms       |       14.438 ms        |      43.099 ms       |       11.538 ms        |

## Ethereum Execution Layer

### Ethereum Virtual Machine

Constantine implements precompiles primitives for the Ethereum virtual machine

- SHA256
- ECADD on BN254_Snarks (called `alt_bn128` in Ethereum), address 0x6, spec [EIP-196](https://eips.ethereum.org/EIPS/eip-196) and pricing [EIP-1108](https://eips.ethereum.org/EIPS/eip-1108)
- ECMUL on BN254_Snarks (called `alt_bn128` in Ethereum), address 0x7, spec [EIP-196](https://eips.ethereum.org/EIPS/eip-196) and pricing [EIP-1108](https://eips.ethereum.org/EIPS/eip-1108)
- ECPAIRING on BN254_Snarks (called `alt_bn128` in Ethereum), address 0x8, spec [EIP-197](https://eips.ethereum.org/EIPS/eip-197) and pricing [EIP-1108](https://eips.ethereum.org/EIPS/eip-1108)
- MODEXP, arbitrary precision modular exponentiation, spec [EIP-198](https://eips.ethereum.org/EIPS/eip-198)
- BLS12-381 precompiles (addition, scalar multiplication, MSM, pairing, hashing-to-curve), spec [EIP-2537](https://eips.ethereum.org/EIPS/eip-2537)

#### Performance

- SHA256 implementation is faster than OpenSSL's for messages less than 65kB: https://github.com/mratsim/constantine/pull/206
  and 16% faster for 32 bytes.
- EIP-2537: https://github.com/mratsim/constantine/pull/368
- https://ethereum-magicians.org/t/eip-2537-bls12-precompile-discussion-thread/4187/76

### IPA for Verkle Tries

Those are currently WIP
