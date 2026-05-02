---
**Branch:** `master` → `peerdas-perf-fix-rebased2` (commit `74d1839c`)
**Diff file:** `.REVIEWS/RID-202605022039-peerdas-perf-fix-rebased2-74d1839c/RID-202605022039-changes_under_review.diff`
**Date:** 2026-05-02
**Reviewer:** Bug Hunter (Pass A)
**Scope:** PeerDAS performance optimization: new ToeplitzAccumulator, batchAffine_vartime, polyphase spectrum bank type change (Jacobian→affine), toeplitzMatVecMul rewrite
**Focus:** Logic errors, boundary conditions, null/undefined, race conditions, error handling
---

# Bug Hunter Review (Pass A)

## Summary

| ID | Severity | Confidence | File | Issue |
|----|----------|------------|------|-------|
| BUG-A-001 | High | 1.0 | constantine/math/polynomials/fft_common.nim:324-333 | Variable name error (`src.len` → should be `buf.len`) causes debug build compilation failure |
| BUG-A-002 | Low | 1.0 | constantine/commitments/kzg_multiproofs.nim:379 / 505-558 | Functions changed from returning error status to `void` with assertions — silent behavior change for callers |
| BUG-A-003 | Medium | 0.8 | constantine/math/matrix/toeplitz.nim:356-365 | `toOpenArray(n2)` on heap-allocated arrays relies on custom template — fragile if import order changes |

**Key takeaways:**
1. A compilation-breaking variable name bug exists in the new in-place `bit_reversal_permutation` function's debug assertion.
2. Several functions silently changed their return type semantics from error-returning to assertion-based, which is a design choice but breaks backward compatibility.
3. The `toOpenArray(n2)` pattern on `ptr UncheckedArray[T]` relies on a custom template that treats the argument as LENGTH rather than LAST INDEX — this works correctly but is fragile.

## Findings

### [BUG] BUG-A-001: Variable name error in in-place `bit_reversal_permutation` causes debug build compilation failure - constantine/math/polynomials/fft_common.nim:324-333

**Location:** `constantine/math/polynomials/fft_common.nim:324-333`
**Severity:** High
**Confidence:** 1.0

**Diff Under Review:**
```diff
+func bit_reversal_permutation*[T](buf: var openArray[T]) {.inline.} =
+  ## In-place bit reversal permutation.
+  ##
+  ## Out-of-place is at least 2x faster than in-place so dispatch to out-of-place
+  debug: doAssert src.len.uint.isPowerOf2_vartime()
+  debug: doAssert buf.len > 0
+  var tmp = allocHeapArrayAligned(T, buf.len, alignment = 64)
+  bit_reversal_permutation_noalias(tmp.toOpenArray(0, buf.len-1), buf)
+  copyMem(buf[0].addr, tmp[0].addr, buf.len * sizeof(buf[0]))
+  freeHeapAligned(tmp)
```

**Issue:** **Undeclared variable `src` in in-place `bit_reversal_permutation`**

The in-place version of `bit_reversal_permutation` (which takes a single `buf` parameter) references `src.len` on line 328, but `src` is not defined in this function's scope. The correct variable name should be `buf.len`.

The out-of-place version (two-parameter `dst, src`) correctly uses `src.len`. This bug appears to have been introduced by copying the debug assertion from the out-of-place version without updating the variable name.

**Impact:** Any debug build (`-d:CTT_DEBUG` or `-d:debug`) will fail to compile with "undeclared identifier: src". The code works correctly in release builds because the `debug:` block is compiled away, but this means:
1. Debug-mode testing of FFT operations is broken
2. The assertion that validates the buffer length is a power of 2 is never executed
3. Developers working on FFT-related features will encounter unexpected compilation failures

**Suggested Change:**
```nim
-  debug: doAssert src.len.uint.isPowerOf2_vartime()
+  debug: doAssert buf.len.uint.isPowerOf2_vartime()
```

---

### [BUG] BUG-A-002: Functions changed from returning error status to `void` with assertions — silent behavior change for callers - constantine/commitments/kzg_multiproofs.nim:379, 505-558

**Location:** `constantine/commitments/kzg_multiproofs.nim:379, 505-558`
**Severity:** Low
**Confidence:** 1.0

**Diff Under Review:**
```diff
  func kzg_coset_prove*[L, CDS: static int, Name: static Algebra](
         proofs: var array[CDS, EC_ShortW_Aff[Fp[Name], G1]],
         poly: openArray[Fr[Name]],
         fr_fft_desc: FrFFT_Descriptor[Fr[Name]],
         ec_fft_desc: ECFFT_Descriptor[EC_ShortW_Jac[Fp[Name], G1]],
-       polyphaseSpectrumBank: array[L, array[CDS, EC_ShortW_Jac[Fp[Name], G1]]]
-      ) {.tags:[Alloca, HeapAlloc, Vartime], meter.} =
+       polyphaseSpectrumBank: array[L, array[CDS, EC_ShortW_Aff[Fp[Name], G1]]]
+      ): void {.tags:[Alloca, HeapAlloc, Vartime], meter.} =

-  func computeAggRandScaledInterpoly[Name: static Algebra, L: static int](
-      ...
-      N: static int): bool {.meter.} =
+  func computeAggRandScaledInterpoly[Name: static Algebra, L: static int](
+      ...
+      N: static int) {.meter.} =
```

**Issue:** **Return type changes remove caller's ability to handle errors gracefully**

Two functions underwent a significant semantic change:

1. **`kzg_coset_prove`**: Previously implicitly returned `FFT_Status` (via `toeplitzMatVecMulPreFFT`), now explicitly returns `void`. All error paths use `doAssert` instead of returning error codes.

2. **`computeAggRandScaledInterpoly`**: Previously returned `bool` with explicit `return false` for invalid inputs, now uses `doAssert` instead:
   ```diff
-  if evals.len != evalsCols.len or linearIndepRandNumbers.len < evalsCols.len:
-    return false
+  doAssert evals.len == evalsCols.len, "Internal error: evals and evalsCols must have same length"
+  doAssert linearIndepRandNumbers.len >= evalsCols.len, "Internal error: linearIndepRandNumbers must cover all evals"

-  if c < 0 or c >= NumCols:
-    return false
+  doAssert c >= 0 and c < NumCols, "Internal error: Column index out of bounds: " & $c
   ```

**Impact:** The corresponding caller in `kzg_coset_verify_batch` changed from:
```nim
if not interpoly.computeAggRandScaledInterpoly(...):
    return false
```
to:
```nim
interpoly.computeAggRandScaledInterpoly(...)
```

This means:
- Invalid input to these functions now causes a **panic/crash** instead of a graceful error return
- External callers (e.g., in data availability sampling code) lose the ability to handle invalid inputs gracefully
- The error messages are labeled "Internal error" but some triggers (like column index out of bounds) could legitimately occur from user-provided data

**Suggested Change:** Either document that these functions are now "precondition-enforcing" (caller guarantees valid input) or add runtime validation with proper error propagation for public-facing APIs.

---

### [BUG] BUG-A-003: `toOpenArray(n2)` on heap-allocated arrays relies on custom template — fragile if import order changes - constantine/math/matrix/toeplitz.nim:356-365

**Location:** `constantine/math/matrix/toeplitz.nim:356-365`
**Severity:** Medium
**Confidence:** 0.8

**Diff Under Review:**
```diff
   block HappyPath:
-    check HappyPath, ec_fft_nn(ecFftDesc, vExt.toOpenArray(n2), vExt.toOpenArray(n2))
     ...
-    check HappyPath, acc.accumulate(circulant, vExtFftAff.toOpenArray(n2))
     ...
-    check HappyPath, acc.finish(ifftResult.toOpenArray(n2))
```

**Issue:** **`toOpenArray(n)` on `ptr UncheckedArray[T]` relies on custom template semantics**

The code uses `toOpenArray(n2)` on heap-allocated arrays (e.g., `vExt.toOpenArray(n2)` where `vExt: ptr UncheckedArray[EC]`). This works correctly **only because** the custom `toOpenArray` template in `constantine/platforms/views.nim` treats the argument as a **LENGTH**:

```nim
template toOpenArray*[T](p: ptr UncheckedArray[T], len: int): openArray[T] =
  p.toOpenArray(0, len-1)
```

However, Nim's standard library `toOpenArray` treats the single argument as a **LAST INDEX** (inclusive):
```nim
# Nim stdlib semantics: a.toOpenArray(k) → indices 0..k (k+1 elements)
```

If the import order changes and the Nim stdlib version is selected instead of the custom one, `toOpenArray(n2)` would create an openArray spanning indices 0..n2 (n2+1 elements), which would:
1. Read one element past the end of the allocated buffer (heap read overflow)
2. Cause size mismatch errors in `accumulate` and `finish` (they check `circulant.len != n`)
3. Cause FFT failure (n2+1 is not a power of 2)

The same pattern appears in `kzg_multiproofs.nim`:
```nim
makeCirculantMatrix(circulant.toOpenArray(CDS), poly, offset, L)  # line 433
accum.accumulate(circulant.toOpenArray(CDS), ...)                  # line 438
accum.finish(u.toOpenArray(CDS))                                    # line 447
ec_fft_desc.ec_fft_nn(u.toOpenArray(CDS), u.toOpenArray(CDS))      # line 455
```

**Impact:** Currently works correctly due to the custom template being imported. However:
- Any code that imports these modules without importing `views.nim` could get the wrong `toOpenArray`
- Future refactoring that changes import order could silently introduce heap overflows
- The convention is non-obvious and could confuse future developers

**Suggested Change:** Use the explicit `toOpenArray(0, n-1)` form consistently to avoid ambiguity:
```nim
- vExt.toOpenArray(n2)
+ vExt.toOpenArray(0, n2-1)
```
Or rename the custom template to avoid confusion (e.g., `toOpenArrayLen`).

---

## Positive Changes

1. **`batchAffine_vartime` properly handles all edge cases**: The new variable-time batch affine conversion correctly handles neutral/infinity points at any position in the batch, all-neutral batches, and single-element batches. The lazy reduction chain is correctly maintained through the product chain, and the final elements are properly reduced.

2. **`ToeplitzAccumulator` has proper resource management**: The `=destroy` proc correctly handles partial allocation failures — if `init` fails after allocating some buffers, the destructor safely frees only the non-nil pointers. The defensive re-initialization in `init` (freeing existing buffers before allocating new ones) prevents leaks on double-init.

3. **In-place FFT alias detection is correct**: The new `bit_reversal_permutation` function with aliasing detection correctly identifies when `dst` and `src` are the same buffer and uses a temporary buffer approach. This is properly used by the in-place `ec_fft_nn` and `ec_ifft_nn` paths.

4. **`checkCirculant` is now bounds-safe for r=1**: The old loop `for i in 1 .. r+1` could have checked beyond valid bounds for small r values. The new code explicitly checks `if r+1 < k2` before accessing index `r+1`, making it safe for all valid r values.

5. **Polyphase spectrum bank now stored in affine form**: Reduces memory footprint from ~200 KB to ~130 KB (8192 points × 48 bytes Jacobian → 32 bytes affine) and enables more efficient batch operations during trusted setup initialization.

6. **All `batchAffine` functions now have N≤0 early return**: Protects against degenerate calls that could cause division-by-zero or invalid memory access in the batch inversion algorithm.
