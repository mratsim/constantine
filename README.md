# Constantine - Constant Time Elliptic Curve Cryptography

[![License: Apache](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](https://opensource.org/licenses/Apache-2.0)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](https://opensource.org/licenses/MIT)
![Stability: experimental](https://img.shields.io/badge/stability-experimental-orange.svg)\
![Github Actions CI](https://github.com/mratsim/constantine/workflows/Constantine%20CI/badge.svg)\
[![Build Status: Travis](https://img.shields.io/travis/com/mratsim/constantine/master?label=Travis%20%28Linux%20x86_64%2FARM64%2FPowerPC64,%20MacOS%20x86_64%29)](https://travis-ci.com/mratsim/constantine)\
[![Build Status: Azure](https://img.shields.io/azure-devops/build/numforge/07a2a7a5-995a-45d3-acd5-f5456fe7b04d/4?label=Azure%20%28Linux%2032%2F64-bit%2C%20Windows%2032%2F64-bit%2C%20MacOS%2064-bit%29)](https://dev.azure.com/numforge/Constantine/_build?definitionId=4&branchName=master)

This library provides constant-time implementation of elliptic curve cryptography.

The implementation is accompanied with SAGE code used as reference implementation and test vectors generators before high speed implementation.

> The library is in development state and high-level wrappers or example protocols are not available yet.

## Target audience

The library aims to be a portable, compact and hardened library for elliptic curve cryptography needs, in particular for blockchain protocols and zero-knowledge proofs system.

The library focuses on following properties:
- constant-time (not leaking secret data via side-channels)
- performance
- generated code size, datatype size and stack usage

in this order

## Installation

You can install the developement version of the library through nimble with the following command
```
nimble install https://github.com/mratsim/constantine@#master
```

For speed it is recommended to prefer Clang, MSVC or ICC over GCC (see [Compiler-caveats](#Compiler-caveats)).

Further if using GCC, GCC 7 at minimum is required, previous versions
generated incorrect add-with-carry code.

On x86-64, inline assembly is used to workaround compilers having issues optimizing large integer arithmetic,
and also ensure constant-time code.
This can be deactivated with `"-d:ConstantineASM=false"`:
- at a significant performance cost with GCC (~50% slower than Clang).
- at misssed opportunity on recent CPUs that support MULX/ADCX/ADOX instructions (~60% faster than Clang).
- There is a 2.4x perf ratio between using plain GCC vs GCC with inline assembly.

## Curves supported

At the moment the following curves are supported, adding a new curve only requires adding the prime modulus
and its bitsize in [constantine/config/curves.nim](constantine/config/curves_declaration.nim).

The following curves are configured:

### ECDH / ECDSA / EdDSA curves

WIP:
- NIST P-224
- Curve25519
- NIST P-256 / Secp256r1
- Secp256k1 (Bitcoin, Ethereum 1)

### Pairing-Friendly curves

Supports:
- [x] Field arithmetics
- [x] Curve arithmetic
- [x] Pairing
- [ ] Multi-Pairing
- [ ] Hash-To-Curve

Families:
- BN: Barreto-Naehrig
- BLS: Barreto-Lynn-Scott

Curves:
- BN254_Nogami
- BN254_Snarks (Zero-Knowledge Proofs, Snarks, Starks, Zcash, Ethereum 1)
- BLS12-377 (Zexe)
- BLS12-381 (Algorand, Chia Networks, Dfinity, Ethereum 2, Filecoin, Zcash Sapling)

## Security

Hardening an implementation against all existing and upcoming attack vectors is an extremely complex task.
The library is provided as is, without any guarantees at least until:
- it gets audited
- formal proofs of correctness are produced
- formal verification of constant-time implementation is possible

Defense against common attack vectors are provided on a best effort basis.

Attackers may go to great lengths to retrieve secret data including:
- Timing the time taken to multiply on an elliptic curve
- Analysing the power usage of embedded devices
- Detecting cache misses when using lookup tables
- Memory attacks like page-faults, allocators, memory retention attacks

This is would be incomplete without mentioning that the hardware, OS and compiler
actively hinder you by:
- Hardware: sometimes not implementing multiplication in constant-time.
- OS: not providing a way to prevent memory paging to disk, core dumps, a debugger attaching to your process or a context switch (coroutines) leaking register data.
- Compiler: optimizing away your carefully crafted branchless code and leaking server secrets or optimizing away your secure erasure routine which is "useless" because at the end of the function the data is not used anymore.

A growing number of attack vectors is being collected for your viewing pleasure
at https://github.com/mratsim/constantine/wiki/Constant-time-arithmetics

### Disclaimer

Constantine's authors do their utmost to implement a secure cryptographic library
in particular against remote attack vectors like timing attacks.

Please note that Constantine is provided as-is without guarantees.
Use at your own risks.

Thorough evaluation of your threat model, the security of any cryptographic library you are considering,
and the secrets you put in jeopardy is strongly advised before putting data at risk.
The author would like to remind users that the best code can only mitigate
but not protect against human failures which are the weakest link and largest
backdoors to secrets exploited today.

### Security disclosure

TODO

## Performance

High-performance is a sought out property.
Note that security and side-channel resistance takes priority over performance.

New applications of elliptic curve cryptography like zero-knowledge proofs or
proof-of-stake based blockchain protocols are bottlenecked by cryptography.

### In blockchain

Ethereum 2 clients spent or use to spend anywhere between 30% to 99% of their processing time verifying the signatures of block validators on R&D testnets
Assuming we want nodes to handle a thousand peers, if a cryptographic pairing takes 1ms, that represents 1s of cryptography per block to sign with a target
block frequency of 1 every 6 seconds.

### In zero-knowledge proofs

According to https://medium.com/loopring-protocol/zksnark-prover-optimizations-3e9a3e5578c0
a 16-core CPU can prove 20 transfers/second or 10 transactions/second.
The previous implementation was 15x slower and one of the key optimizations
was changing the elliptic curve cryptography backend.
It had a direct implication on hardware cost and/or cloud computing resources required.

### Measuring performance

To measure the performance of Constantine

```bash
git clone https://github.com/mratsim/constantine
nimble bench_fp             # Using default compiler + Assembly
nimble bench_fp_clang       # Using Clang + Assembly (recommended)
nimble bench_fp_gcc         # Using GCC + Assembly (very slow)
nimble bench_fp_clang_noasm # Using Clang only
nimble bench_fp_gcc         # Using GCC only (slowest)
nimble bench_fp2
# ...
nimble bench_ec_g1
nimble bench_ec_g2
nimble bench_pairing_bn254_nogami
nimble bench_pairing_bn254_snarks
nimble bench_pairing_bls12_377
nimble bench_pairing_bls12_381
```

"Unsafe" lines uses a non-constant-time algorithm.

As mentioned in the [Compiler caveats](#compiler-caveats) section, GCC is up to 2x slower than Clang due to mishandling of carries and register usage.

On my machine i9-9980XE, for selected benchmarks with Clang + Assembly

```
---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
Line double                                                  BLS12_381            649350.649 ops/s          1540 ns/op          4617 CPU cycles (approx)
Line add                                                     BLS12_381            482858.522 ops/s          2071 ns/op          6211 CPU cycles (approx)
Mul 𝔽p12 by line xy000z                                      BLS12_381            543478.261 ops/s          1840 ns/op          5518 CPU cycles (approx)
---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
Final Exponentiation Easy                                    BLS12_381             39411.973 ops/s         25373 ns/op         76119 CPU cycles (approx)
Final Exponentiation Hard BLS12                              BLS12_381              2141.603 ops/s        466940 ns/op       1400833 CPU cycles (approx)
---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
Miller Loop BLS12                                            BLS12_381              2731.576 ops/s        366089 ns/op       1098278 CPU cycles (approx)
Final Exponentiation BLS12                                   BLS12_381              2033.045 ops/s        491873 ns/op       1475634 CPU cycles (approx)
---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
Pairing BLS12                                                BLS12_381              1131.391 ops/s        883868 ns/op       2651631 CPU cycles (approx)
---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
```

```
---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
EC Add G1                                                    ECP_SWei_Proj[Fp[BLS12_381]]                 2118644.068 ops/s           472 ns/op          1416 CPU cycles (approx)
EC Mixed Addition G1                                         ECP_SWei_Proj[Fp[BLS12_381]]                 2439024.390 ops/s           410 ns/op          1232 CPU cycles (approx)
EC Double G1                                                 ECP_SWei_Proj[Fp[BLS12_381]]                 3448275.862 ops/s           290 ns/op           871 CPU cycles (approx)
---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
EC ScalarMul G1 (unsafe reference DoubleAdd)                 ECP_SWei_Proj[Fp[BLS12_381]]                    7147.094 ops/s        139917 ns/op        419756 CPU cycles (approx)
---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
EC ScalarMul Generic G1 (window = 2, scratchsize = 4)        ECP_SWei_Proj[Fp[BLS12_381]]                    5048.975 ops/s        198060 ns/op        594188 CPU cycles (approx)
EC ScalarMul Generic G1 (window = 3, scratchsize = 8)        ECP_SWei_Proj[Fp[BLS12_381]]                    7148.269 ops/s        139894 ns/op        419685 CPU cycles (approx)
EC ScalarMul Generic G1 (window = 4, scratchsize = 16)       ECP_SWei_Proj[Fp[BLS12_381]]                    8112.735 ops/s        123263 ns/op        369791 CPU cycles (approx)
EC ScalarMul Generic G1 (window = 5, scratchsize = 32)       ECP_SWei_Proj[Fp[BLS12_381]]                    8464.534 ops/s        118140 ns/op        354424 CPU cycles (approx)
---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
EC ScalarMul G1 (endomorphism accelerated)                   ECP_SWei_Proj[Fp[BLS12_381]]                    9679.418 ops/s        103312 ns/op        309939 CPU cycles (approx)
EC ScalarMul Window-2 G1 (endomorphism accelerated)          ECP_SWei_Proj[Fp[BLS12_381]]                   13089.348 ops/s         76398 ns/op        229195 CPU cycles (approx)
---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
```




### Compiler caveats

Unfortunately compilers and in particular GCC are not very good at optimizing big integers and/or cryptographic code even when using intrinsics like `addcarry_u64`.

Compilers with proper support of `addcarry_u64` like Clang, MSVC and ICC
may generate code up to 20~25% faster than GCC.

This is explained by the GMP team: https://gmplib.org/manual/Assembly-Carry-Propagation.html
and can be reproduced with the following C code.

See https://gcc.godbolt.org/z/2h768y
```C
#include <stdint.h>
#include <x86intrin.h>

void add256(uint64_t a[4], uint64_t b[4]){
  uint8_t carry = 0;
  for (int i = 0; i < 4; ++i)
    carry = _addcarry_u64(carry, a[i], b[i], &a[i]);
}
```

GCC
```asm
add256:
        movq    (%rsi), %rax
        addq    (%rdi), %rax
        setc    %dl
        movq    %rax, (%rdi)
        movq    8(%rdi), %rax
        addb    $-1, %dl
        adcq    8(%rsi), %rax
        setc    %dl
        movq    %rax, 8(%rdi)
        movq    16(%rdi), %rax
        addb    $-1, %dl
        adcq    16(%rsi), %rax
        setc    %dl
        movq    %rax, 16(%rdi)
        movq    24(%rsi), %rax
        addb    $-1, %dl
        adcq    %rax, 24(%rdi)
        ret
```

Clang
```asm
add256:
        movq    (%rsi), %rax
        addq    %rax, (%rdi)
        movq    8(%rsi), %rax
        adcq    %rax, 8(%rdi)
        movq    16(%rsi), %rax
        adcq    %rax, 16(%rdi)
        movq    24(%rsi), %rax
        adcq    %rax, 24(%rdi)
        retq
```

As a workaround key procedures use inline assembly.

### Inline assembly

While using intrinsics significantly improve code readability, portability, auditability and maintainability,
Constantine use inline assembly on x86-64 to ensure performance portability despite poor optimization (for GCC)
and also to use dedicated large integer instructions MULX, ADCX, ADOX that compilers cannot generate.

The speed improvement on finite field arithmetic is up 60% with MULX, ADCX, ADOX on BLS12-381 (6 limbs).

## Sizes: code size, stack usage

Thanks to 10x smaller key sizes for the same security level as RSA, elliptic curve cryptography
is widely used on resource-constrained devices.

Constantine is actively optimize for code-size and stack usage.
Constantine does not use heap allocation.

At the moment Constantine is optimized for 32-bit and 64-bit CPUs.

When performance and code size conflicts, a careful and informed default is chosen.
In the future, a compile-time flag that goes beyond the compiler `-Os` might be provided.

### Example tradeoff

Unrolling Montgomery Multiplication brings about 15% performance improvement
which translate to ~15% on all operations in Constantine as field multiplication bottlenecks
all cryptographic primitives.
This is considered a worthwhile tradeoff on all but the most constrained CPUs
with those CPUs probably being 8-bit or 16-bit.

## License

Licensed and distributed under either of

* MIT license: [LICENSE-MIT](LICENSE-MIT) or http://opensource.org/licenses/MIT

or

* Apache License, Version 2.0, ([LICENSE-APACHEv2](LICENSE-APACHEv2) or http://www.apache.org/licenses/LICENSE-2.0)

at your option. This file may not be copied, modified, or distributed except according to those terms.

This library has **no external dependencies**.
In particular GMP is used only for testing and differential fuzzing
and is not linked in the library.
