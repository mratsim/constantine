---
**Branch:** `master` → `peerdas-perf-fix-rebased2` (commit `74d1839c`)
**Diff file:** `.REVIEWS/RID-202605022039-peerdas-perf-fix-rebased2-74d1839c/RID-202605022039-changes_under_review.diff`
**Date:** 2026-05-02
**Reviewer:** Test Coverage Analyst (Pass A)
**Scope:** Major PeerDAS performance overhaul: `batchAffine_vartime` (new vartime batch inversion), `ToeplitzAccumulator` (new MSM-based accumulator replacing `toeplitzMatVecMulPreFFT`), `bit_reversal_permutation` aliasing support, polyphase spectrum bank Jacobian→affine conversion, `computeAggRandScaledInterpoly` behavioral change (bool→void), and new `transpose` module.
**Focus:** Missing tests, happy-path only, boundary gaps, negative tests, regression risk
---

# Test Coverage Review (Pass A)

## Summary

| ID | Severity | Confidence | File | Issue |
|----|----------|------------|------|-------|
| COV-A-001 | Medium | 0.9 | `constantine/math/polynomials/fft_common.nim` | `bit_reversal_permutation` aliasing path (`dst == src`) untested |
| COV-A-002 | High | 0.9 | `constantine/math/matrix/toeplitz.nim` | `ToeplitzAccumulator.accumulate` error path untested |
| COV-A-003 | Medium | 0.9 | `constantine/math/matrix/toeplitz.nim` | `toeplitzMatVecMul` input-validation error paths untested |
| COV-A-004 | High | 0.9 | `constantine/commitments/kzg_multiproofs.nim` | `computeAggRandScaledInterpoly` invalid-input assertions untested |
| COV-A-005 | Medium | 0.8 | `constantine/commitments/kzg_multiproofs.nim` | Polyphase spectrum bank vartime batch-inversion with all-infinity points untested |
| COV-A-006 | Medium | 0.8 | `constantine/math/matrix/toeplitz.nim` | `ToeplitzAccumulator.init` double-init (memory leak) path untested |
| COV-A-007 | Low | 0.8 | `constantine/math/matrix/transpose.nim` | New `transpose` module has no tests |
| COV-A-008 | Low | 0.7 | `constantine/math/elliptic/ec_shortweierstrass_batch_ops.nim` | `batchAffine_vartime` N=0 (empty batch) guard untested |

**Key takeaways:**
1. The new `ToeplitzAccumulator` type has init/finit error tests but the `accumulate` method's error path (`Toeplitz_MismatchedSizes` for mismatched lengths or `offset >= L`) is entirely untested.
2. `computeAggRandScaledInterpoly` was changed from returning `bool` (returning `false` on invalid input) to using `doAssert` — the caller (`kzg_coset_verify_batch`) no longer checks a return value, so invalid inputs that would have returned `false` now cause assertion failures. The negative-input paths have no dedicated tests.
3. The new aliasing-detection path in `bit_reversal_permutation` (where `dst[0].addr == src[0].addr`) is not exercised by any test; all existing tests use either separate dst/src or the in-place overload.
4. The new `transpose.nim` module is a standalone file with no test coverage whatsoever.

## Findings

### [COVERAGE] COV-A-001: `bit_reversal_permutation` aliasing path untested - fft_common.nim

**Location:** `constantine/math/polynomials/fft_common.nim:304-335`
**Severity:** Medium
**Confidence:** 0.9

**Diff Under Review:**
```diff
-func bit_reversal_permutation*[T](dst{.noalias.}: var openArray[T], src{.noalias.}: openArray[T]) {.inline.} =
+func bit_reversal_permutation_noalias*[T](dst{.noalias.}: var openArray[T], src{.noalias.}: openArray[T]) {.inline.} =
+
+func bit_reversal_permutation*[T](dst: var openArray[T], src: openArray[T]) {.inline.} =
+  ## Out-of-place bit reversal permutation with aliasing detection.
+
+  if dst[0].addr == src[0].addr:
+    # Alias: allocate temp, permute to temp, copy back
+    var tmp = allocHeapArrayAligned(T, src.len, alignment = 64)
+    bit_reversal_permutation_noalias(tmp.toOpenArray(0, src.len-1), src)
+    copyMem(dst[0].addr, tmp[0].addr, src.len * sizeof(T))
+    freeHeapAligned(tmp)
+  else:
+    bit_reversal_permutation_noalias(dst, src)
```

**Issue:** **New aliasing-detection code path has no test.**

The diff renames the original `{.noalias.}` two-argument `bit_reversal_permutation` to `bit_reversal_permutation_noalias` and adds a new two-argument `bit_reversal_permutation` that checks `dst[0].addr == src[0].addr` to detect aliasing. When aliased, it allocates a temporary buffer.

Existing tests in `tests/math_polynomials/t_bit_reversal.nim` always use either:
- Separate `dst` and `src` arrays (out-of-place path)
- The in-place overload `buf.bit_reversal_permutation()` (single-argument)

Neither exercises the new aliasing-detection path where the same array is passed as both `dst` and `src`.

**Suggested Test:** Add a test case that passes the same array as both `dst` and `src`:
```nim
proc testBitReversalAliasing[T]() =
  const N = 256
  var buf = newSeq[T](N)
  for i in 0 ..< N: buf[i] = T(i)
  let orig = buf
  bit_reversal_permutation(buf, buf)  # dst == src alias
  for i in 0 ..< N:
    let rev_i = reverseBits(uint32(i), uint32(logN))
    doAssert buf[i] == T(rev_i)
```

---

### [COVERAGE] COV-A-002: `ToeplitzAccumulator.accumulate` error path untested - toeplitz.nim

**Location:** `constantine/math/matrix/toeplitz.nim:249-270`
**Severity:** High
**Confidence:** 0.9

**Diff Under Review:**
```nim
proc accumulate*[EC, ECaff, F](
  ctx: var ToeplitzAccumulator[EC, ECaff, F],
  circulant: openArray[F],
  vFft: openArray[ECaff]
): ToeplitzStatus {.raises: [], meter.} =
  ## Accumulate FFT(circulant) and vFft for position ctx.offset
  let n = ctx.size
  if n == 0 or circulant.len != n or vFft.len != n or ctx.offset >= ctx.L:
    return Toeplitz_MismatchedSizes
```

**Issue:** **The `accumulate` method's error conditions are never tested.**

The test file `tests/math_matrix/t_toeplitz.nim` has tests for `init` errors and `finish` errors, but `accumulate`'s error path (`Toeplitz_MismatchedSizes`) is never exercised. The conditions that trigger this error are:
- `n == 0` (uninitialized accumulator)
- `circulant.len != n` (wrong circulant length)
- `vFft.len != n` (wrong vector length)
- `ctx.offset >= ctx.L` (too many accumulate calls)

**Suggested Test:**
```nim
proc testToeplitzAccumulatorAccumulateErrors() =
  # Test: circulant.len != n
  # Test: vFft.len != n
  # Test: offset >= L (call accumulate L+1 times)
  # Test: uninitialized accumulator (n == 0)
```

---

### [COVERAGE] COV-A-003: `toeplitzMatVecMul` input-validation error paths untested - toeplitz.nim

**Location:** `constantine/math/matrix/toeplitz.nim:308-378`
**Severity:** Medium
**Confidence:** 0.9

**Diff Under Review:**
```diff
-proc toeplitzMatVecMul*[EC, F](
+proc toeplitzMatVecMul*[EC, F](
 ...
-): FFTStatus {.meter.} =
+): ToeplitzStatus {.meter.} =
 ...
   if output.len != n:
-    return FFT_SizeNotPowerOfTwo
+    return Toeplitz_MismatchedSizes
   if circulant.len != n2:
-    return FFT_SizeNotPowerOfTwo
+    return Toeplitz_MismatchedSizes
   if n2 > frFftDesc.order:
-    return FFT_TooManyValues
+    return Toeplitz_TooManyValues
   if n2 > ecFftDesc.order:
-    return FFT_TooManyValues
+    return Toeplitz_TooManyValues
```

**Issue:** **Input-validation error returns for `toeplitzMatVecMul` are untested.**

The function was rewritten to use `ToeplitzAccumulator` internally and now returns `ToeplitzStatus` instead of `FFTStatus`. The error paths are:
- `output.len != n` → `Toeplitz_MismatchedSizes`
- `circulant.len != n2` → `Toeplitz_MismatchedSizes`
- `n2 > frFftDesc.order` → `Toeplitz_TooManyValues`
- `n2 > ecFftDesc.order` → `Toeplitz_TooManyValues`

The existing `testToeplitz()` in `t_toeplitz.nim` only tests the happy path with matching sizes.

**Suggested Test:**
```nim
proc testToeplitzMatVecMulErrors() =
  # output too small → Toeplitz_MismatchedSizes
  # circulant wrong length → Toeplitz_MismatchedSizes
  # n2 exceeds FFT descriptor order → Toeplitz_TooManyValues
```

---

### [COVERAGE] COV-A-004: `computeAggRandScaledInterpoly` behavioral change — negative input assertions untested - kzg_multiproofs.nim

**Location:** `constantine/commitments/kzg_multiproofs.nim:499-560`
**Severity:** High
**Confidence:** 0.9

**Diff Under Review:**
```diff
 func computeAggRandScaledInterpoly[Name: static Algebra, L: static int](
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
```

**Issue:** **Function changed from returning `bool` to `void` with `doAssert` — no test exercises the invalid-input assertions.**

Previously, callers checked the return value:
```nim
-  if not interpoly.computeAggRandScaledInterpoly(...):
-    return false
+  interpoly.computeAggRandScaledInterpoly(...)  # no return value check
```

This is a **behavioral change**: invalid input that previously returned `false` now triggers a `doAssert` (fatal in release builds with `-d:assertions`). The caller `kzg_coset_verify_batch` no longer guards against bad input from this function.

No existing test passes mismatched `evals.len` vs `evalsCols.len`, insufficient `linearIndepRandNumbers`, or out-of-range column indices. While these would only fire on `doAssert` (debug mode), the behavioral contract change itself should be verified by tests.

**Suggested Test:**
```nim
# In debug mode, verify that invalid inputs trigger assertions:
# - evals.len != evalsCols.len
# - linearIndepRandNumbers.len < evalsCols.len
# - evalsCols[k] < 0 or >= NumCols
```

---

### [COVERAGE] COV-A-005: Polyphase spectrum bank vartime batch-inversion with all-infinity points untested - kzg_multiproofs.nim

**Location:** `constantine/commitments/kzg_multiproofs.nim:352-415` (specifically lines 707-713)
**Severity:** Medium
**Confidence:** 0.8

**Diff Under Review:**
```diff
+  # Compute all phases in Jacobian form first
+  let polyphaseSpectrumBankJac = allocHeapArrayAligned(array[CDS, EC_ShortW_Jac[Fp[Name], G1]], L, alignment = 64)
 ...
+  # Half the points are points at infinity. A vartime batch inversion
+  # saves a lot of compute, 3*L*CDS
+  batchAffine_vartime(
+    polyphaseSpectrumBank[0].asUnchecked(),
+    polyphaseSpectrumBankJac[0].asUnchecked(),
+    L * CDS
+  )
```

**Issue:** **The `computePolyphaseDecompositionFourier` function now converts L×CDS Jacobian points to affine using `batchAffine_vartime`, where half the points (CDSdiv2 of each CDS) are points at infinity.**

The existing tests in `t_kzg_multiproofs.nim` exercise the happy path of `computePolyphaseDecompositionFourier` with normal SRS inputs, which produce valid polyphase spectra. However:
- The `batchAffine_vartime` call handles ~50% infinity points (a pathological case for batch inversion)
- While the `batchAffine_vartime` function itself has all-neutral tests in `t_ec_template.nim`, the **integration** through `computePolyphaseDecompositionFourier` → `kzg_coset_prove` → `kzg_coset_verify` pipeline with these specific mixed-infinity inputs is covered only implicitly via the FK20 proof tests
- There is no test that explicitly verifies the polyphase spectrum bank output is correct affine coordinates after the batch conversion (vs. the old per-offset Jacobian output)

This is a regression risk: if `batchAffine_vartime` produces incorrect results for the specific infinity/non-infinity interleaving pattern in the polyphase bank, all FK20 proofs would silently be wrong.

**Suggested Test:**
```nim
# Verify polyphase spectrum bank contains correct affine coordinates:
# Compare with per-point .affine() conversion of the same Jacobian points
# Specifically verify infinity points are correctly represented as affine neutral
```

---

### [COVERAGE] COV-A-006: `ToeplitzAccumulator.init` double-init memory leak path untested - toeplitz.nim

**Location:** `constantine/math/matrix/toeplitz.nim:219-248`
**Severity:** Medium
**Confidence:** 0.8

**Diff Under Review:**
```nim
proc init*[EC, ECaff, F](
  ctx: var ToeplitzAccumulator[EC, ECaff, F],
  ...
): ToeplitzStatus {.raises: [], meter.} =
  # Free existing allocations (defensive: handles accidental double-init)
  if not ctx.coeffs.isNil():
    freeHeapAligned(ctx.coeffs)
  if not ctx.points.isNil():
    freeHeapAligned(ctx.points)
  if not ctx.scratchScalars.isNil():
    freeHeapAligned(ctx.scratchScalars)
```

**Issue:** **The defensive double-init path (freeing existing allocations before re-allocating) is never tested.**

The `init` method defensively frees existing buffers if they are non-nil, handling accidental double-init. The existing test `testToeplitzAccumulatorInitErrors` only calls `init` on a default-initialized (nil) accumulator. The path where `init` is called on an already-initialized accumulator — which should free the old buffers and allocate new ones — is untested.

**Suggested Test:**
```nim
proc testToeplitzAccumulatorDoubleInit() =
  var acc: ToeplitzAccumulator[...]
  doAssert acc.init(frDesc, ecDesc, size = 4, L = 2) == Toeplitz_Success
  # Double-init should succeed and not leak
  doAssert acc.init(frDesc, ecDesc, size = 8, L = 4) == Toeplitz_Success
  # Verify second allocation works (use accumulate + finish)
```

---

### [COVERAGE] COV-A-007: New `transpose` module has no tests - transpose.nim

**Location:** `constantine/math/matrix/transpose.nim` (entire file, 79 lines)
**Severity:** Low
**Confidence:** 0.8

**Diff Under Review:**
```diff
+proc transpose*[T](dst, src: ptr UncheckedArray[T], M, N: int, blockSize: static int = 16) {.inline.} =
+  ## 2D tiled transposition for optimal cache utilization
+  const blck = blockSize
+  for jj in countup(0, N - 1, blck):
+    for ii in countup(0, M - 1, blck):
+      for j in jj ..< min(jj + blck, N):
+        for i in ii ..< min(ii + blck, M):
+          dst[j * M + i] = src[i * N + j]
+
+proc transpose*[T](dst: var openArray[T], src: openArray[T], M, N: int, blockSize: static int = 16) {.inline.} =
+  doAssert dst.len >= N * M, "dst too small"
+  doAssert src.len >= M * N, "src too small"
```

**Issue:** **New `transpose` module is a standalone file with zero test coverage.**

While the benchmark file `benchmarks/bench_matrix_transpose.nim` exercises multiple transpose implementations (including the 2D blocked variant that matches the production code), benchmarks are not tests — they verify performance, not correctness.

**Suggested Test:**
```nim
# Basic correctness: transpose of [1..M*N] should match expected result
# Square matrix: M == N
# Rectangular matrix: M != N
# Different block sizes: blockSize = 4, 8, 16, 32
# Edge case: M=1 or N=1
```

---

### [COVERAGE] COV-A-008: `batchAffine_vartime` N=0 (empty batch) guard untested - ec_shortweierstrass_batch_ops.nim

**Location:** `constantine/math/elliptic/ec_shortweierstrass_batch_ops.nim:1052-1058`
**Severity:** Low
**Confidence:** 0.7

**Diff Under Review:**
```diff
+func batchAffine_vartime*[F, G](
+       affs: ptr UncheckedArray[EC_ShortW_Aff[F, G]],
+       projs: ptr UncheckedArray[EC_ShortW_Prj[F, G]],
+       N: int) {.tags:[VarTime], meter.} =
+  if N <= 0:
+    return
```

**Issue:** **The `N <= 0` early-return guard is untested for both `batchAffine` and `batchAffine_vartime`.**

The diff adds `if N <= 0: return` guards to `batchAffine` (for both Projective and Jacobian overloads) and `batchAffine_vartime`. The existing tests in `t_ec_template.nim` test batch sizes 1, 2, 10, and 16, but never N=0 or negative N.

**Suggested Test:**
```nim
# Verify no crash with N=0:
var affs: array[0, EC_Aff]
var projs: array[0, EC_Prj]
affs.batchAffine_vartime(projs)  # should be no-op
```

## Positive Changes

- **`batchAffine_vartime`** receives comprehensive tests via the updated `t_ec_template.nim`: happy-path, infinite points, single element, all-neutral, and varied batch sizes — all parameterized by `isVartime` flag.
- **`ToeplitzAccumulator.init` error paths** (size=0, L=0, non-power-of-2, negative size) are covered by `testToeplitzAccumulatorInitErrors()`.
- **`ToeplitzAccumulator.finish` error path** (finish without accumulate) is covered by `testToeplitzAccumulatorFinishErrors()`.
- **`checkCirculant` r=1 boundary** is explicitly tested by `testCheckCirculantR1()`, covering the new `r+1` bounds check.
- **`testToeplitz`** now tests sizes 4, 8, and 16 (was only 4 and 8), providing broader coverage of the rewritten `toeplitzMatVecMul` function.
- **`t_kzg_multiproofs.nim`** updated to use affine polyphase spectrum bank type, exercising the new `computePolyphaseDecompositionFourier` → `batchAffine_vartime` path through the full FK20 proof pipeline.
