---
**Branch:** `master` → `peerdas-perf-fix-rebased2` (commit `81784ecd`)
**Diff file:** `.REVIEWS/RID-202605022113-peerdas-perf-fix-rebased2-81784ecd/RID-202605022113-changes_under_review.diff`
**Date:** 2026-05-02
**Reviewer:** Bug Hunter (Pass A)
**Scope:** PeerDAS performance fixes: Toeplitz accumulator with MSM, batchAffine_vartime, polyphase spectrum bank in affine form, FK20 algorithm restructuring
**Focus:** Logic errors, boundary conditions, null/undefined, race conditions, error handling
---

# Bug Hunter Review (Pass A)

## Summary

| ID | Severity | Confidence | File | Issue |
|----|----------|------------|------|-------|
| BUG-A-001 | Medium | 0.9 | `constantine/commitments/kzg_multiproofs.nim:502-534` | `computeAggRandScaledInterpoly` changed from `bool` return to `void` with `doAssert`, crashing on invalid input instead of returning `false` |
| BUG-A-002 | Low | 1.0 | `constantine/math/matrix/toeplitz.nim:142` | `debug: doAssert checkCirculant(...)` fires for `stride=1` circulants (benchmark/test use case) |
| BUG-A-003 | Informational | 0.8 | `constantine/math/matrix/toeplitz.nim:213-219` | `ToeplitzAccumulator.init` allocates heap but missing `HeapAlloc` in `.tags` |
| BUG-A-004 | Informational | 0.7 | `benchmarks/bench_matrix_toeplitz.nim:238` | Benchmark manually resets private `acc.offset = 0` — fragile and bypasses public API |

**Key takeaways:**
1. The most significant correctness concern is the error-handling regression in `computeAggRandScaledInterpoly`: callers that previously handled `false` returns now face crashes on invalid inputs.
2. The `checkCirculant` debug assertion is incompatible with general (non-FK20) circulant matrices, causing debug build failures in benchmarks.
3. The `ToeplitzAccumulator` implementation is structurally sound — init/accumulate/finish flow, resource management, and the `check`/`checkReturn` templates are correct.
4. The `batchAffine_vartime` infinity-point handling via variable-time zero-checks is correct.

## Findings

### [BUG] BUG-A-001: `computeAggRandScaledInterpoly` error handling regression — crashes on invalid input instead of returning `false`
- constantine/commitments/kzg_multiproofs.nim:502-534

**Location:** `constantine/commitments/kzg_multiproofs.nim:502-534`
**Severity:** Medium
**Confidence:** 0.9

**Diff Under Review:**
```diff
- func computeAggRandScaledInterpoly[Name: static Algebra, L: static int](
-        ...
-        N: static int): bool {.meter.} =
+ func computeAggRandScaledInterpoly[Name: static Algebra, L: static int](
+        ...
+        N: static int) {.meter.} =
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
...
-  return true
```

And in the caller `kzg_coset_verify_batch`:
```diff
-  if not interpoly.computeAggRandScaledInterpoly(
+  interpoly.computeAggRandScaledInterpoly(
     evals,
     evalsCols,
     domain,
     linearIndepRandNumbers,
     N
-  ):
-    return false
+  )
```

**Issue:** The function `computeAggRandScaledInterpoly` was changed from returning `bool` to returning `void`, and all parameter validation was switched from `return false` to `doAssert`. The caller `kzg_coset_verify_batch` (an **exported** function) no longer checks the return value and instead proceeds unconditionally.

If any parameter validation fails (e.g., `evals.len != evalsCols.len`, `c < 0`, `c >= NumCols`), the program now **crashes** (via `doAssert`) instead of gracefully returning `false`. This is a behavioral regression for the public API `kzg_coset_verify_batch*`, which previously could indicate verification failure on malformed inputs.

**Root Cause Analysis:** The diff moves validation from `debug:` blocks (lines 523-525) into unconditional `doAssert` calls (lines 528-534). This means even in release builds, invalid parameters cause crashes instead of `false` returns.

**Suggested Change:** If the intent is to treat these as internal errors (not user errors), document this clearly. Otherwise, either restore the `bool` return type or add explicit runtime checks before the `doAssert` in the caller.

---

### [BUG] BUG-A-002: `checkCirculant` debug assertion fires for non-FK20 circulants (`stride=1`)
- constantine/math/matrix/toeplitz.nim:142

**Location:** `constantine/math/matrix/toeplitz.nim:142`
**Severity:** Low
**Confidence:** 1.0

**Diff Under Review:**
```diff
   debug: doAssert checkCirculant(output, poly, offset, stride)
```

In the benchmark (`benchmarks/bench_matrix_toeplitz.nim:275`):
```diff
   makeCirculantMatrix(circulant128.toOpenArray(0, 2*CDS-1), polyFull.toOpenArray(0, N-1), 0, 1)
```

**Issue:** The `checkCirculant` function validates that a circulant has the FK20-specific sparse structure: `output[1..r]` must be all zeros, and `output[r+2..2r-1]` must match poly values at stride intervals. However, `toeplitzMatVecMul` (and its benchmark) uses `stride=1`, which produces a **dense** circulant where `output[1] = poly[n-2]` (non-zero for any non-trivial polynomial).

With `stride=1`, `checkCirculant` checks `output[1]` is zero (since `1..r` includes `1` when `r >= 1`), but `makeCirculantMatrix` sets `output[1] = poly[n-2]`. This causes the `debug: doAssert` at line 142 to fail in debug builds.

This only affects debug-mode builds. The production code path is unaffected since the assertion is guarded by `debug:`.

**Reproduction Steps:** Run the benchmark in debug mode:
```bash
nim c -d:debug benchmarks/bench_matrix_toeplitz.nim
```

**Suggested Change:** Make `checkCirculant` stride-aware, or remove the `checkCirculant` call from `makeCirculantMatrix` and instead add stride-specific validation. For example:
```nim
debug:
  when stride > 1:
    doAssert checkCirculant(output, poly, offset, stride)
  else:
    # stride=1 is the general Toeplitz case; different validation
    doAssert output[0] == poly[d - offset]
```

---

### [BUG] BUG-A-003: `ToeplitzAccumulator.init` and `accumulate` missing `HeapAlloc` in `.tags`
- constantine/math/matrix/toeplitz.nim:213-219

**Location:** `constantine/math/matrix/toeplitz.nim:213-219`
**Severity:** Informational
**Confidence:** 0.8

**Diff Under Review:**
```diff
 proc init*[EC, ECaff, F](
   ctx: var ToeplitzAccumulator[EC, ECaff, F],
   frFftDesc: FrFFT_Descriptor[F],
   ecFftDesc: ECFFT_Descriptor[EC],
   size: int,
   L: int
- ): FFTStatus {.tags:[Alloca, HeapAlloc, Vartime], meter.} =
+ ): ToeplitzStatus {.raises: [], meter.} =
```

**Issue:** `ToeplitzAccumulator.init` calls `allocHeapArrayAligned` three times (for `coeffs`, `points`, and `scratchScalars`), but the function signature only has `{.raises: [], meter.}` — no `{.tags: [HeapAlloc]}`. While Nim's flow analysis typically infers `HeapAlloc` from the implementation, the absence of explicit tags means:

1. Functions that use static tag analysis (without tracing implementations) may incorrectly believe no heap allocation occurs.
2. The `raises: []` claim is technically misleading — `allocHeapArrayAligned` can raise `OutOfMemoryError` unless the allocator is configured to never raise.

The same applies to `accumulate` (uses `allocHeapArrayAligned` internally via `fft_nn` → `bit_reversal_permutation`).

**Suggested Change:** Add `{.tags: [HeapAlloc]}` to the `init` proc signature. Consider whether `raises: []` is accurate given potential OOM from heap allocation.

---

### [BUG] BUG-A-004: Benchmark manually resets private `acc.offset = 0` field
- benchmarks/bench_matrix_toeplitz.nim:238

**Location:** `benchmarks/bench_matrix_toeplitz.nim:227-238`
**Severity:** Informational
**Confidence:** 0.7

**Diff Under Review:**
```diff
+  # Allow direct access to private 'offset' field for benchmark reuse
+  privateAccess(toeplitz.ToeplitzAccumulator)
...
+  bench("ToeplitzAccumulator_64accumulates", size, iters):
+    # Reset accumulator state for this iteration (avoids free+alloc)
+    acc.offset = 0
```

**Issue:** The benchmark uses `privateAccess` to mutate a private field of `ToeplitzAccumulator` directly. This is fragile: if the accumulator adds more internal state to track (e.g., a separate `valid` flag, accumulated data pointers), the reset would be incomplete and cause data corruption in subsequent iterations.

**Suggested Change:** Add a public `reset` method to `ToeplitzAccumulator` that properly resets all internal state.

---

## Positive Changes

1. **`computePolyphaseDecompositionFourier` eliminates redundant heap allocation.** The new version computes polyphase spectra directly into the output buffer (Jacobian form) instead of allocating a temporary `polyphaseComponent` buffer per offset. Then a single batch inversion converts all `L×CDS` points to affine form. This saves `L` heap allocations + frees, and the batch inversion with vartime mode efficiently skips `CDSdiv2` points-at-infinity per phase.

2. **`kzg_coset_prove` reuses the `u` buffer for the final FFT.** Instead of allocating a separate `proofsJac` buffer (`ec_fft_nn(proofsJac, u)`), it now does in-place FFT (`ec_fft_nn(u, u)`), saving one heap allocation per proof.

3. **`eth_peerdas.nim` reuses `extended_times_zero` buffer for in-place IFFT.** The `ifft_rn` result no longer needs a separate `ext_times_zero_coeffs` buffer, saving one allocation + free.

4. **Comprehensive `batchAffine_vartime` implementation** with correct handling of points at infinity (z=0) via variable-time zero detection. The product chain correctly skips zero z-coordinates, and the backward pass properly reconstructs `1/z_i` for finite points while neutralizing infinity points.

5. **`checkCirculant` zero-padding range is more precise.** The change from `1..r+1` to `1..r` plus a separate bounds-checked `r+1` check is actually more correct than the old unconditionally-accessing `circulant[r+1]` (which could be out of bounds for small `r`). The bounds check `if r + 1 < k2` is a genuine improvement.
