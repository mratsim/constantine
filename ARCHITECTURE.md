# Architecture

## APIs & Conventions

### Dependencies

Constantine has no external dependencies in `src` to avoid supply chain attack risks, and to ensure auditing only involves code written with cryptographic security in mind.

This also includes Nim standard library except:

- std/atomics
- Anything used at compile-time only
  - std/macros
  - std/os and std/strutils to create compile-time paths relative to the currentSourcePath
- Anything used for tests or debugging
  - json and yaml libraries are used in tests
  - sequences and strings can be used in tests
  - `toHex` is provided for debugging and testing
- Anything related to code generation, for example:
  - the Nim -> Cuda/WebGPU runtime compiler uses tables but the actual GPU cryptographic code doesn't.
  - the LLVM JIT uses string for identifier

To be clear, we do not use the following:
- std/tables, std/sequtils, std/strutils, std/algorithm, std/math, std/streams ...
- bit manipulations, endianness manipulation, ...
- Nim's `seq` and Nim's `string`
- Nim's locks, condition variables
- external threadpools
- external bigint libraries

For file IO, we reimplement our primitives on top of the C standard library in `constantine/platforms/fileio.nim`

### Argument orders

Function calls have arguments ordered the following way:

1. Context arguments
2. Threadpool context
3. OUT arguments (only written to)
4. INOUT arguments
5. IN arguments

The first context argument should allow method call syntax

In C, length of arrays immediately follow the array, unless there are multiple array arguments with same length.
If an argument is associated with a label, for domain separation for example,
that label precedes the argument.

### Return values

Constantine avoids returning values bigger than the word size
and prefer mutable out parameters.

1. In some cases they introduce extra copies.
2. There is less guarantees over stack space usage.
3. Nim will zero the values without {.noInit.}
   and that zeroing might not be optimized away by the compiler
   on large inputs like `Fp12[BLS12_381]` 48\*12 bytes = 576 bytes.
4. As we sometimes return SecretBool or status code, this keeps the API consistent.

Syntactic sugar through out-of-place arithmetic functions like `+` and `*`
is available for rapid prototyping, testing and debugging.

For elliptic curves, variable time functions are prefixed with a tilde like
`~+` `~-` and `~*`.

They SHOULD NOT be use in performance-critical or stack space critical
subroutines.
- They should be tagged {.inline, noInit.} and just forward to the in-place function
  to guarantee copy elision. (and even then it's not guaranteed)
- Issues:
  - Extremely inefficient codegen in Constantine itself https://github.com/mratsim/constantine/issues/145
    with useless moves instead of in-place construction.
  - In other languages like Rust, users have seen a dramatic 20% increase in performance by moving from out-of-place to in-place mutation: https://www.reddit.com/r/rust/comments/kfs0oe/comment/ggc0dui/
    - And they are struggling with GCE (Guarenteed Copy Elision) and NRVO/RVO(Named) Return Value Optimization
      - https://github.com/rust-lang/rust/pull/76986
      - https://github.com/rust-lang/rfcs/pull/2884

### Error codes, and Result

In low-level C, everything is return through status codes.

In Rust, status is communicated through `Result<Output, Error>`
In particular for verification, Errors are used if the protocol is not followed:
- wrong input length
- point not on curve
- point not in subgroup
- zero point

However if all those exceptional rules are followed, but verification still fails,
the failure is communicated through a boolean.

Similarly in Go, errors are used to communicate breaking protocol rules
and the result of verification is communicated through a bool.

We can use Nim's effect tracking `{.raises: [].}` to ensure no exceptions are raised in a function call stack.

### Memory allocation

We actively avoid memory allocation for any protocol that:
- handle secrets
- could be expected to run in a trusted enclave or embedded devices

This includes encryption, hashing and signatures protocols.

When memory allocation is necessary, for example for multithreading, GPU computing or succinct or zero-knowledge proof protocol, we use custom allocators from `constantine/platforms/allocs.nim`. Those are thin wrappers around the OS `malloc`/`free` with effect tracking `{.tags:[HeapAlloc].}` or `{.tags:[Alloca].}`. Then we can use Nim's effect tracking `{.tags: [].}` to ensure no *heap allocation* or *alloca* is used in the function call stack.

### Constant-time and side-channel resistance

Low-level operations that can handle secrets SHOULD be constant-time by default.
Constantine assumes that addition, subtraction (including carries/borrows), multiplication, bit operations, shifts are constant-time in hardware.

Constantine has `SecretWord` and `SecretBool` types that reimplements basic primitives
with side-channel resistance in mind, though smart compilers may unravel them and reintroduce branches. Constantine provides primitives like `cadd`, `csub`, `cneg`, `ccopy` (conditional add, sub, neg, copy) and `isZero`, `isMsbSet` that allow simulating conditional execution without branches. Check `constantine/platforms/constant_time/ct_routines.nim`

Hence a significant portion of low-level routines has an assembly path (x86-64 and ARM64) to avoid compiler-introduced side-channels like in https://www.cl.cam.ac.uk/~rja14/Papers/whatyouc.pdf

More information in the wiki: https://github.com/mratsim/constantine/wiki/Constant-time-arithmetics

Some primitives may have a variable time optimization (for example field inversion or elliptic curve scalar multiplication) or may be variable-time only (for example multi-scalar multiplication), in that case they are suffixed `_vartime`.

We use Nim's effect tracking `{.tags: [VarTime].}` so we can ensure that in protocols that handle secrets it is a compile-time error to have VarTime anywhere in the call stack via `{.tags:[].}`.

High-level protocols or subroutines for high-level protocols do not need this `_vartime` suffix hence this mostly concerns bigint, fields, elliptic curves and polynomial arithmetic.

Another source of side-channel attacks is table access. A non-uniform table access can be exploited by cache attacks like Colin Percival attack on Hyperthreading.
A lookup table access can be simulated via `secretLookup` to ensure the whole table is uniformly accessed, or `ccopy` for non-trivial indexing patterns like for exponentiation.


## Code organization

TBD
