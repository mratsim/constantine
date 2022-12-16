# GPU compilation targets

For CPUs, Constantine JIT-compiles the cryptographic kernels via LLVM.

This allows targeting several devices with a single frontend, the LLVM IR.

Current use-cases are large scale aggregations, large-scale multi-scalar-multiplications and large-scale FFTs.

Those are important primitives for:
- aggregation of public keys or signatures from a large number of nodes
- protocols based on polynomial commitments
- zero-knowledge proof systems

Potential future use-cases include erasure coding and lattice-based cryptography acceleration.

⚠️ GPU usage is not constant-time and requires allocation of dynamic memory. It MUST NOT be used for secret data.