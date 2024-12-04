# Constantine

[![License: Apache](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](https://opensource.org/licenses/Apache-2.0)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](https://opensource.org/licenses/MIT)
![Stability: experimental](https://img.shields.io/badge/stability-experimental-orange.svg)\
[![Github Actions CI](https://github.com/mratsim/constantine/workflows/Constantine%20CI/badge.svg)](https://github.com/mratsim/constantine/actions?query=workflow%3A%22Constantine+CI%22+branch%3Amaster)

_Constantine: High performance cryptography for proof systems and blockchain protocols_

> “A cryptographic system should be secure even if everything about the system, except the key, is public knowledge.”\
>   — Auguste Kerckhoffs

This library provides [constant-time](https://en.wikipedia.org/wiki/Timing_attack) implementation of cryptographic primitives
with a particular focus on cryptography used in blockchains and zero-knowledge proof systems.

<!-- TOC -->

- [Constantine](#constantine)
  - [Public API: Curves \& Protocols](#public-api-curves--protocols)
    - [Protocols](#protocols)
    - [Elliptic Curves](#elliptic-curves)
    - [General cryptography](#general-cryptography)
    - [Threadpool](#threadpool)
  - [Installation](#installation)
    - [From Rust](#from-rust)
    - [From Go](#from-go)
    - [From C](#from-c)
    - [From Nim](#from-nim)
  - [Dependencies \& Requirements](#dependencies--requirements)
  - [Performance](#performance)
  - [Assembly \& Hardware acceleration](#assembly--hardware-acceleration)
  - [Security](#security)
    - [Disclaimer](#disclaimer)
    - [Security disclosure](#security-disclosure)
  - [Why Nim](#why-nim)
  - [License](#license)

<!-- /TOC -->
The library aims to be a fast, compact and hardened library for elliptic curve cryptography needs, in particular for blockchain protocols and zero-knowledge proofs system.

The library focuses on following properties:
- constant-time (not leaking secret data via [side-channels](https://en.wikipedia.org/wiki/Side-channel_attack))
- performance
- generated code size, datatype size and stack usage

in this order.

## Public API: Curves & Protocols

Protocols are a set of routines, designed for specific goals or a combination thereof:
- confidentiality: only the intended receiver of a message can read it
- authentication: the other party in the communication is the expected part
- integrity: the received message has not been tampered with
- non-repudiation: the sender of a message cannot repudiated it

**Legend**

- :white_check_mark:: Full support
- :building_construction:: Partial support:
  - in C, some APIs not provided.
  - in Rust, only low-level constantine-sys API available but no high-level wrapper.
- :see_no_evil:: Missing support

### Protocols

Constantine supports the following protocols in its public API.

|                                                                        |           Nim           |         C          | Rust               |         Go         |
|------------------------------------------------------------------------|:-----------------------:|:------------------:|--------------------|:------------------:|
| Ethereum BLS signatures                                                |   :white_check_mark:    | :white_check_mark: | :white_check_mark: | :white_check_mark: |
| Ethereum KZG commitments for EIP-4844                                  |   :white_check_mark:    | :white_check_mark: | :white_check_mark: | :white_check_mark: |
| Ethereum IPA commitments for Verkle Tries                              | :building_construction: |   :see_no_evil:    | :see_no_evil:      |   :see_no_evil:    |
| Ethereum Virtual Machine BN254 Precompiles ECADD, ECMUL, ECPAIRING     |   :white_check_mark:    | :white_check_mark: | :white_check_mark: | :white_check_mark: |
| EVM BLS12-381 precompiles (EIP-2537)                                   |   :white_check_mark:    | :white_check_mark: | :white_check_mark: | :white_check_mark: |
| EVM Misc: SHA256, modexp                                               |   :white_check_mark:    | :white_check_mark: | :white_check_mark: | :white_check_mark: |
| Zk Accel layer for Halo2 proof system (experimental)                   |     not applicable      |   not applicable   | :white_check_mark: |   not applicable   |

### Elliptic Curves

Constantine supports the following curves in its public API.

|                               |        Nim         |         C          | Rust               |      Go       |
|-------------------------------|:------------------:|:------------------:|--------------------|:-------------:|
| BN254-Snarks                  | :white_check_mark: | :white_check_mark: | :white_check_mark: | :see_no_evil: |
| BLS12-381                     | :white_check_mark: | :white_check_mark: | :white_check_mark: | :see_no_evil: |
| Pasta curves (Pallas & Vesta) | :white_check_mark: | :white_check_mark: | :white_check_mark: | :see_no_evil: |

For all elliptic curves, the following arithmetic is supported
  - field arithmetic
    - on Fr (i.e. modulo the 255-bit curve order)
    - on Fp (i.e. modulo the 381-bit prime modulus)
  - elliptic curve arithmetic:
    - on elliptic curve over Fp (EC 𝔾₁) with affine, jacobian and homogenous projective coordinates
    - on elliptic curve over Fp2 (EC 𝔾₂) with affine, jacobian and homogenous projective coordinates
    - including scalar multiplication, multi-scalar-multiplication (MSM) and parallel MSM

_All operations are constant-time unless explicitly mentioned_ vartime.

For pairing-friendly curves Fp2 arithmetic is also exposed.\
:building_construction: Pairings and multi-pairings are implemented but not exposed yet.

### General cryptography

Constantine supports the following hash functions and CSPRNGs in its public API.

|                                                              |        Nim         |         C          | Rust                    |         Go         |
|--------------------------------------------------------------|:------------------:|:------------------:|-------------------------|:------------------:|
| SHA256                                                       | :white_check_mark: | :white_check_mark: | :white_check_mark:      | :white_check_mark: |
| Cryptographically-secure RNG from Operating System (sysrand) | :white_check_mark: | :white_check_mark: | :white_check_mark:      | :white_check_mark: |

### Threadpool

Constantine also exposes a high-performance threadpool for Nim that inherits performance and API from:
- Task parallelism API RFC: https://github.com/nim-lang/RFCs/issues/347
  + Weave data parallelism API:
    - `spawn` and `sync`
    - `parallelFor` and `syncScope`
        - `parallelFor` supports arbitrarily complex reduction.
        Constantine uses it extensively for parallel elliptic curve sum reductions.
    - `isSpawned` and `isReady`
- CPU Topology - Query the number of threads available at the OS/VM-level to run computations:
  - `ctt_cpu_get_num_threads_os` in C
  - `getNumThreadsOS` in Nim
  - `constantine_core::hardware::get_num_threads_os` in Rust

- https://github.com/mratsim/weave
- https://github.com/status-im/nim-taskpools

The threadpool supports nested parallelism to exploit high core counts and does not suffer from OpenMP limitations of nested parallel loops. For batching KZG verification, Constantine issues 3 multi-scalar multiplication in parallel, each using at 3 nested parallel loops.

See the following documents on the threadpool performance details, design and research:
- [./README-PERFORMANCE.md#parallelism](./README-PERFORMANCE.md#parallelism)
- [./docs/threadpool-design.md](./docs/threadpool-design.md)
- https://github.com/mratsim/weave/tree/7682784/research

## Installation

> [!IMPORTANT]
> Constantine can be compiled with:
> - Nim v2.2.0

### From Rust

1. Install ``clang`` compiler, for example:
    - Debian/Ubuntu `sudo apt update && sudo apt install build-essential clang`
    - Archlinux `pacman -S base-devel clang`

    > [!TIP]
    > We require Clang as it's significantly more performant than GCC for cryptographic code, especially for ARM where Constantine has no assembly optimizations. And Rust, like Clang both rely on LLVM.<br />This can be changed to any C compiler by deleting [this line](https://github.com/mratsim/constantine/blob/8991b16/constantine-rust/constantine-sys/build.rs#L17).

2. Install nim, it is available in most distros package manager for Linux and Homebrew for MacOS
   Windows binaries are on the official website: https://nim-lang.org/install_unix.html
    - Debian/Ubuntu `sudo apt install nim`
    - Archlinux `pacman -S nim`

3. Test both:
    - the experimental ZK Accel API (ZAL) for Halo2-KZG
    - Ethereum EIP4844 KZG polynomial commitments
    ```
    git clone https://github.com/mratsim/constantine
    cd constantine
    cargo test
    cargo bench
    ```

4. Add Constantine as a dependency in Cargo.toml
    - for Halo2-KZG Zk Accel Layer
        ```toml
        [dependencies]
        constantine-halo2-zal = { git = 'https://github.com/mratsim/constantine' }
        ```
    - for Ethereum EIP-4844 KZG polynomial commitments
        ```toml
        [dependencies]
        constantine-ethereum-kzg = { git = 'https://github.com/mratsim/constantine' }
        ```

Optionally, cross-language LTO between Nim and Rust can be used, see https://doc.rust-lang.org/rustc/linker-plugin-lto.html:

Add a `.cargo/config.toml` to your project with the following:
```toml
# .cargo/config.toml

[build]
rustflags="-Clinker-plugin-lto -Clinker=clang -Clink-arg=-fuse-ld=lld"
```

and modify Constantine's [`build.rs`](https://github.com/mratsim/constantine/blob/8991b16/constantine-rust/constantine-sys/build.rs#L16-L17) to pass `CTT_LTO=1`
```Rust
    Command::new("nimble")
        .env("CC", "clang")
        .env("CTT_LTO", "1") // <--
        .arg("make_lib_rust")
        .current_dir(root_dir)
        .stdout(Stdio::inherit())
        .stderr(Stdio::inherit())
        .status()
        .expect("failed to execute process");
```

### From Go


1. Install any C compiler, `clang` is recommended, for example:
    - Debian/Ubuntu `sudo apt update && sudo apt install build-essential clang`
    - Archlinux `pacman -S base-devel clang`

2. Install nim, it is available in most distros package manager for Linux and Homebrew for MacOS
   Windows binaries are on the official website: https://nim-lang.org/install_unix.html
    - Debian/Ubuntu `sudo apt install nim`
    - Archlinux `pacman -S nim`

3. Compile Constantine as a static (and shared) library in `./include`
    ```
    cd constantine
    CC=clang nimble make_lib
    ```

3. Test the go API.
    ```
    cd constantine-go
    go test -modfile=../go_test.mod
    ```
    > [!IMPORTANT]
    > Constantine uses a separate modfile for tests.<br />It has no dependencies (key to avoid supply chain attacks) except for testing.

### From C

1. Install a C compiler, `clang` is recommended, for example:
    - Debian/Ubuntu `sudo apt update && sudo apt install build-essential clang`
    - Archlinux `pacman -S base-devel clang`

2. Install nim, it is available in most distros package manager for Linux and Homebrew for MacOS
   Windows binaries are on the official website: https://nim-lang.org/install_unix.html
    - Debian/Ubuntu `sudo apt install nim`
    - Archlinux `pacman -S nim`

3. Compile the dynamic and static library.
    - Recommended: \
      `CC=clang nimble make_lib`
    - or `CTT_ASM=0 nimble make_lib`\
     to compile without assembly (otherwise it autodetects support)
    - or with default compiler\
      `nimble make_lib`

4. Ensure the libraries work
    - `nimble test_lib`

5. Libraries location
    - The librariess are put in `./lib/` folder
    - The headers are in [./include/](./include) for example [Ethereum BLS signatures](./include/constantine/protocols/ethereum_bls_signatures.h)

6. Read the examples in [examples-c](./examples-c):
   - Using the [Ethereum BLS signatures bindings from C](./examples-c/ethereum_bls_signatures.c)
   - Testing Constantine BLS12-381 vs GMP [./examples-c/t_libctt_bls12_381.c](./examples-c/t_libctt_bls12_381.c)

### From Nim

You can install the developement version of the library through nimble with the following command
```
nimble install https://github.com/mratsim/constantine@#master
```

## Dependencies & Requirements

For speed it is recommended to use Clang (see [Compiler-caveats](#Compiler-caveats)).
In particular GCC generates inefficient add-with-carry code.

Constantine requires at least:
- GCC 7 \
  Previous versions generated incorrect add-with-carry code.
- Clang 14 \
  On x86-64, inline assembly is used to workaround compilers having issues optimizing large integer arithmetic,
  and also ensure constant-time code. \
  Constantine uses the intel assembly syntax to address issues with the default AT&T syntax and constants propagated in Clang. \
  Clang 14 added support for `-masm=intel`. \
  \
  On MacOS, Apple Clang does not support Intel assembly syntax, use Homebrew Clang instead or compile without assembly.\
  _Note that Apple is discontinuing Intel CPU throughough their product line so this will impact only older model and Mac Pro_

On Windows, Constantine is tested with MinGW. The Microsoft Visual C++ Compiler is not configured.

Constantine has no C, Nim, Rust, Go dependencies, besides compilers, even on Nim standard library except:
- for testing and benchmarking
  - the tested language json and yaml parsers for test vectors
  - the tested language standard library for tests, timing and message formatting.
  - GMP for testing against GMP
- for Nvidia GPU backend:
  - the LLVM runtime ("dev" version with headers is not needed)
  - the CUDA runtime ("dev" version with headers is not needed)
- at compile-time
  - we need the std/macros library to generate Nim code.

## Performance

This section got way too long and has its own file.\
See [./README-PERFORMANCE.md](./README-PERFORMANCE.md)

## Assembly & Hardware acceleration

- Assembly is used on x86 and x86-64, unless `CTT_ASM=0` is passed.
- Assembly is planned for ARM.
- GPU acceleration is planned.

Assembly solves both:
- Security: [fighting the compiler for constant time code](./README-PERFORMANCE.md)
- Performance: [compiler caveats](./README-PERFORMANCE.md#compiler-caveats)

## Security

Hardening an implementation against all existing and upcoming attack vectors is an extremely complex task.
The library is provided as is, without any guarantees at least until:
- it gets audited
- formal proofs of correctness are produced
- formal verification of constant-time implementation is possible

Defense against common attack vectors are provided on a best effort basis.
Do note that Constantine has no external package dependencies hence it is not vulnerable to
supply chain attacks (unless they affect a compiler or the OS).

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

You can privately report a security vulnerability through the Security tab.

`Security > Report a vulnerability`

## Why Nim

The Nim language offers the following benefits for cryptography:
- Compilation to machine code via C or C++ or alternatively compilation to Javascript. Easy FFI to those languages.
  - Obscure embedded devices with proprietary C compilers can be targeted.
  - WASM can be targeted.
- Performance reachable in C is reachable in Nim, easily.
- Rich type system: generics, dependent types, mutability-tracking and side-effect analysis, borrow-checking, compiler enforced distinct types (Miles != Meters, SecretBool != bool and SecretWord != uint64).
- Compile-time evaluation, including parsing hex string, converting them to BigInt or Finite Field elements and doing bigint operations.
- Assembly support either inline or a simple `{.compile: "myasm.S".}` away
- No GC if no GC-ed types are used (automatic memory management is set at the type level and optimized for latency/soft-realtime by default and can be totally deactivated).
- Procedural macros working directly on AST to
  - create generic curve configuration,
  - derive constants
  - write a size-independent inline assembly code generator
- Upcoming proof system for formal verification via Z3 ([DrNim](https://nim-lang.org/docs/drnim.html), [Correct-by-Construction RFC](https://github.com/nim-lang/RFCs/issues/222))

## License

Licensed and distributed under either of

* MIT license: [LICENSE-MIT](LICENSE-MIT) or http://opensource.org/licenses/MIT

or

* Apache License, Version 2.0, ([LICENSE-APACHEv2](LICENSE-APACHEv2) or http://www.apache.org/licenses/LICENSE-2.0)

at your option. This file may not be copied, modified, or distributed except according to those terms.

This library has **no external dependencies**.
In particular GMP is used only for testing and differential fuzzing
and is not linked in the library.
