# Constantine v0.2.0 "Coat of Arms"

Jan 26, 2025, commit TBD

I am very happy to present you the second version of Constantine.

I thank the Ethereum Foundation for their sponsorship on implementing Torus-based cryptography to make the performance of Secret Leader Election viable.

The highlight of this release, and the inspiration for its name is the introduction of specialized ARM64 assembly for most key field operations and SHA256. Thanks to it the latest M4 Max is within 5% of an overclocked AMD Ryzen 9950X on single-threaded performance (though multithreaded performance is lackluster due to Apple very aggressive powersaving). Currently this is only for MacOS but will be coming to Linux, Android and iOS.

The second highlight of this release is significant backend work for JIT compiling elliptic curves to Nvidia and AMD GPUs. \
Backends for x86 and ARM have also been explored and could present an alternative to provide libconstantine as a fully optimized assembly file, at least at Ethereum and elliptic curves level. This would streamline build systems by removing the Nim compiler. and also make it easy to vectorize the library.

Constantine is currently being scoped for a security audit, after which a 1.0 version should follow.
You can review the scope here: https://github.com/mratsim/constantine/pull/483, and I'm looking for sponsors.

An independent benchmark showed that Constantine is as of January 2025 the fastest backend for EIP-4844 / KZG polynomial commitments: https://github.com/grandinetech/rust-kzg.

Now let's review the main changes per-category

## Ethereum

The focus for this release has been Ethereum Execution layer with the introduction of:
- Keccak hash function
- ECDSA signatures over secp256k1
- RIPEMD160 hash function and EVM precompile
- KZG Point Evaluation EVM precompile
- ECRECOVER precompile (under review)
- repricing of EIP-2537 (BLS12-381 precompiles)

Performance on x86 and ARM is detailed in: https://github.com/mratsim/constantine/pull/520

The precompiles are exposed in C, Nim and Rust except ECRECOVER which is under review for corner cases that may not be covered by Ethereum tests and "low performance" (a 1.7x perf advantage at low-level turns to 1x no advantage at elliptic curve level - https://github.com/mratsim/constantine/issues/446)

The inner product argument (IPA) multi-proof primitives for Ethereum Verkle Tries have been thoroughly reviewed and improved.

On the Consensus side, sponsored work has been done on accelerating multi-exponentiation in 𝔾ₜ pairing group via Torus-based cryptography for the purposes of secret leader election: https://ethresear.ch/t/the-return-of-torus-based-cryptography-whisk-and-curdleproof-in-the-target-group/16678/4

## Proof-system

Multilinear extensions of polynomials have been added. This is a prerequisite for sumchecks, the current state-of-the-art proving technique in research.

## Backend

We added an ARM64 compile-time assembler and 90% of the main computing bottlenecks now have ARM64 acceleration.
Performance: https://github.com/mratsim/constantine/pull/513

Exploration in LLVM JIT compilation for GPU has been progressing with:
- the Nvidia backend now having a prototype serial MSM
- AMD GPUs being supported

The threadpool had a task garbage collection fix on ARM64 (and other weak memory models ISA)

## Misc

Constantine can now generate benchmarks in https://zka.lc format with

```
git clone https://github.com/mratsim/constantine
cd constantine
nimble make_zkalc
bin/constantine-bench-zkalc --curve=BLS12_381 --o=myoutputfile.json
```

## Future work

- Work is currently being done to improve the LLVM backend codegen. It may provide multiple advantages:
  - pure assembly: remove GCC vs Clang compiler differences (may be as high as 20%).
  - we can ensure constant-time properties without the compiler rugpulling us.
  - vectorization can be just changing `i256` to `<i256 x 4>` and reusing the exact same LLVM IR.
- GPU acceleration
- Ethereum Data Availability sampling (Erasure coding + 2D KZG proofs)
- Sumchecks Polynomial commitment scheme (PCS)
- Small fields support like Baby Bear, Koala Bear, Goldilocks and Mersenne31
- FRI, Deep FRI and STIR PCS.
- Blake2 to finish EVM precompiles.

## Detailed changes (auto-generated)
* Multilinear extensions of polynomials by @mratsim in https://github.com/mratsim/constantine/pull/423
* add: multiproof consistency test by @agnxsh in https://github.com/mratsim/constantine/pull/424
* fix `scalarMul_vartime` for tiny multiple 5 by @Vindaar in https://github.com/mratsim/constantine/pull/426
* feat(bench): PoC of integration with zkalc by @mratsim in https://github.com/mratsim/constantine/pull/425
* 𝔾ₜ exponentiation, with endomorphism acceleration by @mratsim in https://github.com/mratsim/constantine/pull/429
* Formal verification: resurrect fiat-crypto with formally verified assembly by @mratsim in https://github.com/mratsim/constantine/pull/430
* Constant-time 𝔾ₜ exponentiation with endomorphism acceleration by @mratsim in https://github.com/mratsim/constantine/pull/431
* fix(cryptofuzz): expose all cryptofuzz tested primitives in lowlevel_* by @mratsim in https://github.com/mratsim/constantine/pull/432
* fix(arith): bug in vartime inversion when using fused inverse+multiply by factor - found by Guido Vranken by @mratsim in https://github.com/mratsim/constantine/pull/433
* Compatibility with Nim v1.6.x, Nim v2.0.x, Nim v2.2.x by @mratsim in https://github.com/mratsim/constantine/pull/434
* fix(gcc): compatibility with GCC14 by @mratsim in https://github.com/mratsim/constantine/pull/435
* 𝔾ₜ multi-exponentiations by @mratsim in https://github.com/mratsim/constantine/pull/436
* feat(public API): expose hashing to curve for BN254 and BLS12-381 by @mratsim in https://github.com/mratsim/constantine/pull/437
* fix(nvidia): reorg + rename following #402 by @mratsim in https://github.com/mratsim/constantine/pull/439
* Nvidia backend: update for LLVM 17 by @mratsim in https://github.com/mratsim/constantine/pull/440
* fix: 32-bit on 64-bit compilation by @mratsim in https://github.com/mratsim/constantine/pull/441
* fix test suite for banderwagon by @advaita-saha in https://github.com/mratsim/constantine/pull/442
* feat(secp256k1): add endomorphism acceleration by @mratsim in https://github.com/mratsim/constantine/pull/444
* workaround #448: deactivated secp256k1 tests due to bug on Windows with assembly by @mratsim in https://github.com/mratsim/constantine/pull/449
* research: update LLVM x86 compiler and JIT by @mratsim in https://github.com/mratsim/constantine/pull/452
* AMDGPU JIT compiler by @mratsim in https://github.com/mratsim/constantine/pull/453
* LLVM: field addition with saturated fields by @mratsim in https://github.com/mratsim/constantine/pull/456
* Verkle ipa multiproof is now internally consistent by @mratsim in https://github.com/mratsim/constantine/pull/458
* fix MSM bench using 64-bit scalars after #444 [skip ci] by @mratsim in https://github.com/mratsim/constantine/pull/460
* fixes when nimvm mixing different types by @ringabout in https://github.com/mratsim/constantine/pull/459
* fixes another mixing types by @ringabout in https://github.com/mratsim/constantine/pull/461
* Nvidia remastered by @mratsim in https://github.com/mratsim/constantine/pull/464
* Halo2 0.4 and Halo2curves 0.7 compat + Rust warnings fixes by @mratsim in https://github.com/mratsim/constantine/pull/468
* fix: template typechecking is more stringent by @mratsim in https://github.com/mratsim/constantine/pull/470
* CI: replace apt-fast by apt-get + Nim v2.2.x in CI as Nim v2.0.10 is broken. by @mratsim in https://github.com/mratsim/constantine/pull/473
* Fixes for Nim v2.2 by @mratsim in https://github.com/mratsim/constantine/pull/476
* Implement finite field `ccopy`, `neg`, `cneg`, `nsqr`, ... for CUDA target by @Vindaar in https://github.com/mratsim/constantine/pull/466
* CI: drop old nim compiler versions by @mratsim in https://github.com/mratsim/constantine/pull/486
* Torus-acceleration for multiexponentiation on GT by @mratsim in https://github.com/mratsim/constantine/pull/485
* fix(MSM): properly handle edge condition in parallel MSM when bits is exactly divided by c by @mratsim in https://github.com/mratsim/constantine/pull/484
* Crandall primes by @mratsim in https://github.com/mratsim/constantine/pull/445
* Add KZG point precompile by @Vindaar in https://github.com/mratsim/constantine/pull/489
* Keccak256 and SHA3-256 by @mratsim in https://github.com/mratsim/constantine/pull/494
* Keccak optimizations by @mratsim in https://github.com/mratsim/constantine/pull/498
* Improve Rust build script by @DaniPopes in https://github.com/mratsim/constantine/pull/500
* fix(threadpool): fix task garbage collection synchronization on weak memory models by @mratsim in https://github.com/mratsim/constantine/pull/503
* refactor(add-carry): with Clang on non-x86 (for example MacOS) use builtin add-carry instead of u128 by @mratsim in https://github.com/mratsim/constantine/pull/411
* Add ECDSA over secp256k1 signatures and verification by @Vindaar in https://github.com/mratsim/constantine/pull/490
* keccak: OpenSSL skip MacOS test by @mratsim in https://github.com/mratsim/constantine/pull/508
* fix(threadpool regression): deadlock on Windows on fibonacci by @mratsim in https://github.com/mratsim/constantine/pull/509
* C bindings for Banderwagon by @Richa-iitr in https://github.com/mratsim/constantine/pull/477
* Nvidia MSM proof of concept (serial) by @Vindaar in https://github.com/mratsim/constantine/pull/480
* opt(ecc): jacobian doubling improvement by @mratsim in https://github.com/mratsim/constantine/pull/510
* adds nodecl to imported types by @ringabout in https://github.com/mratsim/constantine/pull/512
* Arm64 assembly by @mratsim in https://github.com/mratsim/constantine/pull/513
* Rust bindings update - includes Banderwagon by @mratsim in https://github.com/mratsim/constantine/pull/514
* upstream CI: support Apple Clang before macOS 15, fix #516 by @mratsim in https://github.com/mratsim/constantine/pull/517
* Add RIPEMD160 hash function and EVM precompile by @Vindaar in https://github.com/mratsim/constantine/pull/505
* Add `ECRecover` EVM precompile by @Vindaar in https://github.com/mratsim/constantine/pull/504
* SHA256 ARM64 hardware accel:  6.4x acceleration (Apple Silicon only) by @mratsim in https://github.com/mratsim/constantine/pull/518
* eip2537: repricing by @mratsim in https://github.com/mratsim/constantine/pull/493
* update Ethereum benches  by @mratsim in https://github.com/mratsim/constantine/pull/520
* CI: Test on MacOS and Linux ARM64 / Aarch64 by @mratsim in https://github.com/mratsim/constantine/pull/524

## New Contributors
* @ringabout made their first contribution in https://github.com/mratsim/constantine/pull/459
* @DaniPopes made their first contribution in https://github.com/mratsim/constantine/pull/500
* @Richa-iitr made their first contribution in https://github.com/mratsim/constantine/pull/477

**Full Changelog**: https://github.com/mratsim/constantine/compare/v0.1.0...v0.2.0