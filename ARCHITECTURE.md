# Architecture

## APIs

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

## Code organization

TBD
