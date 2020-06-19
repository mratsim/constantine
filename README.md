# Constantine - Constant Time Elliptic Curve Cryptography

[![License: Apache](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](https://opensource.org/licenses/Apache-2.0)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](https://opensource.org/licenses/MIT)
![Stability: experimental](https://img.shields.io/badge/stability-experimental-orange.svg)\
![Github Actions CI](https://github.com/mratsim/constantine/workflows/Constantine%20CI/badge.svg)\
[![Build Status: Travis](https://img.shields.io/travis/com/mratsim/constantine/master?label=Travis%20%28Linux%20x86_64%2FARM64,%20MacOS%20x86_64%29)](https://travis-ci.com/mratsim/constantine)\
[![Build Status: Azure](https://img.shields.io/azure-devops/build/numforge/07a2a7a5-995a-45d3-acd5-f5456fe7b04d/4?label=Azure%20%28Linux%2064-bit%2C%20Windows%2032%2F64-bit%2C%20MacOS%2064-bit%29)](https://dev.azure.com/numforge/Constantine/_build?definitionId=4&branchName=master)

This library provides constant-time implementation of elliptic curve cryptography.

> Warning ⚠️: The library is in development state and cannot be used at the moment
>            except as a showcase or to start a discussion on modular big integers internals.

## Installation

You can install the developement version of the library through nimble with the following command
```
nimble install https://github.com/mratsim/constantine@#master
```

For speed it is recommended to prefer Clang, MSVC or ICC over GCC.
GCC does not properly optimize add-with-carry and sub-with-borrow loops (see [Compiler-caveats](#Compiler-caveats)).

Further if using GCC, GCC 7 at minimum is required, previous versions
generated incorrect add-with-carry code.

## Target audience

The library aims to be a portable, compact and hardened library for elliptic curve cryptography needs, in particular for blockchain protocols and zero-knowledge proofs system.

The library focuses on following properties:
- constant-time (not leaking secret data via side-channels)
- performance
- generated code size, datatype size and stack usage

in this order

## Curves supported

At the moment the following curves are supported, adding a new curve only requires adding the prime modulus
and its bitsize in [constantine/config/curves.nim](constantine/config/curves.nim).

The following curves are configured:

### ECDH / ECDSA curves

- NIST P-224
- Curve25519
- NIST P-256 / Secp256r1
- Secp256k1 (Bitcoin, Ethereum 1)

### Pairing-Friendly curves

Families:
- BN: Barreto-Naerig
- BLS: Barreto-Lynn-Scott
- FKM: Fotiadis-Konstantinou-Martindale

Curves:
- BN254 (Zero-Knowledge Proofs, Snarks, Starks, Zcash, Ethereum 1)
- BLS12-377 (Zexe)
- BLS12-381 (Algorand, Chia Networks, Dfinity, Ethereum 2, Filecoin, Zcash Sapling)
- BN446
- FKM12-447
- BLS12-461
- BN462

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

## Measuring performance

To measure the performance of Constantine

```bash
git clone https://github.com/mratsim/constantine
nimble bench_fp_clang
nimble bench_fp2_clang
```

As mentioned in the [Compiler caveats](#compiler-caveats) section, GCC is up to 2x slower than Clang due to mishandling of carries and register usage.

On my machine, for selected benchmarks on the prime field for popular pairing-friendly curves.

```
⚠️ Measurements are approximate and use the CPU nominal clock: Turbo-Boost and overclocking will skew them.
==========================================================================================================

All benchmarks are using constant-time implementations to protect against side-channel attacks.

Compiled with Clang
Running on Intel(R) Core(TM) i9-9980XE CPU @ 3.00GHz (overclocked all-core Turbo @4.1GHz)

--------------------------------------------------------------------------------
Addition        Fp[BN254]               0 ns         0 cycles
Substraction    Fp[BN254]               0 ns         0 cycles
Negation        Fp[BN254]               0 ns         0 cycles
Multiplication  Fp[BN254]              21 ns        65 cycles
Squaring        Fp[BN254]              18 ns        55 cycles
Inversion       Fp[BN254]            6266 ns     18799 cycles
--------------------------------------------------------------------------------
Addition        Fp[BLS12_381]           0 ns         0 cycles
Substraction    Fp[BLS12_381]           0 ns         0 cycles
Negation        Fp[BLS12_381]           0 ns         0 cycles
Multiplication  Fp[BLS12_381]          45 ns       136 cycles
Squaring        Fp[BLS12_381]          39 ns       118 cycles
Inversion       Fp[BLS12_381]       15683 ns     47050 cycles
--------------------------------------------------------------------------------

Notes:
  GCC is significantly slower than Clang on multiprecision arithmetic.
  The simplest operations might be optimized away by the compiler.
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

### Inline assembly

Constantine uses inline assembly for a very restricted use-case: "conditional mov",
and a temporary use-case "hardware 128-bit division" that will be replaced ASAP (as hardware division is not constant-time).

Using intrinsics otherwise significantly improve code readability, portability, auditability and maintainability.

#### Future optimizations

In the future more inline assembly primitives might be added provided the performance benefit outvalues the significant complexity.
In particular, multiprecision multiplication and squaring on x86 can use the instructions MULX, ADCX and ADOX
to multiply-accumulate on 2 carry chains in parallel (with instruction-level parallelism)
and improve performance by 15~20% over an uint128-based implementation.
As no compiler is able to generate such code even when using the `_mulx_u64` and `_addcarryx_u64` intrinsics,
either the assembly for each supported bigint size must be hardcoded
or a "compiler" must be implemented in macros that will generate the required inline assembly at compile-time.

Such a compiler can also be used to overcome GCC codegen deficiencies, here is an example for add-with-carry:
https://github.com/mratsim/finite-fields/blob/d7f6d8bb/macro_add_carry.nim

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
