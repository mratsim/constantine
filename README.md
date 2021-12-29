# Constantine - Fast, compact, hardened Pairing-Based Cryptography

[![License: Apache](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](https://opensource.org/licenses/Apache-2.0)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](https://opensource.org/licenses/MIT)
![Stability: experimental](https://img.shields.io/badge/stability-experimental-orange.svg)\
[![Github Actions CI](https://github.com/mratsim/constantine/workflows/Constantine%20CI/badge.svg)](https://github.com/mratsim/constantine/actions?query=workflow%3A%22Constantine+CI%22+branch%3Amaster)\
[![Build Status: Travis](https://img.shields.io/travis/com/mratsim/constantine/master?label=Travis%20%28Linux%20ARM64%2FPowerPC64%29)](https://travis-ci.com/mratsim/constantine)\
[![Build Status: Azure](https://img.shields.io/azure-devops/build/numforge/07a2a7a5-995a-45d3-acd5-f5456fe7b04d/4?label=Azure%20%28Linux%2032%2F64-bit%2C%20Windows%2032%2F64-bit%2C%20MacOS%2064-bit%29)](https://dev.azure.com/numforge/Constantine/_build?definitionId=4&branchName=master)

> “A cryptographic system should be secure even if everything about the system, except the key, is public knowledge.”\
>   — Auguste Kerckhoffs

This library provides [constant-time](https://en.wikipedia.org/wiki/Timing_attack) implementation of elliptic curve cryptography
with a particular focus on pairing-based cryptography.

The implementations are accompanied with SAGE code used as reference implementation and test vectors generators before writing highly optimized routines implemented in the [Nim language](https://nim-lang.org/)

> The library is in development state and high-level wrappers or example protocols are not available yet.

## Target audience

The library aims to be a fast, compact and hardened library for elliptic curve cryptography needs, in particular for blockchain protocols and zero-knowledge proofs system.

The library focuses on following properties:
- constant-time (not leaking secret data via [side-channels](https://en.wikipedia.org/wiki/Side-channel_attack))
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
This can be deactivated with `"-d:CttASM=false"`:
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
- [x] Multi-Pairing
- [x] Hash-To-Curve

Families:
- BN: Barreto-Naehrig
- BLS: Barreto-Lynn-Scott

Curves:
- BN254_Nogami
- BN254_Snarks (Zero-Knowledge Proofs, Snarks, Starks, Zcash, Ethereum 1)
- BLS12-377 (Zexe)
- BLS12-381 (Algorand, Chia Networks, Dfinity, Ethereum 2, Filecoin, Zcash Sapling)
- BW6-671 (Celo, EY Blockchain) (Pairings are WIP)\
  BLS12-377 is embedded in BW6-761 for one layer proof composition in zk-SNARKS.

### Other curves

- Curve25519, used in ed25519 and X25519 from TLS 1.3 protocol and the Signal protocol.
  With Ristretto, it can be used in bulletproofs.
- Jubjub, a curve embedded in BLS12-381 scalar field to be used in zk-SNARKS circuits.
- Bandersnatch, a more efficient curve embedded in BLS12-381 scalar field to be used in zk-SNARKS circuits.
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
nimble bench_fp_gcc         # Using GCC + Assembly (decent)
nimble bench_fp_clang_noasm # Using Clang only (acceptable)
nimble bench_fp_gcc         # Using GCC only (slowest)
nimble bench_fp2
# ...
nimble bench_ec_g1
nimble bench_ec_g2
nimble bench_pairing_bn254_nogami
nimble bench_pairing_bn254_snarks
nimble bench_pairing_bls12_377
nimble bench_pairing_bls12_381

# And per-curve summaries
nimble bench_summary_bn254_nogami
nimble bench_summary_bn254_snarks
nimble bench_summary_bls12_377
nimble bench_summary_bls12_381
```

As mentioned in the [Compiler caveats](#compiler-caveats) section, GCC is up to 2x slower than Clang due to mishandling of carries and register usage.

On my machine i9-9980XE (overclocked @ 3.9 GHz, nominal clock 3.0 GHz), for Clang + Assembly, **all being constant-time** (including scalar multiplication, square root and inversion).

#### BN254_Snarks (Clang + inline assembly)

```
--------------------------------------------------------------------------------------------------------------------------------------------------------
Multiplication                      Fr[BN254_Snarks]                            66666666.667 ops/s            15 ns/op            47 CPU cycles (approx)
Squaring                            Fr[BN254_Snarks]                            71428571.429 ops/s            14 ns/op            42 CPU cycles (approx)
--------------------------------------------------------------------------------------------------------------------------------------------------------
Multiplication                      Fp[BN254_Snarks]                            66666666.667 ops/s            15 ns/op            47 CPU cycles (approx)
Squaring                            Fp[BN254_Snarks]                            71428571.429 ops/s            14 ns/op            42 CPU cycles (approx)
Inversion                           Fp[BN254_Snarks]                              189537.528 ops/s          5276 ns/op         15828 CPU cycles (approx)
Square Root + isSquare              Fp[BN254_Snarks]                              189358.076 ops/s          5281 ns/op         15843 CPU cycles (approx)
--------------------------------------------------------------------------------------------------------------------------------------------------------
Multiplication                      Fp2[BN254_Snarks]                           18867924.528 ops/s            53 ns/op           160 CPU cycles (approx)
Squaring                            Fp2[BN254_Snarks]                           25641025.641 ops/s            39 ns/op           119 CPU cycles (approx)
Inversion                           Fp2[BN254_Snarks]                             186776.242 ops/s          5354 ns/op         16064 CPU cycles (approx)
Square Root + isSquare              Fp2[BN254_Snarks]                              92790.201 ops/s         10777 ns/op         32332 CPU cycles (approx)
--------------------------------------------------------------------------------------------------------------------------------------------------------
EC Add G1                           ECP_ShortW_Prj[Fp[BN254_Snarks]]             3731343.284 ops/s           268 ns/op           806 CPU cycles (approx)
EC Mixed Addition G1                ECP_ShortW_Prj[Fp[BN254_Snarks]]             3952569.170 ops/s           253 ns/op           761 CPU cycles (approx)
EC Double G1                        ECP_ShortW_Prj[Fp[BN254_Snarks]]             6024096.386 ops/s           166 ns/op           500 CPU cycles (approx)
EC ScalarMul 254-bit G1             ECP_ShortW_Prj[Fp[BN254_Snarks]]               23140.113 ops/s         43215 ns/op        129647 CPU cycles (approx)
--------------------------------------------------------------------------------------------------------------------------------------------------------
EC Add G1                           ECP_ShortW_Jac[Fp[BN254_Snarks]]             2985074.627 ops/s           335 ns/op          1005 CPU cycles (approx)
EC Mixed Addition G1                ECP_ShortW_Jac[Fp[BN254_Snarks]]             4184100.418 ops/s           239 ns/op           718 CPU cycles (approx)
EC Double G1                        ECP_ShortW_Jac[Fp[BN254_Snarks]]             6410256.410 ops/s           156 ns/op           469 CPU cycles (approx)
EC ScalarMul 254-bit G1             ECP_ShortW_Jac[Fp[BN254_Snarks]]               21458.307 ops/s         46602 ns/op        139809 CPU cycles (approx)
--------------------------------------------------------------------------------------------------------------------------------------------------------
EC Add G2                           ECP_ShortW_Prj[Fp2[BN254_Snarks]]            1061571.125 ops/s           942 ns/op          2826 CPU cycles (approx)
EC Mixed Addition G2                ECP_ShortW_Prj[Fp2[BN254_Snarks]]            1183431.953 ops/s           845 ns/op          2536 CPU cycles (approx)
EC Double G2                        ECP_ShortW_Prj[Fp2[BN254_Snarks]]            1821493.625 ops/s           549 ns/op          1649 CPU cycles (approx)
EC ScalarMul 254-bit G2             ECP_ShortW_Prj[Fp2[BN254_Snarks]]               9259.602 ops/s        107996 ns/op        323995 CPU cycles (approx)
--------------------------------------------------------------------------------------------------------------------------------------------------------
EC Add G2                           ECP_ShortW_Jac[Fp2[BN254_Snarks]]            1092896.175 ops/s           915 ns/op          2747 CPU cycles (approx)
EC Mixed Addition G2                ECP_ShortW_Jac[Fp2[BN254_Snarks]]            1577287.066 ops/s           634 ns/op          1904 CPU cycles (approx)
EC Double G2                        ECP_ShortW_Jac[Fp2[BN254_Snarks]]            2570694.087 ops/s           389 ns/op          1167 CPU cycles (approx)
EC ScalarMul 254-bit G2             ECP_ShortW_Jac[Fp2[BN254_Snarks]]              10358.615 ops/s         96538 ns/op        289621 CPU cycles (approx)
--------------------------------------------------------------------------------------------------------------------------------------------------------
Multiplication                      Fp12[BN254_Snarks]                            691085.003 ops/s          1447 ns/op          4342 CPU cycles (approx)
Squaring                            Fp12[BN254_Snarks]                            893655.049 ops/s          1119 ns/op          3357 CPU cycles (approx)
Inversion                           Fp12[BN254_Snarks]                            121876.904 ops/s          8205 ns/op         24617 CPU cycles (approx)
--------------------------------------------------------------------------------------------------------------------------------------------------------
Miller Loop BN                      BN254_Snarks                                    4635.102 ops/s        215745 ns/op        647249 CPU cycles (approx)
Final Exponentiation BN             BN254_Snarks                                    4011.038 ops/s        249312 ns/op        747950 CPU cycles (approx)
Pairing BN                          BN254_Snarks                                    2158.047 ops/s        463382 ns/op       1390175 CPU cycles (approx)
--------------------------------------------------------------------------------------------------------------------------------------------------------
```

#### BLS12_381 (Clang + inline Assembly)

```
--------------------------------------------------------------------------------------------------------------------------------------------------------
Multiplication                      Fr[BLS12_381]                               66666666.667 ops/s            15 ns/op            47 CPU cycles (approx)
Squaring                            Fr[BLS12_381]                               71428571.429 ops/s            14 ns/op            43 CPU cycles (approx)
--------------------------------------------------------------------------------------------------------------------------------------------------------
Multiplication                      Fp[BLS12_381]                               35714285.714 ops/s            28 ns/op            84 CPU cycles (approx)
Squaring                            Fp[BLS12_381]                               35714285.714 ops/s            28 ns/op            84 CPU cycles (approx)
Inversion                           Fp[BLS12_381]                                  70131.145 ops/s         14259 ns/op         42780 CPU cycles (approx)
Square Root + isSquare              Fp[BLS12_381]                                  69793.412 ops/s         14328 ns/op         42986 CPU cycles (approx)
--------------------------------------------------------------------------------------------------------------------------------------------------------
Multiplication                      Fp2[BLS12_381]                              10526315.789 ops/s            95 ns/op           287 CPU cycles (approx)
Squaring                            Fp2[BLS12_381]                              14084507.042 ops/s            71 ns/op           213 CPU cycles (approx)
Inversion                           Fp2[BLS12_381]                                 69376.995 ops/s         14414 ns/op         43242 CPU cycles (approx)
Square Root + isSquare              Fp2[BLS12_381]                                 34526.810 ops/s         28963 ns/op         86893 CPU cycles (approx)
--------------------------------------------------------------------------------------------------------------------------------------------------------
EC Add G1                           ECP_ShortW_Prj[Fp[BLS12_381]]                2127659.574 ops/s           470 ns/op          1412 CPU cycles (approx)
EC Mixed Addition G1                ECP_ShortW_Prj[Fp[BLS12_381]]                2415458.937 ops/s           414 ns/op          1243 CPU cycles (approx)
EC Double G1                        ECP_ShortW_Prj[Fp[BLS12_381]]                3412969.283 ops/s           293 ns/op           881 CPU cycles (approx)
EC ScalarMul 255-bit G1             ECP_ShortW_Prj[Fp[BLS12_381]]                  13218.596 ops/s         75651 ns/op        226959 CPU cycles (approx)
--------------------------------------------------------------------------------------------------------------------------------------------------------
EC Add G1                           ECP_ShortW_Jac[Fp[BLS12_381]]                1757469.244 ops/s           569 ns/op          1708 CPU cycles (approx)
EC Mixed Addition G1                ECP_ShortW_Jac[Fp[BLS12_381]]                2433090.024 ops/s           411 ns/op          1235 CPU cycles (approx)
EC Double G1                        ECP_ShortW_Jac[Fp[BLS12_381]]                3636363.636 ops/s           275 ns/op           826 CPU cycles (approx)
EC ScalarMul 255-bit G1             ECP_ShortW_Jac[Fp[BLS12_381]]                  12390.499 ops/s         80707 ns/op        242126 CPU cycles (approx)
--------------------------------------------------------------------------------------------------------------------------------------------------------
EC Add G2                           ECP_ShortW_Prj[Fp2[BLS12_381]]                710227.273 ops/s          1408 ns/op          4225 CPU cycles (approx)
EC Mixed Addition G2                ECP_ShortW_Prj[Fp2[BLS12_381]]                800640.512 ops/s          1249 ns/op          3748 CPU cycles (approx)
EC Double G2                        ECP_ShortW_Prj[Fp2[BLS12_381]]               1179245.283 ops/s           848 ns/op          2545 CPU cycles (approx)
EC ScalarMul 255-bit G2             ECP_ShortW_Prj[Fp2[BLS12_381]]                  6179.171 ops/s        161834 ns/op        485514 CPU cycles (approx)
--------------------------------------------------------------------------------------------------------------------------------------------------------
EC Add G2                           ECP_ShortW_Jac[Fp2[BLS12_381]]                631711.939 ops/s          1583 ns/op          4751 CPU cycles (approx)
EC Mixed Addition G2                ECP_ShortW_Jac[Fp2[BLS12_381]]                900900.901 ops/s          1110 ns/op          3332 CPU cycles (approx)
EC Double G2                        ECP_ShortW_Jac[Fp2[BLS12_381]]               1501501.502 ops/s           666 ns/op          1999 CPU cycles (approx)
EC ScalarMul 255-bit G2             ECP_ShortW_Jac[Fp2[BLS12_381]]                  6067.519 ops/s        164812 ns/op        494446 CPU cycles (approx)
--------------------------------------------------------------------------------------------------------------------------------------------------------
Multiplication                      Fp12[BLS12_381]                               504540.868 ops/s          1982 ns/op          5949 CPU cycles (approx)
Squaring                            Fp12[BLS12_381]                               688231.246 ops/s          1453 ns/op          4360 CPU cycles (approx)
Inversion                           Fp12[BLS12_381]                                54279.976 ops/s         18423 ns/op         55271 CPU cycles (approx)
--------------------------------------------------------------------------------------------------------------------------------------------------------
Miller Loop BLS12                   BLS12_381                                       3856.953 ops/s        259272 ns/op        777833 CPU cycles (approx)
Final Exponentiation BLS12          BLS12_381                                       2526.465 ops/s        395810 ns/op       1187454 CPU cycles (approx)
Pairing BLS12                       BLS12_381                                       1548.870 ops/s        645632 ns/op       1936937 CPU cycles (approx)
--------------------------------------------------------------------------------------------------------------------------------------------------------
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
