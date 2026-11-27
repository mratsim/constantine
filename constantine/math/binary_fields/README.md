# Binary fields

- `GF2_64`: 𝔽₂⁶⁴ = 𝔽₂[x]/(x⁶⁴ + x⁴ + x³ + x + 1)
- `GF2_64x2`: 𝔽₂¹²⁸ = 𝔽₂⁶⁴[y]/(y² + xy + 1), a `QuadraticExt[GF2_64]`

These are the fields of [leanVM](https://github.com/leanEthereum/leanVM), where they are called K and E.
Elements serialize to the same bytes as leanVM's wire format (`marshal(…, littleEndian)`).

## Arithmetic

Addition is XOR. Multiplication is a 64×64 → 128-bit carry-less product followed by a reduction
by x⁶⁴ = x⁴ + x³ + x + 1. In 𝔽₂¹²⁸, y² folds back as x·y + 1, a 1-bit shift.

All operations are constant-time. Inversion uses Itoh-Tsujii in 𝔽₂⁶⁴ and the norm to 𝔽₂⁶⁴ in 𝔽₂¹²⁸.

## Backends

| | Carry-less product | Everything else | Runtime check |
|---|---|---|---|
| x86-64 | PCLMULQDQ, inline assembly | SSE2 intrinsics | `hasCLMUL()` |
| ARM64 | PMULL / PMULL2, inline assembly | NEON intrinsics | `hasPmull()` |
| Fallback | integer multiplication on masked operands (as in BearSSL) | | |

Only the carry-less multiplication needs a CPU extension. It is emitted with the macro assemblers
(`XmmReg` / `VecReg` operands, `pclmulqdq`, `pmull`, `pmull2`), so callers inline it without being compiled
with `-mpclmul` or `+aes`. On ARM64 the assembly block enables the extension itself (`.arch_extension aes`).
The surrounding code uses only baseline SSE2 or NEON.

On ARM64, a 64-bit operand enters a vector register with `fmov` (low lane, high lane zeroed),
also through the assembler, as non-volatile assembly so the compiler can still hoist and merge it.
It is about 2 cycles faster than DUP on Apple M4, which is on the critical path of every 𝔽₂⁶⁴ product,
and clang turns the intrinsic alternatives into a zeroing plus an insertion.

Compiling with `-d:CTT_ASM=false` selects the fallback everywhere.
The `*_portable` functions use the fallback regardless, for tests and benchmarks.

## Reuse of Constantine's generic code

The API follows the prime fields' (`prod`, `square`, `inv`, `csetZero`, `prod2x`, `redc2x`, …),
so generic code instantiates with these types, for example:

- the extension tower: `GF2_64x2` is a `QuadraticExt` and the lazy-reduced `GF2_64x2Dbl` a `QuadraticExt2x`.
  Only operations that depend on the modulus are specialized. Constantine's towers assume y² = β,
  a form that does not exist in characteristic 2, where every element is a square.
- `pow_vartime` from `extension_fields/exponentiations`
- `batchInv` and `batchInv_vartime`
- `MultilinearExtension` from `boolean_hypercube`

## References

- leanVM: `crates/stable_prover/primitives/src/field/`, `crates/verifier/src/field.rs`, `doc/leanvm/`
- BearSSL constant-time GHASH: https://bearssl.org/constanttime.html#ghash-for-gcm
