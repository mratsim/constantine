# Audit scoping

_Last modified: November, 2024_

This document suggests an audit scope for discussion to serve best the Ethereum ecosystem.

## Overview

The Ethereum community is pursuing credible neutrality and implementation diversification wants to avoid single points of failure.
This is examplified by investing in 5 different clients for the Consensus Layer (CL).

Similarly multiple implementations for cryptography are desired. Constantine is an alternative implementation of cryptography for both consensus and execution layers.

As of November 2024, it is also the fastest cryptography backend for pairing-based cryptography on x86. In particular, with the rise of zkRollups, current non-go BN254 are becoming a bottleneck in Besu (Java), Nethermind (C#), Nimbus-eth1 (Nim) and Reth (Rust) as they are based on the old Zcash implementation (https://github.com/zcash-hackworks/bn) or libff (https://github.com/scipr-lab/libff) which were over 10x slower than state-of-the art already in January 2021 (https://hackmd.io/@gnark/eccbench)

## Library organization
_TODO: tag a new version for audit_

Constantine stores high-level protocols which are exposed to end-users in its root:
- https://github.com/mratsim/constantine/tree/master/constantine

C, Go and Rust API are exposed respectively in
- https://github.com/mratsim/constantine/tree/master/include
- https://github.com/mratsim/constantine/tree/master/constantine-rust
- https://github.com/mratsim/constantine/tree/master/constantine-go

Lower-level implementation is done in subfolders

Elliptic curves:
- fixed-sized bigint and field arithmetic: https://github.com/mratsim/constantine/tree/master/constantine/math/arithmetic
- field extensions: https://github.com/mratsim/constantine/tree/master/constantine/math/extension_fields
- elliptic curve: https://github.com/mratsim/constantine/tree/master/constantine/math/elliptic
- hashing to elliptic curve: https://github.com/mratsim/constantine/tree/master/constantine/hash_to_curve
- pairing-based cryptography: https://github.com/mratsim/constantine/tree/master/constantine/math/pairings
- endomorphisms like Frobenius: https://github.com/mratsim/constantine/tree/master/constantine/math/endomorphisms
- polynomial arithmetic: https://github.com/mratsim/constantine/tree/master/constantine/math/polynomials
- internal/debug IO: https://github.com/mratsim/constantine/tree/master/constantine/math/io

Field/Curve constants are specified in:
- https://github.com/mratsim/constantine/tree/master/constantine/named

Misc:
- arbitrary sized bigint (modexp): https://github.com/mratsim/constantine/tree/master/constantine/math_arbitrary_precision/arithmetic
- sha256: https://github.com/mratsim/constantine/tree/master/constantine/hashes
- HMAC: https://github.com/mratsim/constantine/blob/master/constantine/mac/mac_hmac.nim
- HKDF: https://github.com/mratsim/constantine/tree/master/constantine/kdf
- RNG: https://github.com/mratsim/constantine/tree/master/constantine/csprngs
- threadpool: https://github.com/mratsim/constantine/tree/master/constantine/threadpool

## Dependencies

To remove the thread of supply chain attacks, Constantine has no external dependencies except:
- `std/atomics` a thin-wrapper around C/C++ atomics with C++11 memory model
  for multithreading.
- for testing/fuzzing with dependencies on:
  - Nim standard library for string and sequences (`std/strutils`, `std/strformat` and `std/sequtils`)
  - jsony and nim-yaml package to deserialize test vectors
- benchmarks with dependencies on:
  - `std/times` and `std/monotimes`
  - `std/os` for IO
- at compile-time with dependencies on:
  - `std/macros`
- for C header code generation
  - `std/strtabs` and `std/intsets`

While Nim `system` is used, `string` and `seq` are avoided for:
- zero allocation for functions that might handle secret keys.
- full control over memory management instead of deferring to the Nim allocator.

Non-debug, non-test IO is reimplemented over the C standard library, for example for parsing trusted setups.

Besides supply-chain attacks and leaking secrets on the heap, this also make Constantine easy-to-optimize for trusted enclaves or zkVMs.

## Cryptography for the Consensus Layer

The Consensus Layer of Ethereum relies on the following cryptographic components:

- KZG polynomial commitments:
  - Eth API serial: https://github.com/mratsim/constantine/blob/master/constantine/ethereum_eip4844_kzg.nim
    - backend: https://github.com/mratsim/constantine/blob/master/constantine/commitments/kzg.nim
  - Eth API parallel: https://github.com/mratsim/constantine/blob/master/constantine/ethereum_eip4844_kzg_parallel.nim
    - backend: https://github.com/mratsim/constantine/blob/master/constantine/commitments/kzg_parallel.nim
  - Trusted setup: https://github.com/mratsim/constantine/blob/master/constantine/commitments_setups/ethereum_kzg_srs.nim
- BLS signatures on BLS12-381 curves
  - Eth API serial: https://github.com/mratsim/constantine/blob/master/constantine/ethereum_bls_signatures.nim
    - backend: https://github.com/mratsim/constantine/blob/master/constantine/signatures/bls_signatures.nim
  - Eth API parallel: https://github.com/mratsim/constantine/blob/master/constantine/ethereum_bls_signatures_parallel.nim
    - backend: https://github.com/mratsim/constantine/blob/master/constantine/signatures/bls_signatures_parallel.nim
- EIP-2333
  - Eth API: https://github.com/mratsim/constantine/blob/master/constantine/ethereum_eip2333_bls12381_key_derivation.nim

C, Go and Rust wrappers are available here (and there are parallel headers as well):
- https://github.com/mratsim/constantine/blob/master/include/constantine/protocols/ethereum_eip4844_kzg.h
- https://github.com/mratsim/constantine/blob/master/include/constantine/protocols/ethereum_bls_signatures.h

### Not implemented

The following primitives are of interest but not currently implemented in Constantine:
- EIP-7594, PeerDAS (Data Availability Sampling with 2D erasure codes and KZG)
  - https://github.com/ethereum/consensus-specs/blob/dev/specs/_features/eip7594/polynomial-commitments-sampling.md

- Shamir Secret Sharing as used in Vouch (for threshold signatures) or Obol (for distributed validators):
  - implemented in Nim here: https://github.com/status-im/nim-blscurve/blob/de2d3c7/blscurve/blst/blst_recovery.nim#L74-L156

- fixed size SHA256 (https://github.com/prysmaticlabs/hashtree) and multi-SHA256 for Merkle Trees

- ARM64 assembly

## Cryptography for the Execution Layer

The execution layer relies on the following cryptographic components:

- Precompiles: https://github.com/mratsim/constantine/blob/master/constantine/ethereum_evm_precompiles.nim
  - SHA256
  - Modular Exponentiation
  - BN254 elliptic addition, multiplication and pairing check
  - (next upgrade) BLS12-381 G1 and G2, addition, multiplication, multi-scalar multiplication and pairing check

### In scope?

The following primitive may be in scope, to be discussed:

- Inner Product Argument for Verkle Tries:
  - Ethereum API: https://github.com/mratsim/constantine/blob/master/constantine/ethereum_verkle_ipa.nim
  - Backend: https://github.com/mratsim/constantine/blob/master/constantine/commitments/eth_verkle_ipa.nim

### Not implemented

The following primitives are of interest but not currently implemented in Constantine:

- ECDSA over secp256k1
  - Note that secp256k1 has a specific "Crandall primes" optimization pending further debugging in https://github.com/mratsim/constantine/pull/445
- Keccak, vectorized Keccak, multi-keccak for merkle trees
- Precompiles:
  - ECRecover
  - RIPEMD160
  - Blake2f
  - KZG point verification precompile (trivial, delegates to a consensus layer primitive)

## Specifications and alternative implementations

### Consensus Layer

Spec:
- BLS signatures:
  - https://github.com/ethereum/consensus-specs/blob/dev/specs/phase0/beacon-chain.md#crypto
  - https://www.ietf.org/archive/id/draft-irtf-cfrg-bls-signature-05.html
  - Hashing to elliptic curves:
    - https://www.rfc-editor.org/rfc/rfc9380.html
    - https://github.com/cfrg/draft-irtf-cfrg-hash-to-curve
  - https://github.com/ethereum/bls12-381-tests
- KZG / EIP-4844: https://github.com/ethereum/consensus-specs/blob/dev/specs/deneb/polynomial-commitments.md

Implementations:
- BLST (C), used by all clients
    - https://github.com/google/oss-fuzz/pull/5641
    - https://github.com/GaloisInc/BLST-Verification/
    - Audit: https://www.nccgroup.com/us/research-blog/public-report-blst-cryptographic-implementation-review/

    including the KZG primitives for EIP4844:
    - https://github.com/ethereum/c-kzg-4844/blob/main/doc/audit/Sigma_Prime_Ethereum_Foundation_KZG_Implementations_Security_Assessment.pdf

- Gnark (go)
  - https://github.com/Consensys/gnark-crypto
    - audit: https://github.com/Consensys/gnark/blob/master/audits/2022-10%20-%20Kudelski%20-%20gnark-crypto.pdf
  - https://github.com/crate-crypto/go-kzg-4844

- MCL (C++), was used by Prysm
  - https://github.com/herumi/mcl
  - Audit: https://blog.quarkslab.com/technical-assessment-of-the-herumi-libraries.html
    - https://blog.quarkslab.com/resources/2020-12-17-technical-assessment-of-herumi-libraries/20-07-732-REP.pdf

- MIRACL/Milagro (all lang), first cryptographic backend for all clients in 2018~2020, abandoned due to performance constraints:
  - https://github.com/apache/incubator-milagro-crypto-c
  - https://github.com/miracl/amcl
  - https://github.com/miracl/core

- py_ecc (python): https://github.com/ethereum/py_ecc

### Execution Layer

Note on name:
There are multiple BN254 curves in the literature, the one we refer to has high 2-adicity to enable large FFTs in Snarks application. It used to be called `alt_bn128` (128 being the security level it was considered at before Kim & Barbulesco TNFS attack) and it is also sometimes called bn256.

Specs:
- MODEXP
  - Yellow Paper Appendix E
  - EIP-198 - https://github.com/ethereum/EIPs/blob/master/EIPS/eip-198.md
- BN254:
  - EIP-196 (add/mul): https://eips.ethereum.org/EIPS/eip-196
  - EIP-197 (pairing): https://eips.ethereum.org/EIPS/eip-197
  - EIP-1108 (gas repricing): https://eips.ethereum.org/EIPS/eip-1108
- BLS12-381:
  - EIP-2537: https://eips.ethereum.org/EIPS/eip-2537

Implementations (used or that were referred to when EIP were drafted):
- Zcash (Rust): https://github.com/zcash-hackworks/bn
- libff (C++): https://github.com/scipr-lab/libff
- py_ecc (Python): https://github.com/ethereum/py_ecc
- Nethermind (C# and Rust):
  - https://github.com/NethermindEth/nethermind/tree/1.29.1/src/Nethermind/Nethermind.Evm/Precompiles/Snarks
  - dep: https://github.com/NethermindEth/eth-pairings-bindings/tree/main/src/Nethermind.Crypto.Pairings
  - https://github.com/matter-labs/eip1962
- Geth (Go):
  - Cloudflare, Google and Gnark: https://github.com/ethereum/go-ethereum/tree/master/crypto/bn256
- Besu (Java):
  - pure Java: https://github.com/hyperledger/besu/tree/24.10.0/crypto/algorithms/src/main/java/org/hyperledger/besu/crypto/altbn128
  - Rust from Parity fork of Zcash: https://github.com/hyperledger/besu-native/pull/9
    - https://github.com/paritytech/bn
  - Rust from Matter labs: https://github.com/hyperledger/besu-native/pull/21
  - Gnark: https://github.com/hyperledger/besu-native/pull/168
  - Constantine: https://github.com/hyperledger/besu-native/pull/184
- Nimbus (Nim):
  - https://github.com/status-im/nim-bncurve
    This is a 1-1 port of https://github.com/zcash-hackworks/bn

### Fuzzing

Constantine is integrated in
- Cryptofuzz: https://github.com/guidovranken/el-fuzzers/tree/master/cryptofuzz/modules/constantine
- OSS-fuzz: https://github.com/google/oss-fuzz/pull/10710

Constantine is not integrated in
- KZG:
  - https://github.com/ethereum/c-kzg-4844/tree/main/fuzz
  - https://github.com/jtraglia/kzg-fuzz
- Geth:
  - https://github.com/ethereum/go-ethereum/tree/v1.14.12/tests/fuzzers/bn256
  - https://github.com/ethereum/go-ethereum/tree/v1.14.12/tests/fuzzers/bls12381