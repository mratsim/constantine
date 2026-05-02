---
**Branch:** `master` → `peerdas-perf-fix-rebased2` (commit `81784ecd`)
**Diff file:** `.REVIEWS/RID-202605022113-peerdas-perf-fix-rebased2-81784ecd/RID-202605022113-changes_under_review.diff`
**Date:** 2026-05-02
**Reviewer:** Test Coverage Analyst (Pass A)
**Scope:** PeerDAS performance fixes: new `batchAffine_vartime`, `ToeplitzAccumulator`, matrix transpose, bit-reversal aliasing, `kzg_coset_prove` rewrite
**Focus:** Missing tests, happy-path only, boundary gaps, negative tests, regression risk
---

# Test Coverage Review (Pass A)

## Summary

| ID | Severity | Confidence | File | Issue |
|----|----------|------------|------|-------|
| COV-A-001 | High | 1.0 | constantine/math/matrix/transpose.nim | New production module with zero test coverage |
| COV-A-002 | High | 0.9 | constantine/math/matrix/toeplitz.nim | `ToeplitzAccumulator.accumulate` error paths untested |
| COV-A-003 | Medium | 0.9 | constantine/math/polynomials/fft_common.nim | `bit_reversal_permutation(dst, src)` aliasing path untested |
| COV-A-004 | Medium | 0.9 | constantine/commitments/kzg_multiproofs.nim | `computeAggRandScaledInterpoly` error assertions untested |
| COV-A-005 | Medium | 0.8 | constantine/math/elliptic/ec_shortweierstrass_batch_ops.nim | `batchAffine_vartime` N=0 early-return untested |
| COV-A-006 | Medium | 0.8 | constantine/math/matrix/toeplitz.nim | `ToeplitzAccumulator` multi-accumulate correctness not directly verified |
| COV-A-007 | Low | 0.9 | constantine/math/matrix/toeplitz.nim | `checkCirculant` r+1 boundary change not tested at edge |
| COV-A-008 | Low | 0.7 | constantine/math/elliptic/ec_twistededwards_batch_ops.nim | Twisted Edwards `batchAffine` refactoring (zero-tracking change) lacks dedicated regression test |

**Key takeaways:**
1. The new `transpose.nim` module is entirely untested — a cache-critical optimization with no safety net.
2. `ToeplitzAccumulator` is the core of the FK20 rewrite but its `accumulate` method has no error-path tests, and its multi-accumulate happy path is only indirectly tested through `toeplitzMatVecMul`.
3. The `bit_reversal_permutation` aliasing detection (new two-arg overload) is untested — the existing in-place tests exercise a different single-arg overload.
4. `batchAffine_vartime` gains good coverage for normal and infinite-point cases, but the N=0 boundary guard added to the code is not tested.

## Findings

### [COVERAGE] COV-A-001: New matrix transpose module has zero test coverage - constantine/math/matrix/transpose.nim

**Location:** constantine/math/matrix/transpose.nim:1-80
**Severity:** High
**Confidence:** 1.0

**Diff Under Review:**
```diff
diff --git a/constantine/math/matrix/transpose.nim b/constantine/math/matrix/transpose.nim
new file mode 100644
index 00000000..6dcccec5
--- /dev/null
+++ b/constantine/math/matrix/transpose.nim
@@ -0,0 +1,79 @@
+# Optimized Matrix Transposition
+# Benchmark results (512x512 matrix, 32-byte elements):
+# - 2D Blocked (block=16):   20.4 GB/s  [WINNER]
+# - Naive sequential:        10.1 GB/s
+
+proc transpose*[T](dst, src: ptr UncheckedArray[T], M, N: int, blockSize: static int = 16) {.inline.} =
+  const blck = blockSize
+  for jj in countup(0, N - 1, blck):
+    for ii in countup(0, M - 1, blck):
+      for j in jj ..< min(jj + blck, N):
+        for i in ii ..< min(ii + blck, M):
+          dst[j * M + i] = src[i * N + j]
```

**Issue:** **New production module with no tests at all**

A brand-new file providing cache-optimized 2D tiled matrix transposition. There is a benchmark file (`benchmarks/bench_matrix_transpose.nim`) that exercises multiple strategies and compares performance, but this is not a correctness test — it does not verify that the transposed output matches a reference implementation. The `min(jj + blck, N)` and `min(ii + blck, M)` boundary guards in the inner loops are not validated by any test. A bug in tiling logic could silently produce wrong results.

**Suggested Test:** `testTranspose()` in `tests/math_matrix/t_transpose.nim` — compare output of `transpose()` against a naive implementation for various matrix sizes (square, rectangular, non-multiple-of-block-size like 513x512). Test with at least `[Fr[BLS12_381]]` element type.

---

### [COVERAGE] COV-A-002: `ToeplitzAccumulator.accumulate` error paths untested - constantine/math/matrix/toeplitz.nim

**Location:** constantine/math/matrix/toeplitz.nim:1626-1647
**Severity:** High
**Confidence:** 0.9

**Diff Under Review:**
```diff
+proc accumulate*[EC, ECaff, F](
+  ctx: var ToeplitzAccumulator[EC, ECaff, F],
+  circulant: openArray[F],
+  vFft: openArray[ECaff]
+): ToeplitzStatus {.raises: [], meter.} =
+  let n = ctx.size
+  if n == 0 or circulant.len != n or vFft.len != n or ctx.offset >= ctx.L:
+    return Toeplitz_MismatchedSizes
+
+  block HappyPath:
+    check HappyPath, fft_nn(ctx.frFftDesc, ctx.scratchScalars.toOpenArray(n), circulant)
+    for i in 0 ..< n:
+      ctx.coeffs[i * ctx.L + ctx.offset] = ctx.scratchScalars[i]
+      ctx.points[i * ctx.L + ctx.offset] = vFft[i]
+
+    ctx.offset += 1
+    result = Toeplitz_Success
```

**Issue:** **`accumulate` error paths have no dedicated test**

The `accumulate` method has four distinct error conditions:
1. `n == 0` (accumulator not initialized)
2. `circulant.len != n` (size mismatch)
3. `vFft.len != n` (size mismatch)
4. `ctx.offset >= ctx.L` (too many accumulates)

The existing test file (`tests/math_matrix/t_toeplitz.nim`) has `testToeplitzAccumulatorInitErrors()` and `testToeplitzAccumulatorFinishErrors()` but no `testToeplitzAccumulatorAccumulateErrors()`. These error paths are reachable in production and returning the wrong error code could mask real problems.

**Suggested Test:** `testToeplitzAccumulatorAccumulateErrors()` — verify each of the four error conditions returns `Toeplitz_MismatchedSizes`. Test uninit accumulator (n==0), circulant too short, vFft too long, and calling accumulate more than L times.

---

### [COVERAGE] COV-A-003: `bit_reversal_permutation(dst, src)` aliasing detection path untested - constantine/math/polynomials/fft_common.nim

**Location:** constantine/math/polynomials/fft_common.nim:287-349
**Severity:** Medium
**Confidence:** 0.9

**Diff Under Review:**
```diff
-func bit_reversal_permutation*[T](dst{.noalias.}: var openArray[T], src{.noalias.}: openArray[T]) {.inline.} =
+func bit_reversal_permutation_noalias*[T](dst{.noalias.}: var openArray[T], src{.noalias.}: openArray[T]) {.inline.} =

+func bit_reversal_permutation*[T](dst: var openArray[T], src: openArray[T]) =
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

**Issue:** **Aliasing detection branch in two-argument `bit_reversal_permutation(dst, src)` is never tested**

The renamed `bit_reversal_permutation_noalias` (previously `bit_reversal_permutation` with `{.noalias.}`) is the non-aliasing fast path. The new `bit_reversal_permutation(dst, src)` overload adds an aliasing check (`if dst[0].addr == src[0].addr`). 

The existing test file (`tests/math_polynomials/t_bit_reversal.nim`) tests:
- Naive out-of-place (always separate dst/src)
- COBRA out-of-place (always separate dst/src)
- In-place `buf.bit_reversal_permutation()` (single-arg overload, which allocates its own temp internally)
- Auto out-of-place `bit_reversal_permutation(dst, src)` where dst and src are always different arrays

The aliasing branch (`dst[0].addr == src[0].addr`) in the two-arg overload is never exercised. This is critical because this path is used internally by `ec_fft_nn` when `output` and `vals` are the same buffer (as noted in the diff: `ec_fft_desc.ec_fft_nn(u.toOpenArray(CDS), u.toOpenArray(CDS))`).

**Suggested Test:** In `tests/math_polynomials/t_bit_reversal.nim`, add `testAliasingTwoArgBRP[T]()` — pass the same array as both `dst` and `src` to `bit_reversal_permutation(dst, src)`, verify correctness. Test with `int64` and `Fr[BLS12_381]`.

---

### [COVERAGE] COV-A-004: `computeAggRandScaledInterpoly` error assertions not tested - constantine/commitments/kzg_multiproofs.nim

**Location:** constantine/commitments/kzg_multiproofs.nim:519-555
**Severity:** Medium
**Confidence:** 0.9

**Diff Under Review:**
```diff
-      N: static int): bool {.meter.} =
+      N: static int) {.meter.} =
   ## Compute ∑ₖrᵏIₖ(X)
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

**Issue:** **Error conditions converted from returnable `false` to `doAssert` with no test exercising them**

The function `computeAggRandScaledInterpoly` changed from returning `bool` (with `false` on invalid input) to `void` (with `doAssert`). Three error conditions were converted:
1. `evals.len != evalsCols.len`
2. `linearIndepRandNumbers.len < evalsCols.len`
3. `c < 0 or c >= NumCols` (column index out of bounds)

This function is called internally by `kzg_coset_verify_batch`. While `kzg_coset_verify_batch` has extensive negative tests (fake proofs, switched evals, etc.), none of these tests deliberately trigger the `computeAggRandScaledInterpoly` assertions. If these doAsserts are wrong (e.g., too strict or too loose), no test would catch it. In production, `doAssert` may be compiled out with `-d:release` without `-d:debug`, meaning invalid inputs silently produce wrong results rather than being caught.

**Suggested Test:** Add a test that deliberately passes mismatched `evals`/`evalsCols` lengths and negative column indices to `kzg_coset_verify_batch`, verifying that the `doAssert` fires (when compiled with `-d:debug`). This confirms the assertions are live and correctly positioned.

---

### [COVERAGE] COV-A-005: `batchAffine_vartime` N=0 early-return not tested - constantine/math/elliptic/ec_shortweierstrass_batch_ops.nim

**Location:** constantine/math/elliptic/ec_shortweierstrass_batch_ops.nim:1025-1031
**Severity:** Medium
**Confidence:** 0.9

**Diff Under Review:**
```diff
 func batchAffine*[F, G](
        affs: ptr UncheckedArray[EC_ShortW_Aff[F, G]],
        projs: ptr UncheckedArray[EC_ShortW_Prj[F, G]],
        N: int) {.meter.} =
+  if N <= 0:
+    return
 ...
+func batchAffine_vartime*[F, G](
+       affs: ptr UncheckedArray[EC_ShortW_Aff[F, G]],
+       projs: ptr UncheckedArray[EC_ShortW_Prj[F, G]],
+       N: int) {.tags:[VarTime], meter.} =
+  if N <= 0:
+    return
 ...
+func batchAffine_vartime*[F, G](
+       affs: ptr UncheckedArray[EC_ShortW_Aff[F, G]],
+       jacs: ptr UncheckedArray[EC_ShortW_Jac[F, G]],
+       N: int) {.tags:[VarTime], meter.} =
+  if N <= 0:
+    return
```

**Issue:** **N=0 early-return guard added to both `batchAffine` and `batchAffine_vartime` but not tested**

The diff adds `if N <= 0: return` guards to:
- `batchAffine` (projective → affine, Jacobian → affine) 
- `batchAffine_vartime` (projective → affine, Jacobian → affine)

The existing test template (`t_ec_template.nim`) tests batch sizes of 1, 2, 10, and 16. It does not test `N=0` or `N=-1`. While the `N <= 0` early return is straightforward, the same guard was added to the existing `batchAffine` (not just `batchAffine_vartime`), making this a behavior change for the original function as well. Without a test, we cannot confirm the guard prevents out-of-bounds access on `affs[0]` or `projs[0]`.

**Suggested Test:** Add `batchAffine_vartime` with `N=0` assertion in `t_ec_template.nim` — call with empty arrays or explicitly pass N=0 and verify no crash.

---

### [COVERAGE] COV-A-006: `ToeplitzAccumulator` multi-accumulate path not directly verified - constantine/math/matrix/toeplitz.nim

**Location:** constantine/math/matrix/toeplitz.nim:1537-1701
**Severity:** Medium
**Confidence:** 0.8

**Diff Under Review:**
```diff
+proc init*[EC, ECaff, F](ctx: var ToeplitzAccumulator[EC, ECaff, F], ...): ToeplitzStatus
+proc accumulate*[EC, ECaff, F](ctx: var ToeplitzAccumulator[EC, ECaff, F], ...): ToeplitzStatus
+proc finish*[EC, ECaff, F](ctx: var ToeplitzAccumulator[EC, ECaff, F], output: var openArray[EC]): ToeplitzStatus
```

**Issue:** **Multi-accumulate happy path correctness not directly tested**

The `ToeplitzAccumulator` is designed for L > 1 use cases (L=64 in production PeerDAS). The existing `testToeplitz(n)` in `t_toeplitz.nim` tests `toeplitzMatVecMul` which internally uses the accumulator with `L=1` only. The multi-accumulate pattern (`init(L>1)` → N×`accumulate()` → `finish()`) is the core of the FK20 performance improvement, but it is not tested as a standalone sequence.

The `kzg_coset_prove` rewrite exercises this path indirectly, and `testFK20SingleProofs`/`testFK20MultiProofs` provide regression testing. However, a bug in the accumulator's transposed storage layout (`ctx.coeffs[i * ctx.L + ctx.offset]`) or MSM accumulation (`multiScalarMul_vartime`) could produce wrong results that are masked by the high-level KZG verification test.

**Suggested Test:** `testToeplitzAccumulatorMultiAccumulate()` — use `ToeplitzAccumulator` directly with L=4 or L=8, verify the accumulated result matches manual computation (sum of L individual Toeplitz multiplications).

---

### [COVERAGE] COV-A-007: `checkCirculant` r+1 boundary change not tested at edge - constantine/math/matrix/toeplitz.nim

**Location:** constantine/math/matrix/toeplitz.nim:71-78
**Severity:** Low
**Confidence:** 0.9

**Diff Under Review:**
```diff
-  for i in 1 .. r + 1:
-    if not circulant[i].isZero().bool:
-      return false
+  for i in 1 .. r:
+    if not circulant[i].isZero().bool:
+      return false
+  # Also check index r+1 when it is in bounds (r >= 2)
+  if r + 1 < k2 and not circulant[r + 1].isZero().bool:
+    return false
```

**Issue:** **`checkCirculant` boundary change for r+1 index not tested**

The zero-check range changed from `1..r+1` (fixed range) to `1..r` + conditional `r+1` check. This means for `r=1`, the old code checked index `1..2` (two positions) while the new code checks `1..1` and then `r+1=2 < k2=2` which is false, so it checks only index 1.

The `testCheckCirculantR1()` test added in the diff tests the `r=1` case but only validates that a valid circulant passes and a corrupted one fails. It does not specifically verify that index `r+1` is checked when `r >= 2`. The boundary condition `r + 1 < k2` is a subtle change from unconditional checking.

**Suggested Test:** Extend `testCheckCirculantR1()` or add `testCheckCirculantR2()` — verify that for r=2, index r+1=3 is correctly checked for zero. Corrupt index 3 and confirm `checkCirculant` returns false.

---

### [COVERAGE] COV-A-008: Twisted Edwards `batchAffine` refactoring lacks regression test - constantine/math/elliptic/ec_twistededwards_batch_ops.nim

**Location:** constantine/math/elliptic/ec_twistededwards_batch_ops.nim:25-91
**Severity:** Low
**Confidence:** 0.7

**Diff Under Review:**
```diff
 func batchAffine*[F](
        affs: ptr UncheckedArray[EC_TwEdw_Aff[F]],
        projs: ptr UncheckedArray[EC_TwEdw_Prj[F]],
-       N: int) {.noInline, tags:[Alloca].} =
+       N: int) {.meter.} =
+  if N <= 0:
+    return
   ...
-  let zeroes = allocStackArray(SecretBool, N)
+  template zero(i: int): SecretWord =
+    affs[i].y.mres.limbs[0]
-  zeroes[0] = affs[0].x.isZero()
-  affs[0].x.csetOne(zeroes[0])
+  zero(0) = SecretWord affs[0].x.isZero()
+  affs[0].x.csetOne(SecretBool zero(0))
```

**Issue:** **Internal zero-tracking mechanism changed from stack array to inline template storage**

The Twisted Edwards `batchAffine` function was refactored to use the same zero-tracking pattern as `batchAffine_vartime` (storing zero flags in `affs[i].y.mres.limbs[0]` instead of a separate `allocStackArray(SecretBool, N)`). This changes the memory layout and computation path of the existing constant-time `batchAffine` function. The diff also removes `tags:[Alloca]` and adds `meter`.

While the `t_ec_conversion.nim` test file now calls `run_EC_affine_conversion` for Twisted Edwards with both regular and vartime modes, the regular Twisted Edwards `batchAffine` test only runs once (pre-existing), and the specific change from `allocStackArray` to inline storage is a non-trivial refactoring that could introduce subtle bugs.

**Suggested Test:** No new test needed if the existing `t_ec_conversion.nim` Twisted Edwards tests pass — the comparison against single `.affine()` conversion would catch most errors. Flagged as low confidence since this is more of a code smell check.

## Positive Changes

1. **`batchAffine_vartime` tests are well-structured** — The `t_ec_template.nim` template now supports `isVartime=true` and covers normal points, infinite points, single element, all-neutral, and varied batch sizes for Short Weierstrass (Jacobian and Projective). This is comprehensive coverage for the new vartime batch conversion.

2. **`ToeplitzAccumulator` init and finish error paths are tested** — `testToeplitzAccumulatorInitErrors()` and `testToeplitzAccumulatorFinishErrors()` in `t_toeplitz.nim` provide good error-path coverage for the constructor and destructor.

3. **`testFK20MultiProofs` provides regression coverage** — The KZG multiproofs test file validates FK20 proofs end-to-end through verification, ensuring the `kzg_coset_prove` rewrite produces correct results against known-good verification.

4. **`checkCirculant` r=1 edge case added** — The new `testCheckCirculantR1()` test directly addresses the boundary condition where the old zero-check loop would have checked out-of-bounds indices.
