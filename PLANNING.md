# Constantine's planning

This document is current as of June 23, 2024.

This splits Constantine's axis of development under various tracks.
Priority is given to Ethereum, proof systems and optimization tracks.

Other tracks are stretch goals, contributions towards them are accepted.

## Table of Contents

<!-- TOC -->

- [Constantine's planning](#constantines-planning)
    - [Table of Contents](#table-of-contents)
    - [Tracks](#tracks)
        - [Tech debt track](#tech-debt-track)
        - [Ethereum Consensus Track](#ethereum-consensus-track)
        - [Ethereum Execution Track](#ethereum-execution-track)
        - [Proving Ethereum track](#proving-ethereum-track)
        - [Optimization track](#optimization-track)
        - [User Experience track](#user-experience-track)
        - [Technical marketing track](#technical-marketing-track)
        - [ZK and proof systems track](#zk-and-proof-systems-track)
        - [Multi-party computation MPC track](#multi-party-computation-mpc-track)
        - [Core crypto track](#core-crypto-track)
        - [Fully-Homomorphic encryption FHE track](#fully-homomorphic-encryption-fhe-track)
        - [Post-Quantum cryptography PQC track](#post-quantum-cryptography-pqc-track)

<!-- /TOC -->

## Tracks

### Tech debt track

- Endomorphism splitting bounds guarantee: i.e. division-based vs lattice-based splitting
- Fix optimized MSM

Internal API breakage, which might leak to others using internal APIs.

- Expand the library to support named fields and not just curves
    - move and rename the config & constant folder
    - use field instead of curve
    - "named_math/fields_and_curves"
    - matchingOrderBigInt -> BigInt[foo.getOrder()]
    - Delete Mod*(), replace by fieldMod
- In the future there will likely be named ciphersuites or other high-level protocols



### Ethereum Consensus Track

- Implement cryptography and erasure codes EIP-7594 PeerDAS
  - https://github.com/mratsim/constantine/issues/341
  - Spec:
    - crypto: https://github.com/ethereum/consensus-specs/blob/29d3a24/specs/_features/eip7594/polynomial-commitments-sampling.md
    - erasure codes: https://github.com/ethereum/consensus-specs/blob/29d3a24/specs/_features/eip7594/das-core.md#recover_matrix
  - executive summary: 2-dimensional data availability sampling for KZG polynomial commitments
  - Prerequisites:
    - Coset FFT
    - KZG multiproofs
    - Polynomial interpolation
- Fuzzing
    - BLS signatures
    - KZG in https://github.com/jtraglia/kzg-fuzz

- Long-term project, unspecified:
    - Secret Shared Leader Election
    - Single Slot Finality
    - enshrined DVT (distributed validator technology)

### Ethereum Execution Track

- Keccak
  - with hardware acceleration
- Hash functions precompiles:
  - RIPEMD-160, Blake2
- KZG point precompile
- Verkle Tries
  - Finish IPA for Verkle Tries:
    - Fix verification outside AddressSanitizer
    - Full test suite coverage https://github.com/mratsim/constantine/issues/396
    - Fix multiproofs
    - Add IPA and multiproofs to benchmark to compare with other implementations

- Fast MSM for fixed base like Trusted Setups and Ethreum Verkle Tries
  - Notes on MSMs with precomputation https://hackmd.io/WfIjm0icSmSoqy2cfqenhQ
  - Verkle Trees - Another iteration of VKTs MSMs https://hackmd.io/@jsign/vkt-another-iteration-of-vkt-msms

### Proving Ethereum track

- Proof-of-equivalence for Ethereum KZG:
  - https://notes.ethereum.org/@vbuterin/proto_danksharding_faq#Moderate-approach-works-with-any-ZK-SNARK
  - https://notes.ethereum.org/@dankrad/kzg_commitments_in_proofs
  - https://ethresear.ch/t/easy-proof-of-equivalence-between-multiple-polynomial-commitment-schemes-to-the-same-data/8188

  - Prerequisites:
    - ZK friendly hash function like Poseidon (there are 2 versions !): https://github.com/mratsim/constantine/issues/294

- Groth16 + on-chain verifier code-generator (solidity/huff/yul)

- Long-term project, unspecified:
    - Snarkified EVM

### Optimization track

- ARM assembly
- Finish Nvidia GPU codegenerator up to MSM
- Implement an unsaturated finite fields backend for Risc-V, WASM, WebGPU, AMD GPU, Apple Metal, Vulkan, ...
    - ideally in LLVM IR so that pristine Risc-V assembly can be generated
      and used in zkVMs without any risk of C stdlib or syscalls being used
      and without depending on the Nim compiler at build time.
- introduce batchAffine_vartime

### User Experience track

- Provide curves_sugar and fields_sugar higher-level with
  out-of-place functions like `+` and `*`.
    - They should be tagged {.inline, noInit.} and just forward to the in-place function
      to guarantee copy elision.
    - Mention lack of control over stack space
    - Guaranteed optimization issue
        - with even up to a dramatic 20% perf:
            - https://www.reddit.com/r/rust/comments/kfs0oe/comment/ggc0dui/
            - past Constantine large copy bug:
                - out-of-place function lead to bad codegen:
                  - https://github.com/mratsim/constantine/issues/145
                - https://github.com/nim-lang/Nim/issues/16897
    - Mention Rust GCE and NRVO / RVO
    - https://github.com/rust-lang/rust/pull/76986
    - https://github.com/rust-lang/rfcs/pull/2884

- Shorter names:
    - Rename to EC_ShortW
    - Rename to EC_TwEdw

### Technical marketing track

- Create Python bindings
    - provide primitives appealing to cryptography researchers and enabling fast prototyping

- Create a Constantine benchmark CLI and UI.
  - Make it easy-to-use from tools like Phoronix test suite
  - Give a single-threaded/multi-threaded, for use in say EthDocker to rank hardware.
  - Integrate building it in CI
  - Goal: the reference cryptographic benchmark

- Participate in secp256k1 programming language benchmark:
  - https://programming-language-benchmarks.vercel.app/problem/secp256k1
  - outline: https://github.com/mratsim/constantine/issues/285

### ZK and proof systems track

- Transcripts (Halo2, Merlin)
    - https://zcash.github.io/halo2/design/implementation/proofs.html
    - https://merlin.cool/transcript/index.html

- SNARKS:
    - Polynomial IOP (Interactive Oracle Proof)
      Implement BabySpartan (Spartan+Lasso) or Spartan or Spartan2

    - Lookup Argument
      One that commits to only small field elements if the witness contains small field elements
      Example: Lasso or LogUp+GKR

    - Multilinear Polynomial Commitment Schemes
      For efficiency when commiting to small values (for example coming from bit manipulation in hash functions)
      Example: KZG+Gemini/Zeromorph, Dory, Hyrax, Binius, ...

- STARKS:
    - Implement small fields:
      - Mersenne31: 2^31-1
      - BabyBear
      - Goldilocks
    - Optimize small fields with Neon / Avx512
    - Implement FRI and/or STIR
        - Prerequisites:
            - Erasure codes
            - Merkle Trees

Long-term, unspecified:
- zkML

### Multi-party computation (MPC) track

- Implement Shamir Secret Sharing
- Threshold signatures and Distributed Key Generation for DVT (Distributed Validator Technology)

### Core crypto track

- Implement NaCl / libsodium API:
- Implement the Signal Protocol:
  - https://signal.org/docs/
- Implement TLSv3:
  - https://datatracker.ietf.org/doc/html/rfc8446
- Json Web Tokens

### Fully-Homomorphic encryption (FHE) track

- Implement lattice-based RLWE: Ring-Learning-With-Errors

Long-term, unspecified:
- Privacy-perserving machine learning

### Post-Quantum cryptography (PQC) track

- Implement a lattice-based cryptography scheme
