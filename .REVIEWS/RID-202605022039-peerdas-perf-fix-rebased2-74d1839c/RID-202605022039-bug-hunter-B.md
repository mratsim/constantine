---
**Branch:** `master` → `peerdas-perf-fix-rebased2` (commit `74d1839c`)
**Diff file:** `.REVIEWS/RID-202605022039-peerdas-perf-fix-rebased2-74d1839c/RID-202605022039-changes_under_review.diff`
**Date:** 2026-05-02
**Reviewer:** Bug Hunter (Pass B)
**Scope:** PeerDAS performance fix — new `ToeplitzAccumulator`, `batchAffine_vartime`, polyphase spectrum bank restructuring (Jacobian → Affine), FFT tag changes, bit_reversal_permutation aliasing support
**Focus:** Runtime failures, unexpected inputs, state machine edge cases, Nim-specific issues (nil deref, bounds violations, uninitialized memory)
---

# Bug Hunter Review (Pass B)

## Summary

| ID | Severity | Confidence | File | Issue |
|----|----------|------------|------|-------|
| BUG-B-001 | High | 1.0 | `constantine/math/polynomials/fft_common.nim:311` | Undefined variable `buf` in `bit_reversal_permutation` two-parameter overload |
| BUG-B-002 | High | 1.0 | `constantine/math/polynomials/fft_common.nim:328` | Undefined variable `src` in `bit_reversal_permutation` single-parameter overload |
| BUG-B-003 | High | 0.9 | `constantine/commitments/kzg_multiproofs.nim:528-534` | Runtime input validation replaced with `doAssert` — OOB in release builds |
| BUG-B-004 | Medium | 0.9 | `constantine/commitments/kzg_multiproofs.nim:502-508` | Return type changed `bool` → `void`, callers can no longer check for errors |
| BUG-B-005 | Low | 0.7 | `constantine/math/matrix/toeplitz.nim:74-78` | Weakened zero-check coverage in `checkCirculant` for r=1 edge case |
| BUG-B-006 | Informational | 0.8 | `constantine/math/elliptic/ec_twistededwards_batch_ops.nim:237` | `Alloca` tag removed from `batchAffine` despite potential stack allocation |

**Key takeaways:**
1. Two **compile errors** in the new `bit_reversal_permutation` overloads — undefined variable references in `debug:` blocks cause compilation failure in debug builds.
2. **Security regression** in `computeAggRandScaledInterpoly`: runtime bounds checks were replaced with `doAssert`, which are stripped in release builds, potentially allowing out-of-bounds memory access.
3. The `ToeplitzAccumulator` restructuring is well-designed with proper memory management (`=destroy`, `=copy {.error.}`), but the overall architectural shift from `toeplitzMatVecMulPreFFT` is complex and increases the surface area for subtle bugs.

## Findings

### [BUG] BUG-B-001: Undefined variable `buf` in two-parameter `bit_reversal_permutation`

**Location:** `constantine/math/polynomials/fft_common.nim:311`
**Severity:** High
**Confidence:** 1.0

**Diff Under Review:**
```diff
 func bit_reversal_permutation*[T](dst: var openArray[T], src: openArray[T]) {.inline.} =
   ## Out-of-place bit reversal permutation with aliasing detection.
   ##
   ## If dst and src are the same array (aliasing), a temporary buffer is allocated.
+  debug: doAssert buf.len.uint.isPowerOf2_vartime()
   debug: doAssert dst.len == src.len
   debug: doAssert dst.len > 0
```

**Issue: Compile error — undefined variable `buf`**

The debug assertion `doAssert buf.len.uint.isPowerOf2_vartime()` references `buf`, which is **not defined** in this function. The parameters are `dst` and `src`. This was clearly a copy-paste error from the single-parameter overload below, where `buf` is the parameter name.

**Impact:** In debug builds (when the `debug` symbol is defined, which is the default Nim compilation mode), this function **will fail to compile** with a "variable not found" error. Since this function is called from `fft_ec.nim:369` and `fft_fields.nim:519`, the compilation failure propagates to all FFT-using code. In release builds (`-d:release`), the `debug:` block is compiled out, so the function silently works.

This means the branch cannot be compiled and tested in debug mode, which is the default development workflow.

**Suggested Change:**
```nim
  debug: doAssert src.len.uint.isPowerOf2_vartime()
```

---

### [BUG] BUG-B-002: Undefined variable `src` in single-parameter `bit_reversal_permutation`

**Location:** `constantine/math/polynomials/fft_common.nim:328`
**Severity:** High
**Confidence:** 1.0

**Diff Under Review:**
```diff
 func bit_reversal_permutation*[T](buf: var openArray[T]) {.inline.} =
   ## In-place bit reversal permutation.
   ##
   ## Out-of-place is at least 2x faster than in-place so dispatch to out-of-place
+  debug: doAssert src.len.uint.isPowerOf2_vartime()
   debug: doAssert buf.len > 0
```

**Issue: Compile error — undefined variable `src`**

The debug assertion `doAssert src.len.uint.isPowerOf2_vartime()` references `src`, which is **not defined** in this function. The only parameter is `buf`. This is a copy-paste error from the two-parameter overload above.

**Impact:** Same as BUG-B-001 — compilation failure in debug builds. Since this single-parameter overload is called internally by the two-parameter overload (when aliasing is detected), the bug would manifest even if only the two-parameter version is directly called.

**Suggested Change:**
```nim
  debug: doAssert buf.len.uint.isPowerOf2_vartime()
```

---

### [BUG] BUG-B-003: Runtime input validation replaced with `doAssert` in `computeAggRandScaledInterpoly`

**Location:** `constantine/commitments/kzg_multiproofs.nim:528-534`
**Severity:** High
**Confidence:** 0.9

**Diff Under Review:**
```diff
-  if evals.len != evalsCols.len or linearIndepRandNumbers.len < evalsCols.len:
-    return false
+  doAssert evals.len == evalsCols.len, "Internal error: evals and evalsCols must have same length"
+  doAssert linearIndepRandNumbers.len >= evalsCols.len, "Internal error: linearIndepRandNumbers must cover all evals"

   for k in 0 ..< evalsCols.len:
     let c = evalsCols[k]
-    if c < 0 or c >= NumCols:
-      return false
+    doAssert c >= 0 and c < NumCols, "Internal error: Column index out of bounds: " & $c
```

**Issue: Runtime bounds checks replaced with compile-time assertions — potential OOB memory access in release builds**

The original code had **runtime conditional checks** (`if ... return false`) that guard against:
1. Mismatched array lengths between `evals`, `evalsCols`, and `linearIndepRandNumbers`
2. Out-of-bounds column indices in `evalsCols`

These were replaced with `doAssert` statements, which:
- In **debug builds** (`-d:debug` or default): fire an assertion and crash if violated
- In **release builds** (`-d:release`): are completely stripped — no runtime check occurs

After these assertions, the code accesses `agg_cols_used[c]` and `agg_cols[c]` where `c` comes from `evalsCols[k]`. If `c >= NumCols` in a release build, this is an **out-of-bounds heap access** on `agg_cols` and `agg_cols_used`.

**Impact:** 
- **Security**: Malicious or corrupted input data could cause out-of-bounds reads/writes in release builds
- **Correctness**: The function previously returned `false` for invalid inputs; now in release builds, it proceeds with undefined behavior

The `kzg_coset_verify_batch` caller (lines 652-664) does have its own runtime validation of `evalsCols` bounds, which mitigates this in the common calling path. However, if `computeAggRandScaledInterpoly` is ever called directly or through another path without the same guards, it would be vulnerable.

**Suggested Change:** Keep the runtime `if ... return false` checks or add explicit runtime assertions:
```nim
  # Runtime validation: prevent OOB indexing of heap allocations
  if evals.len != evalsCols.len or linearIndepRandNumbers.len < evalsCols.len:
    return false  # or signal error appropriately
  for k in 0 ..< evalsCols.len:
    let c = evalsCols[k]
    if c < 0 or c >= NumCols:
      return false
```

---

### [BUG] BUG-B-004: `computeAggRandScaledInterpoly` return type changed from `bool` to `void`

**Location:** `constantine/commitments/kzg_multiproofs.nim:502-508`
**Severity:** Medium
**Confidence:** 0.9

**Diff Under Review:**
```diff
-      N: static int): bool {.meter.} =
+      N: static int) {.meter.} =
```

**Issue: Caller can no longer detect error conditions from `computeAggRandScaledInterpoly`**

The function's return type was changed from `bool` to `void` (no return type). The caller in `kzg_coset_verify_batch` was updated:

```diff
-  if not interpoly.computeAggRandScaledInterpoly(
-    evals, evalsCols, domain, linearIndepRandNumbers, N
-  ):
-    return false
+  interpoly.computeAggRandScaledInterpoly(
+    evals, evalsCols, domain, linearIndepRandNumbers, N
+  )
```

Combined with BUG-B-003, this means that in release builds, any invalid input to `computeAggRandScaledInterpoly` will result in the caller continuing with potentially corrupted data rather than returning `false`. The function's contract has fundamentally changed from "validates input and returns error" to "assumes valid input and crashes on invalid input (debug only)".

**Impact:** Error propagation is broken. The caller can no longer distinguish between success and failure, which was the previous contract.

---

### [BUG] BUG-B-005: Weakened zero-check in `checkCirculant` for r=1 edge case

**Location:** `constantine/math/matrix/toeplitz.nim:74-78`
**Severity:** Low
**Confidence:** 0.7

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

**Issue: Check at index `r+1` is skipped for r=1 edge case**

For `r = 1` (circulant length `k2 = 2`):
- **Old code:** Loop `1 .. 2` checks both `circulant[1]` and `circulant[2]`
- **New code:** Loop `1 .. 1` checks `circulant[1]`; bounds check `r + 1 < k2` → `2 < 2` → `false`, so `circulant[2]` is **NOT checked**

When `r = 1`, `makeCirculantMatrix` produces a 2-element array where both elements are either set or zeroed. Index 2 (`circulant[2]`) is out of bounds for the 2-element array, so the old code was checking out of bounds. The new code is actually **correct** here — the old code had a latent bug.

However, for `r = 2` (circulant length `k2 = 4`), both code paths check `circulant[3]` (index `r+1 = 3 < 4 = k2`), so the behavior matches.

**Impact:** No actual correctness issue. The new code is actually more correct (avoids OOB check for r=1). This is informational.

**Suggested Change:** No change needed. The new code is correct.

---

### [BUG] BUG-B-006: `Alloca` tag removed from `batchAffine` for Twisted Edwards

**Location:** `constantine/math/elliptic/ec_twistededwards_batch_ops.nim:237`
**Severity:** Informational
**Confidence:** 0.8

**Diff Under Review:**
```diff
 func batchAffine*[F](
        affs: ptr UncheckedArray[EC_TwEdw_Aff[F]],
        projs: ptr UncheckedArray[EC_TwEdw_Prj[F]],
-       N: int) {.noInline, tags:[Alloca].} =
+       N: int) {.meter.} =
```

**Issue: `Alloca` tag removed despite potential stack allocation**

The `Alloca` tag was removed (along with `noInline`) and replaced with `meter`. The function body still uses `allocStackArray(SecretBool, N)` in the original non-vartime path (line 250 → removed in vartime version, but the function may have other callers). 

For large `N` values, `allocStackArray` would overflow the stack. The removal of the `Alloca` tag suggests this was intentional to signal that the function may now use heap allocation instead of stack allocation. However, the tag removal should be verified against the actual implementation to ensure the stack usage pattern hasn't changed unexpectedly.

**Impact:** Informational. Task scheduling systems that rely on `Alloca` tags to avoid stack-heavy tasks might misclassify this function.

---

## Positive Changes

1. **`ToeplitzAccumulator` design** — Well-designed with `=copy {.error.}` preventing accidental copies, `=destroy` with nil checks for safe cleanup, and the `init` function defensively frees existing allocations before re-allocating.

2. **`bit_reversal_permutation` aliasing support** — The new aliasing detection (`dst[0].addr == src[0].addr`) with temp buffer fallback correctly handles in-place operations that the old `{.noalias.}` version could not.

3. **`recoverPolynomialCoeff` in-place IFFT** — Eliminates one heap allocation (~128KB for ext_size) by performing IFFT in-place on `extended_times_zero`, verified correct because `ifft_rn` supports in-place via internal temp buffer.

4. **Comprehensive test additions** — New tests for `batchAffine_vartime` covering all-neutral points, single-element, varied batch sizes, and Twisted Edwards curves.

5. **`checkCirculant` edge-case fix** — The bounds check `r + 1 < k2` correctly handles the case where `r = 1` (circulant length 2), where the old code would have accessed an out-of-bounds index.
