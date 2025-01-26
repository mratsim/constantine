# Constantine v0.1.0 "The Way of Shadows"

Jul 6, 2024, commit 1b4d969

> This release is named after "The Way of Shadows" (2009), the first book of Brent Weeks masterpiece "The Night Angel Trilogy".

I am very proud to release the very first version of Constantine, a high-performance modular cryptography stack for blockchains and proof systems.

I thank Ethereum Protocol Fellowship Program and Status for sponsoring the part-time work of 2 fellows on Constantine (then hiring them!) as well as a couple hours a week of my time for several months to prepare an upcoming complete refactoring of the Ethereum blockchain called Verkle Tries/Trees.

I also thank Araq, ringabout and all other contributors to the Nim compiler: the static ICE must flow.

Today Constantine is focused on the Ethereum blockchain, tomorrow I hope it will also address the need of (potentially Zero-Knowledge) proof systems and privacy-preserving protocols.

It currently exposes the following high-level protocols:
- BLS signatures for Ethereum
- BLS Key derivation for Ethereum - EIP-2333
- Optimized BigInt and Cryptographic Primitives for the Ethereum Virtual Machine
- KZG commitment for EIP4844 for scaling Ethereum
- SHA256 hash function
- Exposing the operating system Cryptographically Secure RNG
- An optimized threadpool, building upon both the performance of Weave and the simplicity and auditability of nim-taskpools.

On Ethereum protocols, Constantine is noticeably faster than other alternatives on x86 thanks to a mix of theoretical math, engineering and hardware-specific optimizations.

Those high-level protocols hide a modular stack of generic math and cryptography that can be reused to build optimized cryptographic protocols.
This even includes a JIT assembler as macro for x86 and a code generator for Nvidia GPU assembly through LLVM IR, skipping Cuda and Nvidia toolchain woes.

On the security side:
- Constantine has been written to have zero-dependency, besides the Nim compiler. It doesn't depend on Nim runtime or even allocator (including exceptions or sequences). This eases using tools like sanitizers or Valgrind, significantly hinder supply chain attacks, reduces security audit scope and will allow end-users to use specialized allocators like jemalloc. Current proof systems may need more than 1TB of memory for hours for example when proving the Ethereum Virtual Machine which is very different from what Nim allocator was built for.
- Constantine features as far as I know the largest test suite in the Nim ecosystem after the Nim compiler and Nimbus with 176 Nim files, 159 Json files and 253 yaml test vectors.
- The tests use a custom RNG that trigger rare events like carries (2⁻⁶⁴ chance) with high probability
- Constantine has had a fuzzing campaign sponsored by the Ethereum Foundation and has been added to Google OSS Fuzz: https://github.com/google/oss-fuzz/pull/10710
- It strive to test 32-bit, 64-bit, Linux, Windows, MacOS, x86, ARM as part of its CI. (Technically ARM hasn't work since Travis CI removed the free tier, but Github MacOS now uses ARM so soon)
- Constantine has NOT had a security audit. Here be dragons!

Constantine is built with use-cases beyond Nim:
- It has a C, Go and Rust backend within the repo. Python, C#, Typescript, Java are being considered to serve the full range of Ethereum clients + fast prototyping in Python.
- It can accelerate Rust ZK proof systems through ZAL, the ZK (Zero-Knowledge) Acceleration API: https://github.com/privacy-scaling-explorations/halo2/issues/216

The future:

Please refer to https://github.com/mratsim/constantine/blob/v0.1.0/PLANNING.md and the issue tracker https://github.com/mratsim/constantine/issues?q=is%3Aopen+is%3Aissue+label%3A%22enhancement+%3Ashipit%3A%22+

This includes:
- Continuing to follow Ethereum needs
- A focus on proof systems, zero-knowledge and potentially zkML (zero-knowledge machine learning)
- ARM Assembly
- RISC-V / WASM / WebGPU code generation
- Nvidia/AMD/Intel GPU code generation
- Potentially using LLVM MLIR and other compiler techniques for zkVMs (Virtual Machines for Proof Systems)

Some potential goals that I have no time for at the moment:
- Compete in the language benchmark game for https://programming-language-benchmarks.vercel.app/problem/secp256k1
- Implement classic cryptography like TLS or QUIC (Webrtc dependency) or Json Web Tokens in pure Nim
- Implement Fully-Homomorphic Encryption to enable privacy-preserving machine learning
- Implement Post-Quantum Cryptography in pure Nim

-- Mamy