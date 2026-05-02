---
**Branch:** `master` → `peerdas-perf-fix-rebased2` (commit `74d1839c`)
**Diff file:** `.REVIEWS/RID-202605022039-peerdas-perf-fix-rebased2-74d1839c/RID-202605022039-changes_under_review.diff`
**Date:** 2026-05-02
**Reviewer:** Math-Crypto Engineer (Pass A)
**Scope:** FK20 multiproof accumulator redesign, batch affine conversion vartime variants, polyphase spectrum bank coordinate change (Jacobian→Affine), Toeplitz API refactoring, bit reversal permutation aliasing fix
**Focus:** Elliptic curves, pairings, ZK proofs, FFTs, field arithmetic, protocol correctness, side-channels
---

# Math-Crypto Review (Pass A)

## Summary

| ID | Severity | Confidence | File | Issue |
|----|----------|------------|------|-------|
| MATH-A-001 | Medium | 0.8 | `constantine/commitments/kzg_multiproofs.nim:525-555` | `computeAggRandScaledInterpoly` runtime validation replaced by `doAssert` — parameter bounds only checked in debug builds |
| MATH-A-002 | Low | 0.9 | `constantine/math/matrix/toeplitz.nim:281-295` | `ToeplitzAccumulator.finish` type-puns `F` ↔ `F.getBigInt()` via raw pointer cast (defended by static size check) |

**Key takeaways:**
1. The FK20 accumulator redesign (`ToeplitzAccumulator`) is **mathematically correct**: the algorithm correctly computes per-position MSM after accumulating Hadamard products in Fourier domain, followed by a single amortized EC IFFT. This preserves the Toeplitz convolution identity `T·v = IFFT(FFT(circulant) ⊙ FFT(v))`.
2. All `batchAffine_vartime` call sites process **only public data** (KZG proof outputs, IPA proof points, verification intermediates). No secret-dependent timing channels are introduced.
3. The polyphase spectrum bank's transition from `EC_ShortW_Jac` to `EC_ShortW_Aff` storage is correct and reduces per-prove memory by eliminating repeated Jacobian→affine conversions.
4. One medium-severity concern: `computeAggRandScaledInterpoly` drops runtime bounds checking in favor of `doAssert`, which is optimized away in release builds.

---

## Findings

### [MATH-CRYPTO] MATH-A-001: `computeAggRandScaledInterpoly` runtime validation replaced by `doAssert` — parameter bounds only checked in debug builds

**Location:** `constantine/commitments/kzg_multiproofs.nim:525-555`
**Severity:** Medium
**Confidence:** 0.8

**Diff Under Review:**
```diff
 func computeAggRandScaledInterpoly[Name: static Algebra, L: static int](
        interpoly: var PolynomialCoef[L, Fr[Name]],
        evals: openArray[Fr[Name]],
        evalsCols: openArray[int],
        domain: FrFFT_Descriptor[Fr[Name]],
        linearIndepRandNumbers: openArray[Fr[Name]],
-      N: static int): bool {.meter.} =
+      N: static int) {.meter.} =
   ...
-  if evals.len != evalsCols.len or linearIndepRandNumbers.len < evalsCols.len:
-    return false
+  doAssert evals.len == evalsCols.len, "Internal error: evals and evalsCols must have same length"
+  doAssert linearIndepRandNumbers.len >= evalsCols.len, "Internal error: linearIndepRandNumbers must cover all evals"
   ...
-    if c < 0 or c >= NumCols:
-      return false
+    doAssert c >= 0 and c < NumCols, "Internal error: Column index out of bounds: " & $c
   ...
-  return true
```
And in the caller (`kzg_coset_verify_batch`):
```diff
-  if not interpoly.computeAggRandScaledInterpoly(
-     evals, evalsCols, domain, linearIndepRandNumbers, N):
-    return false
+  interpoly.computeAggRandScaledInterpoly(
+     evals, evalsCols, domain, linearIndepRandNumbers, N)
```

**Issue:** The function `computeAggRandScaledInterpoly` changes from returning `bool` with runtime validation to `void` with `doAssert` guards. The column index bounds check `c >= 0 and c < NumCols` and the length validation of `evals`, `evalsCols`, and `linearIndepRandNumbers` are now compile-time-only assertions that are stripped in release builds (`-d:release`).

This function is called from `kzg_coset_verify_batch`, which processes KZG multiproof verification data. If `evalsCols` contains a negative or out-of-bounds column index, or if `evals`/`linearIndepRandNumbers` lengths don't match expectations in a release build, the function will proceed with out-of-bounds array access on `agg_cols[c]` (heap-allocated array), potentially reading garbage or causing undefined behavior.

**Primitive:** KZG coset multiproof verification — aggregated random-scaled interpolating polynomial computation.

**Attack:** An attacker who can influence `evalsCols` (column indices) in a KZG verification request could cause out-of-bounds reads on the `agg_cols` heap buffer in release builds. The impact depends on what's in adjacent memory.

**Impact:** In the worst case, out-of-bounds reads could leak heap data or cause incorrect polynomial computation leading to verification failures. Primary concern is information leak or DoS (assertion failure in debug builds).

**Suggested Change:** Keep runtime validation for parameters derived from external/untrusted input. The `evalsCols` column indices are ultimately derived from DAS sample selection, which could be influenced by a malicious peer:
```nim
# Keep runtime check for external-facing parameters
if c < 0 or c >= NumCols:
  return false  # or raise a proper error
```
Alternatively, validate all column indices at the entry point of `kzg_coset_verify_batch` before calling `computeAggRandScaledInterpoly`.

**Specification Deviation:** The original code provided defense-in-depth by returning false on invalid inputs. Removing this creates a dependency on upstream validation that may not be complete.

---

### [MATH-CRYPTO] MATH-A-002: `ToeplitzAccumulator.finish` type-puns `F` ↔ `F.getBigInt()` via raw pointer cast (defended by static size check)

**Location:** `constantine/math/matrix/toeplitz.nim:281-295`
**Severity:** Low
**Confidence:** 0.9

**Diff Under Review:**
```diff
 proc finish*[EC, ECaff, F](
   ctx: var ToeplitzAccumulator[EC, ECaff, F],
   output: var openArray[EC]
 ): ToeplitzStatus {.raises: [], meter.} =
   ## MSM per position, then IFFT
   let n = ctx.size
   ...
+  # Invariant: scratchScalars is typed as F but re-interpreted as F.getBigInt() below.
+  # This requires sizeof(F) == sizeof(F.getBigInt()), which holds for all production
+  # field types (e.g. Fr[BLS12_381] is 32 bytes in both representations).
+  static: doAssert sizeof(F) == sizeof(F.getBigInt()), "scratchScalars cast requires sizeof(F) == sizeof(F.getBigInt())"
+
+  let scalars = cast[ptr UncheckedArray[F.getBigInt()]](ctx.scratchScalars)
+
+  for i in 0 ..< n:
+    # Load L scalars for position i
+    for offset in 0 ..< ctx.L:
+      scalars[offset].fromField(ctx.coeffs[i * ctx.L + offset])
+
+    # MSM: output[i] = Σ scalars[offset] * points[offset]
+    let pointsPtr = cast[ptr UncheckedArray[ECaff]](addr ctx.points[i * ctx.L])
+    output[i].multiScalarMul_vartime(scalars, pointsPtr, ctx.L)
```

**Issue:** The `ToeplitzAccumulator` declares `scratchScalars` as `ptr UncheckedArray[F]` (field elements in Montgomery representation) but re-interprets it as `ptr UncheckedArray[F.getBigInt()]` (BigInt in canonical representation) via a raw pointer cast. The correctness of this pun depends on `sizeof(F) == sizeof(F.getBigInt())` being true.

The `static: doAssert` provides compile-time verification for statically-known types like `Fr[BLS12_381]`. For Crandall primes, the Montgomery representation is identical to the canonical representation in memory, so the `fromField` conversion is a no-op (just `dst = src.mres`).

**Primitive:** Toeplitz matrix-vector multiplication — MSM coefficient loading via type-punned scratch buffer.

**Attack:** Not exploitable for BLS12-381 (where the size invariant holds). A theoretical concern if the generic were instantiated with an extension field (e.g., `Fp2`) where `sizeof(Fp2) != sizeof(Fp2.getBigInt())`.

**Impact:** Correctness concern for non-Crandall prime fields or extension fields. For BLS12-381 `Fr`, the representation is correct. The `static: doAssert` provides strong compile-time protection.

**Suggested Change:** The existing approach is acceptable for production. The `static: doAssert` combined with documentation is sufficient. Consider adding a compile-time constraint on the generic parameter to reject incompatible field types more explicitly.

---

## Positive Changes

1. **FK20 accumulator redesign (`ToeplitzAccumulator`)**: The new approach correctly implements the FK20 amortized proof algorithm by accumulating Hadamard products in Fourier domain, performing per-position MSM, and then a single amortized EC IFFT. This is mathematically equivalent to the original `toeplitzMatVecMulPreFFT` approach but with better memory layout (transposed storage) and reduced allocation overhead.

   Key mathematical verification: For each output position `i`, the accumulator computes `output[i] = Σ_{offset=0}^{L-1} FFT(circulant_{offset})[i] * polyphaseSpectrumBank[offset][i]` via MSM, then applies a single amortized IFFT to all positions. This correctly implements `T·v = IFFT(FFT(circulant) ⊙ FFT(v))` per FK20 Proposition 4.

2. **Polyphase spectrum bank coordinate change**: Converting from `EC_ShortW_Jac` to `EC_ShortW_Aff` storage eliminates per-prove Jacobian→affine conversions. The single `batchAffine_vartime` at the end of `computePolyphaseDecompositionFourier` correctly handles the ~50% infinity points in the second half of each phase (indices `CDSdiv2-1` through `CDS-1` are set to neutral).

3. **`batchAffine_vartime` infinity handling**: The variable-time batch affine conversion correctly handles points at infinity (Z=0) by maintaining the Montgomery product chain with identity elements (multiplying by 1 instead of Z), and outputs `setNeutral()` for infinity points. Verified for all four coordinate systems:
   - Short Weierstrass Projective → Affine (single inversion)
   - Short Weierstrass Jacobian → Affine (single inversion + squaring)
   - Twisted Edwards Projective → Affine (single inversion)

4. **In-place FFT operations**: Multiple functions now use in-place FFT (e.g., `ec_fft_nn(u, u)`, `ifft_rn(buf, buf)`) reducing memory allocation by one buffer per call. This is correct because the FFT implementations handle in-place operation via internal bit-reversal permutation (the new aliasing-safe `bit_reversal_permutation`).

5. **`bit_reversal_permutation` aliasing fix**: The new `bit_reversal_permutation` function detects dst/src aliasing (`dst[0].addr == src[0].addr`) and allocates a temporary buffer, preventing data corruption that could have occurred with in-place calls.

6. **`N <= 0` early return in `batchAffine`**: Added defensive guard in all `batchAffine` and `batchAffine_vartime` variants to handle zero/negative batch sizes, preventing out-of-bounds access.

7. **`checkCirculant` r=1 edge case handling**: The zero-padding check now properly handles the edge case where `r=1` (circulant length 2), avoiding out-of-bounds access at index `r+1` when `k2 = 2`. The check `if r + 1 < k2 and not circulant[r + 1].isZero().bool` correctly bounds-checks before access.

8. **Comprehensive test coverage**: New tests for `batchAffine_vartime` with all neutral points, single-element batches, varied batch sizes (2, 16), and all coordinate systems (ShortWeierstrass Jac/Prj, TwistedEdwards Prj) across BLS12-381 and BN254. Toeplitz accumulator init/finish error path tests added.

9. **`fromField` Montgomery conversion**: The `ToeplitzAccumulator.finish` correctly uses `scalars[offset].fromField(ctx.coeffs[...])` to convert from Montgomery to canonical representation before MSM. This is consistent with how `multiScalarMul_vartime` expects BigInt coefficients in natural (non-Montgomery) form, matching the pattern used throughout the codebase (kzg verification, EVM precompiles, parallel MSM).

No findings.
