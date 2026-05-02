---
**Branch:** `master` → `peerdas-perf-fix-rebased2` (commit `81784ecd`)
**Diff file:** `.REVIEWS/RID-202605022113-peerdas-perf-fix-rebased2-81784ecd/RID-202605022113-changes_under_review.diff`
**Date:** 2026-05-02
**Reviewer:** Bug Hunter (Pass B)
**Scope:** PeerDAS FK20 multiproof performance fix — ToeplitzAccumulator redesign, batchAffine_vartime, polyphase spectrum affine storage, in-place FFT support
**Focus:** Runtime failures, unexpected inputs, state machine edge cases, error handling changes
---

# Bug Hunter Review (Pass B)

## Summary

| ID | Severity | Confidence | File | Issue |
|----|----------|------------|------|-------|
| BUG-B-001 | Medium | 0.8 | kzg_multiproofs.nim:502-580 | `computeAggRandScaledInterpoly` changed from `bool` to `void` with `doAssert`; caller error handling eliminated |
| BUG-B-002 | Low | 0.9 | toeplitz.nim:26-30, 51-53, 109-113 | Documentation of zero-padded circulant range inconsistent: `1..r+1` vs `1..r` + bounds check |
| BUG-B-003 | Low | 0.7 | kzg_multiproofs.nim:372-459 | `kzg_coset_prove` return type changed to `void` — callers cannot detect internal failures |
| BUG-B-004 | Informational | 1.0 | ec_shortweierstrass_batch_ops.nim:1052-1211 | `batchAffine_vartime` uses `affs[i].y` for zero-tracking flags — potential confusion with output data |

**Key takeaways:**
1. The shift from return-value-based error handling to `doAssert` in `computeAggRandScaledInterpoly` removes a graceful error path for validation failures, though upstream validation in `kzg_coset_verify_batch` covers most cases.
2. The ToeplitzAccumulator state machine (init → accumulate×L → finish) is well-designed with proper offset tracking and size validation.
3. The in-place FFT + aliasing detection in `bit_reversal_permutation` is correctly implemented and safe.
4. Documentation inconsistencies in circulant zero-padding ranges could confuse future maintainers.

## Findings

### [BUG] BUG-B-001: `computeAggRandScaledInterpoly` return type changed from `bool` to `void` — callers lose error detection capability

**Location:** `constantine/commitments/kzg_multiproofs.nim:502-580`

**Severity:** Medium
**Confidence:** 0.8

**Diff Under Review:**
```diff
 func computeAggRandScaledInterpoly[Name: static Algebra, L: static int](
        interpoly: var PolynomialCoef[L, Fr[Name]],
        evals: openArray[array[L, Fr[Name]]],
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
-  if c < 0 or c >= NumCols:
-    return false
+  doAssert c >= 0 and c < NumCols, "Internal error: Column index out of bounds: " & $c
 ...
-  return true
```

**Issue:** **Error handling contract change — callers can no longer detect validation failures**

The function was changed from returning `bool` (with `return false` for invalid inputs) to returning `void` with `doAssert` for all validation. The only caller is `kzg_coset_verify_batch`, which had:

```nim
if not interpoly.computeAggRandScaledInterpoly(...):
    return false
```

Now it's:

```nim
interpoly.computeAggRandScaledInterpoly(...)
```

**Impact analysis:** `kzg_coset_verify_batch` (which still returns `bool`) has its own input validation at lines 652-664 that checks:
- `evals.len != proofs.len`
- `evalsCols.len != proofs.len`
- Column index bounds `c < 0 or c >= numCols`

This means the `doAssert evals.len == evalsCols.len` is redundant (both equal `proofs.len`), and the column bounds check is also redundant (already checked at line 663).

However, if `kzg_coset_verify_batch` is called with `proofs.len == 0`, the for-loop validation at lines 660-664 doesn't execute, and neither does the inner loop in `computeAggRandScaledInterpoly`. So the empty-input case is safe.

**Edge case concern:** If someone calls `computeAggRandScaledInterpoly` directly (not through `kzg_coset_verify_batch`) with mismatched input sizes, the program will now crash with an assertion failure instead of returning `false`. This is a behavioral API change that could affect callers outside this file.

**Suggested Change:** Either (a) keep `bool` return type for public API compatibility, or (b) document the behavioral change and ensure all callers are aware of the `doAssert` semantics.

---

### [BUG] BUG-B-002: Documentation of zero-padded circulant range is inconsistent across the file

**Location:** `constantine/math/matrix/toeplitz.nim:26-30, 51-53, 109-113`

**Severity:** Low
**Confidence:** 0.9

**Diff Under Review:**
```diff
-#   c[1..r+1] = 0
+#   c[1..r+1] = 0
 ...
-  ## - circulant[1..r+1] are all zero (r+1 zeros)
+  ## - circulant[1..r] are all zero
+  ## - circulant[r+1] is zero when r+1 < 2*r (bounds-checked for r >= 2)
 ...
-  ##   output[1..r+1] = 0 (zero padding, r+1 zeros)
+  ##   output[1..r]   = 0 (zero padding)
+  ##   output[r+1]    = 0 (from zero-init)
```

**Issue:** **File header comment still says `c[1..r+1] = 0` but implementation uses `1..r` + separate bounds check**

The file-level comment at lines 28-30 still says `c[1..r+1] = 0`, but the actual implementation (and the updated function documentation) uses `1..r` plus a bounds-checked check for index `r+1`. This inconsistency could confuse maintainers reading the file header.

Specifically for `r = 1` (circulant length = 2):
- Old behavior: Loop `1 .. 2` would access index 2, which is out of bounds (length-1 = 1). This was a latent bug.
- New behavior: Loop `1 .. 1` checks index 1, then `r+1 < k2` (2 < 2 = false) skips index 2. This is safe.

**Impact:** For `r = 1`, the old code had an out-of-bounds access in `checkCirculant`. The new code fixes this. However, `r = 1` implies a circulant of length 2, which is not used in production (CDS=128, r=64). The documentation inconsistency itself is harmless but could lead to bugs if someone copies the header comment structure.

**Suggested Change:** Update the file header comment at line 29 to match the implementation:

```nim
#   c[1..r] = 0
#   c[r+1] = 0 (from initialization, bounds-checked for r >= 2)
#   c[r+2..2r-1] = poly[1..r-2]
```

---

### [BUG] BUG-B-003: `kzg_coset_prove` return type changed from `FFT_Status` to `void` — no error signaling to callers

**Location:** `constantine/commitments/kzg_multiproofs.nim:372-459`

**Severity:** Low
**Confidence:** 0.7

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
```

**Issue:** **Return type changed from `FFT_Status` to `void`, all internal checks use `doAssert`**

The function no longer returns a status code. All internal errors are handled via `doAssert`:

```nim
doAssert status == Toeplitz_Success, "Internal error: Toeplitz accumulator init failed: " & $status
doAssert status == Toeplitz_Success, "Internal error: Toeplitz accumulator failed at offset " & $offset & ": " & $status
doAssert status2 == Toeplitz_Success, "Internal error: Toeplitz accumulator finish failed: " & $status2
doAssert status3 == FFT_Success, "Internal error: EC FFT failed: " & $status3
```

**Impact:** Callers of `kzg_coset_prove` can no longer detect or handle internal computation failures. If the Toeplitz accumulator init fails (e.g., due to memory allocation failure or descriptor order mismatch), the program will crash with an assertion failure rather than gracefully handling the error.

This is likely intentional for production use (the function is used in trusted contexts where inputs are validated), but it changes the API contract.

**Suggested Change:** Add a note in the function documentation that this function does not return errors — all failures are fatal assertions. Alternatively, consider adding a `check` mode where errors are returned instead of asserted.

---

### [BUG] BUG-B-004: `batchAffine_vartime` uses output buffer's y-coordinate field for zero-tracking flags

**Location:** `constantine/math/elliptic/ec_shortweierstrass_batch_ops.nim:1052-1211`

**Severity:** Informational
**Confidence:** 1.0

**Diff Under Review:**
```diff
+  # To avoid temporaries, we store partial accumulations
+  # in affs[i].x and whether z == 0 in affs[i].y
+  template zero(i: int): SecretWord =
+    when F is Fp:
+      affs[i].y.mres.limbs[0]
+    else:
+      affs[i].y.coords[0].mres.limbs[0]
```

**Issue:** **Output buffer fields used as temporary storage during batch conversion**

The `batchAffine_vartime` function uses `affs[i].y.mres.limbs[0]` (the first limb of the y-coordinate) to store whether the i-th input point has z=0 (i.e., is the point at infinity). This means during the intermediate computation:

1. `affs[i].x` stores the partial product chain
2. `affs[i].y.mres.limbs[0]` stores the zero flag

These are overwritten with actual affine coordinates only at the end of the backward pass. If an assertion failure or exception occurs during the computation, the `affs` output buffer will contain garbage data (partial products mixed with zero flags), not valid affine coordinates.

**Impact:** In practice, Nim's `{.push raises: [].}` pragma prevents exceptions from being raised in this file, and `doAssert` in production builds is typically compiled out (or crashes before returning partial data). This is a minor robustness concern — the output buffer should not be trusted if the function doesn't complete normally.

**Positive note:** This is the same optimization pattern used in the constant-time `batchAffine` version, so it's a well-established technique. The zero-tracking via `SecretWord` in the CT version provides both correctness and side-channel resistance.

## Positive Changes

1. **In-place FFT with aliasing detection:** The `bit_reversal_permutation` function now properly handles the case where `dst` and `src` are the same array, allocating a temporary buffer and copying back. This enables correct in-place FFT calls like `ec_fft_nn(desc, u, u)` without corrupting data.

2. **`ToeplitzAccumulator` state machine:** The new accumulator has clean state tracking with `offset` field, ensuring exactly L accumulate calls before finish. The `finish` method validates `ctx.offset == ctx.L`, preventing premature completion.

3. **Memory efficiency:** The `ToeplitzAccumulator` pre-allocates `scratchScalars` as a union buffer, avoiding per-accumulate heap allocations. The `init` method defensively frees existing allocations, handling accidental double-init.

4. **N=0 guard in all batchAffine variants:** All `batchAffine` and `batchAffine_vartime` variants now check `if N <= 0: return` at the start, preventing crashes on empty batches.

5. **All points at infinity handled correctly:** The `batchAffine_vartime` functions properly handle the edge case where all input points are the point at infinity (z=0), producing all-neutral outputs without division by zero.

6. **Polyphase spectrum bank in affine form:** Changing from Jacobian to affine storage for the polyphase spectrum bank saves affine conversion overhead in `kzg_coset_prove` (the accumulator works with affine points directly), at the cost of one-time Jacobian→affine conversion during setup.
