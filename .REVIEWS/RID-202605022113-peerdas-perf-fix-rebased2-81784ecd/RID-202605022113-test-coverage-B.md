---
**Branch:** `master` → `peerdas-perf-fix-rebased2` (commit `81784ecd`)
**Diff file:** `.REVIEWS/RID-202605022113-peerdas-perf-fix-rebased2-81784ecd/RID-202605022113-changes_under_review.diff`
**Date:** 2026-05-02
**Reviewer:** Test Coverage Analyst (Pass B)
**Scope:** PeerDAS performance optimization: ToeplitzAccumulator API, batchAffine_vartime, in-place FFT, polyphase spectrum affine conversion, checkCirculant boundary fix, matrix transpose module
**Focus:** Missing tests, happy-path only, boundary gaps, negative tests, regression risk
---

# Test Coverage Review (Pass B)

## Summary

| ID | Severity | Confidence | File | Issue |
|----|----------|------------|------|-------|
| COV-B-001 | High | 0.9 | constantine/math/matrix/toeplitz.nim | `ToeplitzAccumulator.accumulate()` error path has no test |
| COV-B-002 | High | 0.9 | constantine/math/polynomials/fft_common.nim | `bit_reversal_permutation` aliasing detection path untested |
| COV-B-003 | Medium | 0.9 | constantine/math/matrix/toeplitz.nim | `ToeplitzAccumulator.init()` double-init defensive cleanup untested |
| COV-B-004 | Medium | 0.9 | constantine/math/matrix/transpose.nim | Entire new module has no tests |
| COV-B-005 | Medium | 0.9 | constantine/math/matrix/toeplitz.nim | `checkCirculant` boundary fix for `r=2` (index `r+1`) untested |
| COV-B-006 | Medium | 0.8 | constantine/math/matrix/toeplitz.nim | `ToeplitzAccumulator` end-to-end correctness not verified against naive |
| COV-B-007 | Medium | 0.7 | constantine/commitments/kzg_multiproofs.nim | `computeAggRandScaledInterpoly` assertion paths untested by negative tests |
| COV-B-008 | Low | 0.7 | constantine/math/matrix/toeplitz.nim | `ToeplitzAccumulator.finish()` `sizeof(F) == sizeof(F.getBigInt())` static assertion not tested |
| COV-B-009 | Informational | 0.6 | constantine/commitments/kzg_multiproofs.nim | `kzg_coset_prove` integration tested only with FK20 polyphase, not raw ToeplitzAccumulator |

**Key takeaways:**
1. The `ToeplitzAccumulator` new API has error-path tests for `init()` and `finish()`, but the critical middle step `accumulate()` has no error-path test — size mismatch and offset-exceeded cases are unverified.
2. The `bit_reversal_permutation` aliasing detection (new `dst == src` branch) in `fft_common.nim` is an entirely new code path with no dedicated test.
3. The new `matrix/transpose.nim` module is completely untested.
4. The `checkCirculant` boundary fix for the `r+1` index is tested only for `r=1` (where `r+1` is out of bounds and not checked), not for `r=2` (where `r+1 == 3` is the boundary that is actually checked).

## Findings

### [COVERAGE] COV-B-001: `ToeplitzAccumulator.accumulate()` error path has no test - constantine/math/matrix/toeplitz.nim

**Location:** `constantine/math/matrix/toeplitz.nim` (lines 1626-1647 in diff; new `accumulate` proc)
**Severity:** High
**Confidence:** 0.9

**Diff Under Review:**
```diff
 proc accumulate*[EC, ECaff, F](
   ctx: var ToeplitzAccumulator[EC, ECaff, F],
   circulant: openArray[F],
   vFft: openArray[ECaff]
 ): ToeplitzStatus {.raises: [], meter.} =
   ## Accumulate FFT(circulant) and vFft for position ctx.offset
   let n = ctx.size
-  if n == 0 or circulant.len != n or vFft.len != n or ctx.offset >= ctx.L:
+    return Toeplitz_MismatchedSizes
```

**Issue: `accumulate()` error path untested**

The `ToeplitzAccumulator` object is the central new abstraction in this diff. The `accumulate()` method has a validation gate that returns `Toeplitz_MismatchedSizes` for four failure conditions:
1. `n == 0` (accumulator not initialized)
2. `circulant.len != n` (circulant size mismatch)
3. `vFft.len != n` (vector size mismatch)
4. `ctx.offset >= ctx.L` (too many accumulate calls)

None of these are tested. The existing `testToeplitzAccumulatorInitErrors()` tests `init()` and `testToeplitzAccumulatorFinishErrors()` tests `finish()`, but `accumulate()` sits between them with zero error-path coverage. This is a regression risk: if the validation logic has a bug, production code calling `accumulate()` with wrong parameters would silently produce garbage results (the FFT + transpose write would proceed with bad data).

**Suggested Test:**
```nim
proc testToeplitzAccumulatorAccumulateErrors() =
  let fftSize = 128
  let frDesc = createFFTDescriptor(Fr[BLS12_381], fftSize)
  let ecDesc = createFFTDescriptor(BLS12_381_G1_Prj, Fr[BLS12_381], fftSize)
  var acc: ToeplitzAccumulator[BLS12_381_G1_Prj, G1Aff, Fr[BLS12_381]]
  
  # Test on uninitialized accumulator (n == 0)
  var circ = newSeq[Fr[BLS12_381]](4)
  var pts = newSeq[G1Aff](4)
  doAssert acc.accumulate(circ, pts) == Toeplitz_MismatchedSizes
  
  # Valid init
  doAssert acc.init(frDesc, ecDesc, size = 4, L = 2) == Toeplitz_Success
  
  # Circulant size mismatch
  var circWrong = newSeq[Fr[BLS12_381]](8)
  doAssert acc.accumulate(circWrong, pts) == Toeplitz_MismatchedSizes
  
  # Vector size mismatch
  var ptsWrong = newSeq[G1Aff](8)
  doAssert acc.accumulate(circ, ptsWrong) == Toeplitz_MismatchedSizes
  
  # Too many accumulate calls (offset >= L)
  doAssert acc.accumulate(circ, pts) == Toeplitz_Success  # offset=0, OK
  doAssert acc.accumulate(circ, pts) == Toeplitz_Success  # offset=1, OK
  doAssert acc.accumulate(circ, pts) == Toeplitz_MismatchedSizes  # offset=2, L=2, FAIL
```

---

### [COVERAGE] COV-B-002: `bit_reversal_permutation` aliasing detection path untested - constantine/math/polynomials/fft_common.nim

**Location:** `constantine/math/polynomials/fft_common.nim` (lines 1921-1936 in diff)
**Severity:** High
**Confidence:** 0.9

**Diff Under Review:**
```diff
 func bit_reversal_permutation*[T](dst: var openArray[T], src: openArray[T]) =
   ## Out-of-place bit reversal permutation with aliasing detection.
   if dst[0].addr == src[0].addr:
     # Alias: allocate temp, permute to temp, copy back
     var tmp = allocHeapArrayAligned(T, src.len, alignment = 64)
     bit_reversal_permutation_noalias(tmp.toOpenArray(0, src.len-1), src)
     copyMem(dst[0].addr, tmp[0].addr, src.len * sizeof(T))
     freeHeapAligned(tmp)
   else:
     bit_reversal_permutation_noalias(dst, src)
```

**Issue: New aliasing detection code path has no test**

This is a behavioral change: the two-argument `bit_reversal_permutation(dst, src)` previously required non-aliased inputs (it had a `{.noalias.}` pragma). Now it detects aliasing at runtime and uses a temporary buffer. However, the aliasing path (`dst[0].addr == src[0].addr`) is never tested.

The existing `t_bit_reversal.nim` tests call `bit_reversal_permutation(dst, src)` with `dst` and `src` as separate arrays (line 119, 181, 195, 209, 229), so they always hit the `else` branch. The in-place variant `buf.bit_reversal_permutation()` is tested, but that uses a separate code path (single-argument overload that allocates its own temporary).

This means the aliasing detection path — which is the *new* code introduced by this change — has zero coverage. If the `copyMem` size calculation or the temp allocation has a bug, it would go undetected.

**Suggested Test:**
```nim
proc testBitReversalAliasing[T]() =
  echo "Testing bit_reversal_permutation with aliasing (dst == src)..."
  for logN in 1 .. 8:
    let N = 1 shl logN
    var buf = newSeq[T](N)
    for i in 0 ..< N:
      buf[i] = T(i)
    
    # Call out-of-place variant with same array for both dst and src
    bit_reversal_permutation(buf.toOpenArray(0, N-1), buf.toOpenArray(0, N-1))
    
    for i in 0 ..< N:
      let rev_i = reverseBits(uint32(i), uint32(logN))
      doAssert buf[i] == T(rev_i),
        "Aliased bit-reversal failed at logN=" & $logN & " index=" & $i
  echo "  ✓ Aliasing test PASSED"
```

---

### [COVERAGE] COV-B-003: `ToeplitzAccumulator.init()` double-init defensive cleanup untested - constantine/math/matrix/toeplitz.nim

**Location:** `constantine/math/matrix/toeplitz.nim` (lines 1537-1606 in diff)
**Severity:** Medium
**Confidence:** 0.9

**Diff Under Review:**
```diff
 proc init*[EC, ECaff, F](
   ctx: var ToeplitzAccumulator[EC, ECaff, F],
   frFftDesc: FrFFT_Descriptor[F],
   ecFftDesc: ECFFT_Descriptor[EC],
   size: int,
   L: int
 ): ToeplitzStatus {.raises: [], meter.} =
   # Free existing allocations (defensive: handles accidental double-init)
   if not ctx.coeffs.isNil():
     freeHeapAligned(ctx.coeffs)
   if not ctx.points.isNil():
     freeHeapAligned(ctx.points)
   if not ctx.scratchScalars.isNil():
     freeHeapAligned(ctx.scratchScalars)
   ...
   return Toeplitz_Success
```

**Issue: Double-init path not tested**

The `init()` method includes defensive code to free existing allocations before re-initializing. This prevents memory leaks if `init()` is called twice on the same object. However, this path is never exercised in tests. The existing `testToeplitzAccumulatorInitErrors()` only tests error conditions on fresh objects.

While Nim's `=destroy` would eventually clean up on scope exit, calling `init()` twice is a reasonable usage pattern (re-use of a long-lived accumulator), and the defensive free logic should be verified to prevent memory leaks.

**Suggested Test:**
```nim
proc testToeplitzAccumulatorDoubleInit() =
  let fftSize = 128
  let frDesc = createFFTDescriptor(Fr[BLS12_381], fftSize)
  let ecDesc = createFFTDescriptor(BLS12_381_G1_Prj, Fr[BLS12_381], fftSize)
  var acc: ToeplitzAccumulator[BLS12_381_G1_Prj, G1Aff, Fr[BLS12_381]]
  
  # First init
  doAssert acc.init(frDesc, ecDesc, size = 4, L = 2) == Toeplitz_Success
  
  # Second init (should free first allocation and re-allocate)
  doAssert acc.init(frDesc, ecDesc, size = 8, L = 4) == Toeplitz_Success
  
  # Verify the second init worked correctly
  doAssert acc.size == 8
  doAssert acc.L == 4
  # (acc will be destroyed on scope exit, freeing the second allocation)
  echo "✓ Double-init test PASSED"
```

---

### [COVERAGE] COV-B-004: Entire new `matrix/transpose.nim` module has no tests - constantine/math/matrix/transpose.nim

**Location:** `constantine/math/matrix/transpose.nim` (new file, 79 lines)
**Severity:** Medium
**Confidence:** 0.9

**Diff Under Review:**
```diff
+proc transpose*[T](dst, src: ptr UncheckedArray[T], M, N: int, blockSize: static int = 16) {.inline.} =
+  const blck = blockSize
+  for jj in countup(0, N - 1, blck):
+    for ii in countup(0, M - 1, blck):
+      for j in jj ..< min(jj + blck, N):
+        for i in ii ..< min(ii + blck, M):
+          dst[j * M + i] = src[i * N + j]
```

**Issue: New module completely untested**

The `transpose.nim` module is a new public API (`transpose*`) with a 2D tiled transposition algorithm. It has benchmark code (`bench_matrix_transpose.nim`) that exercises it for performance, but no correctness tests. Benchmarks do not validate output correctness.

The module is referenced in the diff's summary text but is not yet imported by any production code. However, the public API is exposed and should have correctness tests before being depended upon.

**Suggested Test:**
```nim
proc testTranspose() =
  const M = 4, N = 3
  var src = newSeq[int](M * N)
  var dst = newSeq[int](N * M)
  for i in 0 ..< M * N:
    src[i] = i
  dst.transpose(src, M, N)
  for i in 0 ..< M:
    for j in 0 ..< N:
      doAssert dst[j * M + i] == src[i * N + j],
        "Transpose mismatch at row=" & $i & " col=" & $j
```

---

### [COVERAGE] COV-B-005: `checkCirculant` boundary fix for `r=2` (index `r+1`) untested - constantine/math/matrix/toeplitz.nim

**Location:** `constantine/math/matrix/toeplitz.nim` (lines 1427-1429 in diff)
**Severity:** Medium
**Confidence:** 0.9

**Diff Under Review:**
```diff
-  for i in 1 .. r + 1:
+  for i in 1 .. r:
     if not circulant[i].isZero().bool:
       return false
+  # Also check index r+1 when it is in bounds (r >= 2)
+  if r + 1 < k2 and not circulant[r + 1].isZero().bool:
+    return false
```

**Issue: `r=2` boundary case not tested**

The `checkCirculant` function was fixed to handle the `r=1` case (where `r+1 == 2 == k2`, so index `r+1` is out of bounds). The new test `testCheckCirculantR1()` covers this case. However, the `r=2` case is also a boundary: when `r=2`, `k2=4`, and `r+1=3`, which is the last valid index. This is the smallest case where the `r+1` check is actually exercised (not skipped due to bounds).

The existing `testCheckCirculant()` uses `n=4` which implies `r=n=4`, not testing the `r=2` boundary. The `testCheckCirculantR1()` uses `n=2` which means `r=1`, where `r+1` is out of bounds and the new check is skipped.

**Suggested Test:**
```nim
proc testCheckCirculantR2() =
  # r=2 means circulant length = 2*r = 4, so r+1=3 is in bounds
  var poly = newSeq[Fr[BLS12_381]](4)  # n=4
  var circ = newSeq[Fr[BLS12_381]](4)  # 2*r = 4
  
  for i in 0 ..< 4:
    poly[i].fromUint(uint64(i + 1))
  
  makeCirculantMatrix(circ, poly, 0, 1)
  doAssert checkCirculant(circ, poly, 0, 1), "Valid r=2 circulant should pass"
  
  # Corrupt index r+1 = 3
  circ[3].fromUint(999)
  doAssert not checkCirculant(circ, poly, 0, 1), "Corrupted index r+1 should be detected"
  
  echo "✓ checkCirculant r=2 PASSED"
```

---

### [COVERAGE] COV-B-006: `ToeplitzAccumulator` end-to-end correctness not verified against naive - constantine/math/matrix/toeplitz.nim

**Location:** `constantine/math/matrix/toeplitz.nim` (entire `ToeplitzAccumulator` type and procs)
**Severity:** Medium
**Confidence:** 0.8

**Issue: Accumulator correctness not independently verified**

The existing `testToeplitz(n)` function tests the high-level `toeplitzMatVecMul` API against a naive O(n²) reference. While `toeplitzMatVecMul` internally uses the `ToeplitzAccumulator`, this is an indirect test. The accumulator's core algorithm (MSM + IFFT) replaces the old Hadamard product + scalar multiplication pattern, which is a fundamental algorithmic change.

There is no test that directly exercises `init()` → `accumulate()` (with L > 1) → `finish()` and verifies the result against a known-correct reference. The KZG multiproof tests (`t_kzg_multiproofs.nim`) exercise this through the full `kzg_coset_prove` pipeline, but that masks any Toeplitz-specific bugs with the complexity of the full FK20 pipeline.

**Suggested Test:**
```nim
proc testToeplitzAccumulatorEndToEnd(n: static int, L: static int) =
  ## Verify accumulator produces same result as naive Toeplitz multiplication
  ## for each L accumulation step
  let fftSize = 2 * n
  let frDesc = createFFTDescriptor(Fr[BLS12_381], fftSize)
  let ecDesc = createFFTDescriptor(BLS12_381_G1_Prj, Fr[BLS12_381], fftSize)
  
  var acc: ToeplitzAccumulator[BLS12_381_G1_Prj, G1Aff, Fr[BLS12_381]]
  doAssert acc.init(frDesc, ecDesc, size = n, L = L) == Toeplitz_Success
  
  # ... accumulate L circulants and verify against naive ...
```

---

### [COVERAGE] COV-B-007: `computeAggRandScaledInterpoly` assertion paths untested - constantine/commitments/kzg_multiproofs.nim

**Location:** `constantine/commitments/kzg_multiproofs.nim` (lines 519-555 in diff)
**Severity:** Medium
**Confidence:** 0.7

**Diff Under Review:**
```diff
-  if evals.len != evalsCols.len or linearIndepRandNumbers.len < evalsCols.len:
-    return false
+  doAssert evals.len == evalsCols.len, "Internal error: evals and evalsCols must have same length"
+  doAssert linearIndepRandNumbers.len >= evalsCols.len, "Internal error: linearIndepRandNumbers must cover all evals"
...
-  if not interpoly.computeAggRandScaledInterpoly(...):
-    return false
+  interpoly.computeAggRandScaledInterpoly(...)
```

**Issue: Function changed from error-returning to assertion-based; negative tests removed**

The `computeAggRandScaledInterpoly` function was changed from returning `bool` (with explicit error checks) to using `doAssert` statements. This removes the ability of callers to handle errors gracefully — instead, bad inputs will assert-fail. The calling code in `kzg_coset_verify_batch` was also updated to remove the `if not` check.

The existing `kzg_coset_verify_batch` tests (including negative tests like `testKzgCosetVerifyBatchNegative_SwitchProofs`) test that *batch verification fails* when proofs are wrong, but they never test the assertion paths inside `computeAggRandScaledInterpoly`. If someone calls the batch verify API with mismatched input lengths, they get an assert failure (debug mode) or silent incorrect behavior (release mode).

This is a behavioral regression risk: the function no longer validates its inputs in release mode.

**Suggested Test:**
Add a test that verifies the function is called with valid inputs from all production call sites. Alternatively, if the doAssert pattern is intentional (caller guarantees validity), add a comment documenting this contract.

---

### [COVERAGE] COV-B-008: `sizeof(F) == sizeof(F.getBigInt())` static assertion not tested - constantine/math/matrix/toeplitz.nim

**Location:** `constantine/math/matrix/toeplitz.nim` (line 1661 in diff)
**Severity:** Low
**Confidence:** 0.7

**Diff Under Review:**
```diff
   static: doAssert sizeof(F) == sizeof(F.getBigInt()), "scratchScalars cast requires sizeof(F) == sizeof(F.getBigInt())"
   
   let scalars = cast[ptr UncheckedArray[F.getBigInt()]](ctx.scratchScalars)
```

**Issue: Unsafe cast precondition not tested across field types**

The `finish()` method casts `scratchScalars` (typed as `F`) to `F.getBigInt()` via `cast[ptr UncheckedArray[...]]`. This is an unsafe pointer reinterpretation that relies on both types having the same size. The `static: doAssert` catches this at compile time, but only for the field type that the test is compiled with.

While this is a `static` assertion (compile-time), it's worth noting that the test suite only exercises `Fr[BLS12_381]`. If the `ToeplitzAccumulator` is ever instantiated with a different field type where this assumption breaks, the compile-time assertion would only fire when that instantiation is compiled.

This is informational: the static assertion is the right approach for Nim, but it's worth noting the gap.

**Suggested Test:** N/A (static assertion is compile-time). However, consider adding a comment to the test explaining the tested field type.

---

### [COVERAGE] COV-B-009: `kzg_coset_prove` tested only through FK20 polyphase, not raw accumulator - constantine/commitments/kzg_multiproofs.nim

**Location:** `constantine/commitments/kzg_multiproofs.nim` (lines 717-829 in diff)
**Severity:** Informational
**Confidence:** 0.6

**Issue: `kzg_coset_prove` tested end-to-end but accumulator internal path not isolated**

The `kzg_coset_prove` function is extensively tested through `testFK20SingleProofs`, `testFK20MultiProofs`, and `testNonOptimizedCosetProofs`. These verify end-to-end correctness (proofs verify correctly). However, they do not isolate the `ToeplitzAccumulator` path within `kzg_coset_prove` from the surrounding FK20 pipeline (polyphase decomposition, commitment computation, etc.).

This is not a critical gap — the end-to-end tests provide strong regression protection — but it means a bug specifically in the accumulator's interaction with `kzg_coset_prove` (e.g., buffer reuse in the in-place FFT at line 821) could only be caught through the full pipeline test.

**Suggested Test:** Consider adding a unit test that directly verifies the accumulator's contribution: compute the accumulator output independently and compare it against the naive FK20 accumulation.

---

## Positive Changes

1. **`batchAffine_vartime` tests are comprehensive.** The diff adds extensive tests for the new vartime batch conversion functions across BN254 (G1/G2), BLS12-381 (G1/G2), and Bandersnatch/Banderwagon curves, with coverage for single element, all-neutral, varied batch sizes, and infinite points. This is a model example of regression-prevention testing.

2. **`ToeplitzAccumulator.init()` error paths are well tested.** The `testToeplitzAccumulatorInitErrors()` covers size=0, L=0, non-power-of-2, and negative size — all the entry-point validation cases.

3. **`ToeplitzAccumulator.finish()` early-return tested.** The `testToeplitzAccumulatorFinishErrors()` verifies that calling `finish()` without any `accumulate()` calls correctly returns `Toeplitz_MismatchedSizes`.

4. **`checkCirculant` r=1 edge case tested.** The new `testCheckCirculantR1()` specifically covers the boundary case that the `checkCirculant` fix was designed to handle.

5. **FK20 proof verification remains comprehensive.** The `t_kzg_multiproofs.nim` tests exercise `kzg_coset_prove` with both L=1 and L>1, including multi-commitment and negative tests (fake proofs, switched proofs, switched evals).
