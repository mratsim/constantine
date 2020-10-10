# Constantine - Constant Time Pairing-Based & Elliptic Curve Cryptography

[![License: Apache](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](https://opensource.org/licenses/Apache-2.0)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](https://opensource.org/licenses/MIT)
![Stability: experimental](https://img.shields.io/badge/stability-experimental-orange.svg)\
![Github Actions CI](https://github.com/mratsim/constantine/workflows/Constantine%20CI/badge.svg)\
[![Build Status: Travis](https://img.shields.io/travis/com/mratsim/constantine/master?label=Travis%20%28Linux%20x86_64%2FARM64%2FPowerPC64,%20MacOS%20x86_64%29)](https://travis-ci.com/mratsim/constantine)\
[![Build Status: Azure](https://img.shields.io/azure-devops/build/numforge/07a2a7a5-995a-45d3-acd5-f5456fe7b04d/4?label=Azure%20%28Linux%2032%2F64-bit%2C%20Windows%2032%2F64-bit%2C%20MacOS%2064-bit%29)](https://dev.azure.com/numforge/Constantine/_build?definitionId=4&branchName=master)

This library provides [constant-time](https://en.wikipedia.org/wiki/Side-channel_attack) implementation of elliptic curve cryptography
with a particular focus on pairing-based cryptography.

The implementations are accompanied with SAGE code used as reference implementation and test vectors generators before writing highly optimized routines implemented in the [Nim language](https://nim-lang.org/)

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

## Why Nim

The Nim language offers the following benefits for cryptography:
- Compilation to machine code via C or C++ or alternatively compilation to Javascript. Easy FFI to those languages.
  - Obscure embedded devices with proprietary C compilers can be targeted.
  - WASM can be targeted.
- Performance reachable in C is reachable in Nim, easily.
- Rich type system: generics, dependent types, mutability-tracking and side-effect analysis, borrow-checking, compiler enforced distinct types (Miles != Meters, SecretBool != bool and SecretWord != uint64).
- Compile-time evaluation, including parsing hex string, converting them to BigInt or Finite Field elements and doing bigint operations.
- Assembly support either inline or ``__attribute__((naked))`` or a simple `{.compile: "myasm.S".}` away
- No GC if no GC-ed types are used (automatic memory management is set at the type level and optimized for latency/soft-realtime by default and can be totally deactivated).
- Procedural macros working directly on AST to
  - create generic curve configuration,
  - derive constants
  - write a size-independent inline assembly code generator
- Upcoming proof system for formal verification via Z3 ([DrNim](https://nim-lang.org/docs/drnim.html), [Correct-by-Construction RFC](https://github.com/nim-lang/RFCs/issues/222))

## Curves supported

At the moment the following curves are supported, adding a new curve only requires adding the prime modulus
and its bitsize in [constantine/config/curves.nim](constantine/config/curves_declaration.nim).

The following curves are configured:

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
- BW6-671 (Celo, EY Blockchain) (Pairings are WIP)

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
- Compiler: optimizing away your carefully crafted branchless code and leaking server secrets or optimizing away your secure erasure routine which is deemed "useless" because at the end of the function the data is not used anymore.

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

On my machine i9-9980XE, for selected benchmarks with Clang + Assembly, all being constant-time (or tagged unsafe).

```
---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
Line double                                                  BLS12_381            872600.349 ops/s          1146 ns/op          3434 CPU cycles (approx)
Line add                                                     BLS12_381            616522.811 ops/s          1622 ns/op          4864 CPU cycles (approx)
Mul 𝔽p12 by line xy000z                                      BLS12_381            535905.681 ops/s          1866 ns/op          5597 CPU cycles (approx)
---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
Final Exponentiation Easy                                    BLS12_381             39443.064 ops/s         25353 ns/op         76058 CPU cycles (approx)
Final Exponentiation Hard BLS12                              BLS12_381              2139.367 ops/s        467428 ns/op       1402299 CPU cycles (approx)
---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
Miller Loop BLS12                                            BLS12_381              2971.512 ops/s        336529 ns/op       1009596 CPU cycles (approx)
Final Exponentiation BLS12                                   BLS12_381              2029.365 ops/s        492765 ns/op       1478310 CPU cycles (approx)
---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
Pairing BLS12                                                BLS12_381              1164.051 ops/s        859069 ns/op       2577234 CPU cycles (approx)
---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
```

```
---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
EC Add G1                                                    ECP_ShortW_Proj[Fp[BLS12_381]]               2118644.068 ops/s           472 ns/op          1416 CPU cycles (approx)
EC Add G1                                                    ECP_ShortW_Jac[Fp[BLS12_381]]                1818181.818 ops/s           550 ns/op          1652 CPU cycles (approx)
EC Mixed Addition G1                                         ECP_ShortW_Proj[Fp[BLS12_381]]               2427184.466 ops/s           412 ns/op          1236 CPU cycles (approx)
EC Double G1                                                 ECP_ShortW_Proj[Fp[BLS12_381]]               3460207.612 ops/s           289 ns/op           867 CPU cycles (approx)
EC Double G1                                                 ECP_ShortW_Jac[Fp[BLS12_381]]                3717472.119 ops/s           269 ns/op           809 CPU cycles (approx)
---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
EC Projective to Affine G1                                   ECP_ShortW_Proj[Fp[BLS12_381]]                 72020.166 ops/s         13885 ns/op         41656 CPU cycles (approx)
EC Jacobian to Affine G1                                     ECP_ShortW_Jac[Fp[BLS12_381]]                  71989.058 ops/s         13891 ns/op         41673 CPU cycles (approx)
---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
EC ScalarMul G1 (unsafe reference DoubleAdd)                 ECP_ShortW_Proj[Fp[BLS12_381]]                  7260.266 ops/s        137736 ns/op        413213 CPU cycles (approx)
EC ScalarMul G1 (unsafe reference DoubleAdd)                 ECP_ShortW_Jac[Fp[BLS12_381]]                   7140.970 ops/s        140037 ns/op        420115 CPU cycles (approx)
---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
EC ScalarMul Generic G1 (window = 2, scratchsize = 4)        ECP_ShortW_Proj[Fp[BLS12_381]]                  5036.946 ops/s        198533 ns/op        595606 CPU cycles (approx)
EC ScalarMul Generic G1 (window = 3, scratchsize = 8)        ECP_ShortW_Proj[Fp[BLS12_381]]                  7080.799 ops/s        141227 ns/op        423684 CPU cycles (approx)
EC ScalarMul Generic G1 (window = 4, scratchsize = 16)       ECP_ShortW_Proj[Fp[BLS12_381]]                  8062.631 ops/s        124029 ns/op        372091 CPU cycles (approx)
EC ScalarMul Generic G1 (window = 5, scratchsize = 32)       ECP_ShortW_Proj[Fp[BLS12_381]]                  8377.244 ops/s        119371 ns/op        358116 CPU cycles (approx)
EC ScalarMul Generic G1 (window = 2, scratchsize = 4)        ECP_ShortW_Jac[Fp[BLS12_381]]                   4703.359 ops/s        212614 ns/op        637847 CPU cycles (approx)
EC ScalarMul Generic G1 (window = 3, scratchsize = 8)        ECP_ShortW_Jac[Fp[BLS12_381]]                   6901.407 ops/s        144898 ns/op        434697 CPU cycles (approx)
EC ScalarMul Generic G1 (window = 4, scratchsize = 16)       ECP_ShortW_Jac[Fp[BLS12_381]]                   8022.720 ops/s        124646 ns/op        373940 CPU cycles (approx)
EC ScalarMul Generic G1 (window = 5, scratchsize = 32)       ECP_ShortW_Jac[Fp[BLS12_381]]                   8433.552 ops/s        118574 ns/op        355725 CPU cycles (approx)
---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
EC ScalarMul G1 (endomorphism accelerated)                   ECP_ShortW_Proj[Fp[BLS12_381]]                  9703.933 ops/s        103051 ns/op        309155 CPU cycles (approx)
EC ScalarMul Window-2 G1 (endomorphism accelerated)          ECP_ShortW_Proj[Fp[BLS12_381]]                 13160.839 ops/s         75983 ns/op        227950 CPU cycles (approx)
EC ScalarMul G1 (endomorphism accelerated)                   ECP_ShortW_Jac[Fp[BLS12_381]]                   9064.868 ops/s        110316 ns/op        330951 CPU cycles (approx)
EC ScalarMul Window-2 G1 (endomorphism accelerated)          ECP_ShortW_Jac[Fp[BLS12_381]]                  12722.484 ops/s         78601 ns/op        235806 CPU cycles (approx)
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
