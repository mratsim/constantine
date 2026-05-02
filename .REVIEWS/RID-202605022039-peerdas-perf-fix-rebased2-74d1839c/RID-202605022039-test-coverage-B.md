---
**Branch:** `master` → `peerdas-perf-fix-rebased2` (commit `74d1839c`)
**Diff file:** `.REVIEWS/RID-202605022039-peerdas-perf-fix-rebased2-74d1839c/RID-202605022039-changes_under_review.diff`
**Date:** 2026-05-02
**Reviewer:** Test Coverage Analyst (Pass B)
**Scope:** Regression-prevention review of PeerDAS performance fixes: new `ToeplitzAccumulator`, `batchAffine_vartime` family, `computeAggRandScaledInterpoly` signature change, `bit_reversal_permutation` aliasing support, polyphase spectrum bank format change (Jac→Aff), and FFT tag removals.
**Focus:** Missing tests, happy-path only, boundary gaps, negative tests, regression risk
---

# Test Coverage Review (Pass B)

## Summary

| ID | Severity | Confidence | File | Issue |
|----|----------|------------|------|-------|
| COV-B-001 | High | 0.9 | constantine/commitments/kzg_multiproofs.nim:527-534 | `computeAggRandScaledInterpoly` changed from `bool` return to `void` with `doAssert`; no test exercises the former error-return paths |
| COV-B-002 | Medium | 0.9 | constantine/math/matrix/toeplitz.nim:586-600 | `ToeplitzAccumulator.accumulate` mismatched-size error path has no dedicated test |
| COV-B-003 | Medium | 0.8 | constantine/math/polynomials/fft_common.nim:307-322 | `bit_reversal_permutation(dst, src)` aliasing detection branch untested |
| COV-B-004 | Medium | 0.8 | constantine/math/matrix/toeplitz.nim:602-650 | `ToeplitzAccumulator` end-to-end accumulate→accumulate→finish correctness not directly tested |
| COV-B-005 | Low | 0.8 | constantine/math/elliptic/ec_shortweierstrass_batch_ops.nim:188-190 | `batchAffine_vartime` N≤0 early-return guard not explicitly tested |
| COV-B-006 | Low | 0.7 | constantine/commitments/kzg_multiproofs.nim:717-809 | `kzg_coset_prove` internal error paths (accumulator init/finish failures) have no focused test |
| COV-B-007 | Informational | 0.6 | constantine/commitments/kzg_multiproofs.nim:659-715 | `computePolyphaseDecompositionFourier` in-place IFFT + Jac→Aff batch conversion tested only end-to-end |

**Key takeaways:**
1. The most significant regression risk is COV-B-001: `computeAggRandScaledInterpoly` silently changed from graceful error-return to assertion-fail, but tests only exercise the happy path.
2. The new `ToeplitzAccumulator` has error-path tests for `init` and `finish`, but the `accumulate` method's size-mismatch error path is untested.
3. The aliasing detection in `bit_reversal_permutation(dst, src)` is a new code path with zero test coverage.

## Findings

### [COVERAGE] COV-B-001: `computeAggRandScaledInterpoly` error-return removed without regression test - kzg_multiproofs.nim:527-534

**Location:** constantine/commitments/kzg_multiproofs.nim:527-534
**Severity:** High
**Confidence:** 0.9

**Diff Under Review:**
```diff
-  if evals.len != evalsCols.len or linearIndepRandNumbers.len < evalsCols.len:
-    return false
+  doAssert evals.len == evalsCols.len, "Internal error: evals and evalsCols must have same length"
+  doAssert linearIndepRandNumbers.len >= evalsCols.len, "Internal error: linearIndepRandNumbers must cover all evals"
```
```diff
-    if c < 0 or c >= NumCols:
-      return false
+    doAssert c >= 0 and c < NumCols, "Internal error: Column index out of bounds: " & $c
```
```diff
-  if not interpoly.computeAggRandScaledInterpoly(
-    evals, evalsCols, domain, linearIndepRandNumbers, N
-  ):
-    return false
+  interpoly.computeAggRandScaledInterpoly(
+    evals, evalsCols, domain, linearIndepRandNumbers, N
+  )
```

**Issue:** **Error-return contract silently changed from graceful rejection to assertion failure**

The function signature changed from `bool` return to `void`. Previously, callers could receive `false` for mismatched lengths, insufficient random numbers, or out-of-bounds column indices. Now these conditions cause `doAssert` failures (fatal in debug, silent skip in release).

The existing tests in `tests/commitments/t_kzg_multiproofs.nim` (e.g., `testKzgCosetVerifyBatch`) always pass valid inputs, so the new `doAssert` paths are never exercised. More critically, there is no regression test that verifies `kzg_coset_verify_batch` still correctly rejects bad inputs — it previously returned `false` for these cases, and the behavior is now fundamentally different.

In `-d:release` builds, `doAssert` is a no-op, meaning the function proceeds with invalid data, potentially causing memory corruption or incorrect results.

**Suggested Test:** Add a test that calls `kzg_coset_verify_batch` with:
1. Mismatched `evals.len != evalsCols.len` — should be rejected or caught
2. Negative column index — should be rejected or caught  
3. Column index >= `NumCols` — should be rejected or caught
4. `linearIndepRandNumbers` shorter than `evalsCols` — should be rejected or caught

Verify the behavior in both debug and release modes is consistent and safe.

---

### [COVERAGE] COV-B-002: `ToeplitzAccumulator.accumulate` mismatched-size error path untested - toeplitz.nim:586-600

**Location:** constantine/math/matrix/toeplitz.nim:586-600
**Severity:** Medium
**Confidence:** 0.9

**Diff Under Review:**
```diff
+proc accumulate*[EC, ECaff, F](
+  ctx: var ToeplitzAccumulator[EC, ECaff, F],
+  circulant: openArray[F],
+  vFft: openArray[ECaff]
+): ToeplitzStatus {.raises: [], meter.} =
+  ## Accumulate FFT(circulant) and vFft for position ctx.offset
+  let n = ctx.size
+  if n == 0 or circulant.len != n or vFft.len != n or ctx.offset >= ctx.L:
+    return Toeplitz_MismatchedSizes
```

**Issue:** **The `accumulate` method's size-validation error path has no test**

`tests/math_matrix/t_toeplitz.nim` adds `testToeplitzAccumulatorInitErrors()` (tests `init` error paths) and `testToeplitzAccumulatorFinishErrors()` (tests `finish` error paths), but there is no `testToeplitzAccumulatorAccumulateErrors()`.

The `accumulate` method checks four conditions:
- `n == 0` (uninitialized accumulator)
- `circulant.len != n` (wrong circulant length)
- `vFft.len != n` (wrong vector length)
- `ctx.offset >= ctx.L` (too many accumulates)

None of these are tested. A regression in this validation (e.g., wrong comparison operator) would go undetected and could cause heap buffer over-reads in the transposed storage layout.

**Suggested Test:** Add `testToeplitzAccumulatorAccumulateErrors()` that verifies:
```nim
proc testToeplitzAccumulatorAccumulateErrors() =
  var acc: ToeplitzAccumulator[...]
  acc.init(frDesc, ecDesc, size = 4, L = 2) == Toeplitz_Success
  var circulant: array[8, Fr[BLS12_381]]  # wrong length (8 instead of 4)
  var vFft: array[4, G1Aff]
  doAssert acc.accumulate(circulant, vFft) == Toeplitz_MismatchedSizes
  
  # Test offset exhaustion
  var circulant2: array[4, Fr[BLS12_381]]
  discard acc.accumulate(circulant2, vFft)
  discard acc.accumulate(circulant2, vFft)
  doAssert acc.accumulate(circulant2, vFft) == Toeplitz_MismatchedSizes  # offset == L
```

---

### [COVERAGE] COV-B-003: `bit_reversal_permutation(dst, src)` aliasing detection branch untested - fft_common.nim:307-322

**Location:** constantine/math/polynomials/fft_common.nim:307-322
**Severity:** Medium
**Confidence:** 0.8

**Diff Under Review:**
```diff
-func bit_reversal_permutation*[T](dst{.noalias.}: var openArray[T], src{.noalias.}: openArray[T]) {.inline.} =
+func bit_reversal_permutation_noalias*[T](dst{.noalias.}: var openArray[T], src{.noalias.}: openArray[T]) {.inline.} =
+
+func bit_reversal_permutation*[T](dst: var openArray[T], src: openArray[T]) {.inline.} =
+  ## Out-of-place bit reversal permutation with aliasing detection.
+  if dst[0].addr == src[0].addr:
+    # Alias: allocate temp, permute to temp, copy back
+    var tmp = allocHeapArrayAligned(T, src.len, alignment = 64)
+    bit_reversal_permutation_noalias(tmp.toOpenArray(0, src.len-1), src)
+    copyMem(dst[0].addr, tmp[0].addr, src.len * sizeof(T))
+    freeHeapAligned(tmp)
+  else:
+    bit_reversal_permutation_noalias(dst, src)
```

**Issue:** **The new aliasing detection code path in `bit_reversal_permutation(dst, src)` has no test**

The existing tests in `tests/math_polynomials/t_bit_reversal.nim` test:
- `testNaiveOutOfPlace` — separate src and dst (no aliasing)
- `testAutoOutOfPlace` — separate src and dst (no aliasing)
- `testAutoInPlace` — uses single-arg `buf.bit_reversal_permutation()`, NOT the two-arg form with aliasing

The two-argument `bit_reversal_permutation(dst, src)` is called in many places throughout the codebase. If `dst` and `src` happen to be the same buffer, the new aliasing path should produce the same result as the in-place version. But this path is never exercised by any test.

**Suggested Test:** Add an aliasing test to `t_bit_reversal.nim`:
```nim
proc testAliasingOutOfPlace[T]() =
  ## Test bit_reversal_permutation(dst, src) when dst and src alias
  let N = 64
  var buf = newSeq[T](N)
  for i in 0 ..< N: buf[i] = T(i)
  let original = buf  # save copy
  bit_reversal_permutation(buf, buf)  # aliasing!
  # Verify same result as in-place
  var expected = original
  expected.bit_reversal_permutation()  # single-arg version
  for i in 0 ..< N:
    doAssert buf[i] == expected[i], "Aliasing out-of-place failed at " & $i
```

---

### [COVERAGE] COV-B-004: `ToeplitzAccumulator` accumulate→finish correctness not directly tested - toeplitz.nim:602-650

**Location:** constantine/math/matrix/toeplitz.nim:602-650
**Severity:** Medium
**Confidence:** 0.8

**Diff Under Review:**
```diff
+proc finish*[EC, ECaff, F](
+  ctx: var ToeplitzAccumulator[EC, ECaff, F],
+  output: var openArray[EC]
+): ToeplitzStatus {.raises: [], meter.} =
+  ## MSM per position, then IFFT
+  let n = ctx.size
+  if n == 0 or output.len != n or ctx.offset != ctx.L:
+    return Toeplitz_MismatchedSizes
+  for i in 0 ..< n:
+    # Load L scalars for position i
+    for offset in 0 ..< ctx.L:
+      scalars[offset].fromField(ctx.coeffs[i * ctx.L + offset])
+    # MSM: output[i] = Σ scalars[offset] * points[offset]
+    let pointsPtr = cast[ptr UncheckedArray[ECaff]](addr ctx.points[i * ctx.L])
+    output[i].multiScalarMul_vartime(scalars, pointsPtr, ctx.L)
+  # IFFT in-place
+  checkReturn ec_ifft_nn(ctx.ecFftDesc, output, output)
+  return Toeplitz_Success
```

**Issue:** **The complete `ToeplitzAccumulator` happy-path (init → accumulate × L → finish) is tested only indirectly through `toeplitzMatVecMul`**

The `testToeplitz(4/8/16)` tests exercise the high-level `toeplitzMatVecMul` wrapper, which internally uses `ToeplitzAccumulator`. However, there is no test that directly constructs a `ToeplitzAccumulator`, calls `accumulate` multiple times with known inputs, calls `finish`, and verifies the result against a naive O(n²) computation. This means:
- Bugs in the transposed storage layout (`coeffs[i * L + offset]`) would only be caught if the high-level wrapper happens to trigger the same path
- Bugs in the MSM per-position computation would go undetected if `toeplitzMatVecMul`'s single-L=1 path differs from the multi-L path

**Suggested Test:** Add a direct accumulator correctness test:
```nim
proc testToeplitzAccumulatorDirect() =
  ## Direct test: init → accumulate × 4 → finish, verify against naive
  var acc: ToeplitzAccumulator[G1_Prj, G1_Aff, Fr]
  acc.init(frDesc, ecDesc, size = 4, L = 4)
  for offset in 0 ..< 4:
    acc.accumulate(circulant[offset], vFft[offset])
  var result: array[4, G1_Prj]
  acc.finish(result)
  # Verify against known expected values
```

---

### [COVERAGE] COV-B-005: `batchAffine_vartime` N≤0 early-return not explicitly tested - ec_shortweierstrass_batch_ops.nim:188-190

**Location:** constantine/math/elliptic/ec_shortweierstrass_batch_ops.nim:188-190 (and similar in ec_twistededwards_batch_ops.nim)
**Severity:** Low
**Confidence:** 0.8

**Diff Under Review:**
```diff
+func batchAffine_vartime*[F, G](
+       affs: ptr UncheckedArray[EC_ShortW_Aff[F, G]],
+       projs: ptr UncheckedArray[EC_ShortW_Prj[F, G]],
+       N: int) {.tags:[VarTime], meter.} =
+  if N <= 0:
+    return
```

**Issue:** **The N≤0 early-return guard in `batchAffine_vartime` is never explicitly tested**

The `run_EC_affine_conversion` test template in `tests/math_elliptic_curves/t_ec_template.nim` covers batch sizes 1, 2, 10, and 16. The N≤0 guard is important for robustness but has no explicit test. If the guard is accidentally removed or its condition changed (e.g., `N < 0` instead of `N <= 0`), it would cause crashes on zero-length batches.

**Suggested Test:** Add a boundary test:
```nim
proc testBatchAffine_vartime_Empty() =
  var affs: array[0, EC_ShortW_Aff[Fp[BLS12_381], G1]]
  var projs: array[0, EC_ShortW_Prj[Fp[BLS12_381], G1]]
  affs.batchAffine_vartime(projs)  # should not crash
```

---

### [COVERAGE] COV-B-006: `kzg_coset_prove` internal error paths not focused-tested - kzg_multiproofs.nim:717-809

**Location:** constantine/commitments/kzg_multiproofs.nim:717-809
**Severity:** Low
**Confidence:** 0.7

**Diff Under Review:**
```diff
-  for offset in 0 ..< L:
-    let status = toeplitzMatVecMulPreFFT(...)
-    doAssert status == FFT_Success, "FK20 toeplitzMatVecMulPreFFT failed at offset " & $offset
+  var accum: ToeplitzAccumulator[...]
+  let status = accum.init(fr_fft_desc, ec_fft_desc, CDS, L)
+  doAssert status == Toeplitz_Success, "Internal error: Toeplitz accumulator init failed: " & $status
+  for offset in 0 ..< L:
+    let status = accum.accumulate(circulant.toOpenArray(CDS), polyphaseSpectrumBank[offset])
+    doAssert status == Toeplitz_Success, "Internal error: Toeplitz accumulator failed at offset " & $offset
+  let status2 = accum.finish(u.toOpenArray(CDS))
+  doAssert status2 == Toeplitz_Success, "Internal error: Toeplitz accumulator finish failed: " & $status2
```

**Issue:** **The `kzg_coset_prove` function's error assertions are exercised only through happy-path integration tests**

The existing tests (`testFK20SingleProofs`, `testFK20MultiProofs`, `testNonOptimizedCosetProofs`) all use valid inputs, so the `doAssert` error paths in `kzg_coset_prove` are never triggered. This is acceptable for production code where assertions are defensive, but it means:
- If the accumulator init/accumulate/finish return non-success unexpectedly, the error message quality is untested
- The `toeplitzMatVecMul` function's error paths (FFT failures) are similarly untested

**Suggested Test:** A unit test that deliberately passes malformed FFT descriptors to `toeplitzMatVecMul` and verifies it returns `Toeplitz_MismatchedSizes` or similar (rather than asserting).

---

### [COVERAGE] COV-B-007: `computePolyphaseDecompositionFourier` in-place IFFT path tested only end-to-end - kzg_multiproofs.nim:659-715

**Location:** constantine/commitments/kzg_multiproofs.nim:659-715
**Severity:** Informational
**Confidence:** 0.6

**Diff Under Review:**
```diff
-  let polyphaseComponent = allocHeapArrayAligned(..., CDS, 64)
-  # ... fill polyphaseComponent ...
-  result = ec_fft_nn(ecfft_desc, polyphaseSpectrum, polyphaseComponent.toOpenArray(CDS))
-  freeHeapAligned(polyphaseComponent)
+  # Extract polyphase component directly into output buffer
+  polyphaseSpectrum[i].fromAffine(powers_of_tau.coefs[j])
+  # ... 
+  # FFT in-place
+  result = ec_fft_nn(ecfft_desc, polyphaseSpectrum, polyphaseSpectrum)
```

**Issue:** **The in-place `ec_fft_nn` path for polyphase decomposition is tested only through end-to-end FK20 tests**

The function was refactored from two-buffer (input → output) to in-place FFT. The end-to-end tests in `t_kzg_multiproofs.nim` verify the final FK20 proofs are correct, which transitively validates this change. However, there is no unit-level test that isolates the polyphase decomposition with in-place FFT.

Additionally, the outer function `computePolyphaseDecompositionFourier` now allocates a temporary Jacobian buffer and does a single `batchAffine_vartime` over all L×CDS points instead of per-offset conversion. This is an optimization that is validated by end-to-end tests but has no focused correctness test.

**Suggested Test:** A unit test that compares the output of the offset-level `computePolyphaseDecompositionFourierOffset` (with in-place FFT) against a known reference. This would catch any regression in the in-place FFT aliasing behavior specific to this use pattern.

## Positive Changes

1. **`batchAffine_vartime` receives comprehensive tests** — `tests/math_elliptic_curves/t_ec_conversion.nim` now tests `batchAffine_vartime` across Short Weierstrass (Jacobian and Projective) for BN254 and BLS12-381 (G1 and G2), plus Twisted Edwards for Bandersnatch and Banderwagon. Tests cover single-element, all-neutral, mixed infinity, and varied batch sizes (2, 10, 16).

2. **`ToeplitzAccumulator` error-path tests** — `tests/math_matrix/t_toeplitz.nim` adds `testToeplitzAccumulatorInitErrors()` and `testToeplitzAccumulatorFinishErrors()`, covering zero-size, non-power-of-2, and negative-size inputs.

3. **`checkCirculant` r=1 boundary test** — New `testCheckCirculantR1()` specifically tests the edge case where r=1 and the `r+1 < k2` bounds check matters.

4. **`testToeplitz` now covers size 16** — Added `testToeplitz(16)` alongside existing 4 and 8 size tests, expanding coverage of the accumulator with larger dimensions.
