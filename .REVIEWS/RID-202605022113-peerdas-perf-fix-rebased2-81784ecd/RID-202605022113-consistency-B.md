---
**Branch:** `master` → `peerdas-perf-fix-rebased2` (commit `81784ecd`)
**Diff file:** `.REVIEWS/RID-202605022113-peerdas-perf-fix-rebased2-81784ecd/RID-202605022113-changes_under_review.diff`
**Date:** 2026-05-02
**Reviewer:** Consistency Analyst (Pass B)
**Scope:** PeerDAS performance optimizations — ToeplitzAccumulator, batchAffine_vartime, FFT tag cleanup, matrix transpose module
**Focus:** Convention drift, duplication, missing reuse, API blast-radius (alternative angle)
---

# Consistency Review (Pass B)

## Summary

| ID | Severity | Confidence | File | Issue |
|----|----------|------------|------|-------|
| CONS-B-001 | High | 1.0 | benchmarks/bench_kzg_multiproofs.nim:104-108 | `ToeplitzAccumulator.init` allocated inside benchmark loop — contradicts bench_matrix_toeplitz.nim pattern |
| CONS-B-002 | Medium | 0.7 | constantine/math/matrix/toeplitz.nim:155-156 | Exported `checkReturn` template may collide with `ethereum_verkle_ipa.nim:90` if both imported |
| CONS-B-003 | Medium | 0.8 | constantine/commitments/kzg_multiproofs.nim:433-455 | `toOpenArray(CDS)` single-arg style diverges from project convention `toOpenArray(0, N-1)` |
| CONS-B-004 | Low | 0.9 | benchmarks/bench_matrix_toeplitz.nim:171 | `privateAccess(toeplitz.ToeplitzAccumulator)` to mutate private `offset` field for benchmark reset |
| CONS-B-005 | Low | 0.8 | constantine/math/matrix/toeplitz.nim:286-287 | `scratchScalars` type punning via `cast` between `F` and `F.getBigInt()` — fragile despite static assert |
| CONS-B-006 | Low | 0.8 | constantine/math/elliptic/ec_twistededwards_batch_ops.nim:25 | `batchAffine` loses `noInline` pragma after stack allocation removal — may affect compile-time |
| CONS-B-007 | Low | 0.9 | benchmarks/bench_kzg_multiproofs.nim:111-113 vs kzg_multiproofs.nim:433 | `toOpenArray(0, CDS-1)` vs `toOpenArray(CDS)` — benchmark vs production inconsistency |
| CONS-B-008 | Informational | 1.0 | constantine/math/polynomials/fft_common.nim:290 | `bit_reversal_permutation` → `bit_reversal_permutation_noalias` + aliasing wrapper — positive change |
| CONS-B-009 | Informational | 1.0 | constantine/math/elliptic/ec_shortweierstrass_batch_ops.nim:30-32, 98-100, 185-187, 262-264 | `N <= 0` guard added consistently to all `batchAffine`/`batchAffine_vartime` entry points |

**Key takeaways:**
1. **Critical benchmark methodology inconsistency:** `bench_kzg_multiproofs.nim` initializes `ToeplitzAccumulator` inside the timed loop (allocating ~772KB per iteration), while `bench_matrix_toeplitz.nim` correctly initializes outside. This skews Phase 1 benchmark results.
2. **Exported `checkReturn` template naming:** `toeplitz.nim` exports a generic `checkReturn` template that could collide with the existing one in `ethereum_verkle_ipa.nim` if a file imports both modules.
3. **`toOpenArray` style drift:** New code in `kzg_multiproofs.nim` uses single-arg `toOpenArray(N)` while the project predominantly uses `toOpenArray(0, N-1)`.

## Findings

### [CONSISTENCY] CONS-B-001: ToeplitzAccumulator.init allocated inside benchmark timed loop - benchmarks/bench_kzg_multiproofs.nim:104-108

**Location:** benchmarks/bench_kzg_multiproofs.nim:104-108
**Severity:** High
**Confidence:** 1.0

**Diff Under Review:**
```diff
   bench("fk20_phase1_accumulation_loop", CDS, iters):
+    type BLS12_381_G1_aff = EC_ShortW_Aff[Fp[BLS12_381], G1]
+    type BLS12_381_G1_jac = EC_ShortW_Jac[Fp[BLS12_381], G1]
+    var accum: ToeplitzAccumulator[BLS12_381_G1_jac, BLS12_381_G1_aff, Fr[BLS12_381]]
+    doAssert accum.init(ctx.fft_desc_ext, ctx.ecfft_desc_ext, CDS, L) == Toeplitz_Success
+    var circulant: array[CDS, Fr[BLS12_381]]
     for offset in 0 ..< L:
```

**Issue:** **Benchmark allocates ~772KB per iteration**

The `benchFK20_Phase1_Full` benchmark initializes a `ToeplitzAccumulator` inside the `bench()` call body. The `init` method allocates three `allocHeapAligned` buffers (`coeffs`, `points`, `scratchScalars`) totaling approximately 772 KB. This allocation cost is measured as part of every benchmark iteration, inflating the reported timing.

The companion benchmark file `benchmarks/bench_matrix_toeplitz.nim:171-194` explicitly avoids this anti-pattern with a comment:
```nim
# Initialize accumulator once outside the benchmark loop to avoid
# allocation overhead (3 x allocHeapAligned, ~772 KB total) in timing.
```
and resets `acc.offset = 0` inside the loop instead (via `privateAccess`).

**Issue Type:** inconsistent-pattern

**Scope:** 
- benchmarks/bench_kzg_multiproofs.nim:104-108 (affected)
- benchmarks/bench_matrix_toeplitz.nim:171-194 (correct pattern)

**Existing Pattern:** benchmarks/bench_matrix_toeplitz.nim:171-194

**Suggested Change:** Move `accum.init` outside the `bench()` call and reset `acc.offset = 0` inside the loop body. Follow the pattern established in `bench_matrix_toeplitz.nim:171-194`:
```nim
  var accum: ToeplitzAccumulator[BLS12_381_G1_jac, BLS12_381_G1_aff, Fr[BLS12_381]]
  doAssert accum.init(ctx.fft_desc_ext, ctx.ecfft_desc_ext, CDS, L) == Toeplitz_Success
  privateAccess(toeplitz.ToeplitzAccumulator)

  bench("fk20_phase1_accumulation_loop", CDS, iters):
    accum.offset = 0
    var circulant: array[CDS, Fr[BLS12_381]]
    for offset in 0 ..< L:
      ...
```

---

### [CONSISTENCY] CONS-B-002: Exported checkReturn template may collide with ethereum_verkle_ipa.nim — potential API blast radius - constantine/math/matrix/toeplitz.nim:155-180

**Location:** constantine/math/matrix/toeplitz.nim:155-180
**Severity:** Medium
**Confidence:** 0.7

**Diff Under Review:**
```diff
+template checkReturn*(evalExpr: untyped): untyped {.dirty.} =
+  ## Check ToeplitzStatus or FFTStatus and return early on failure
+  ## Use in functions that return ToeplitzStatus directly
+  block:
+    let status = evalExpr
+    when status is ToeplitzStatus:
+      if status != Toeplitz_Success:
+        return status
+    elif status is FFTStatus:
+      if status != FFT_Success:
+        return case status
+          of FFT_SizeNotPowerOfTwo: Toeplitz_SizeNotPowerOfTwo
+          of FFT_TooManyValues: Toeplitz_TooManyValues
+          else: Toeplitz_MismatchedSizes
```

**Issue:** **Exported generic `checkReturn` template with `*` export may collide**

The new `checkReturn*` template is exported from `toeplitz.nim`. An existing `checkReturn` template with a different signature already exists in `ethereum_verkle_ipa.nim:90`:
```nim
template checkReturn(evalExpr: CttCodecScalarStatus): untyped {.dirty.} =
template checkReturn(evalExpr: CttCodecEccStatus): untyped {.dirty.} =
```

If any file imports both `toeplitz` and `ethereum_verkle_ipa.nim` (directly or transitively), the two `checkReturn` templates would conflict. While `kzg_multiproofs.nim` currently imports `toeplitz` without issue (it doesn't use `checkReturn`), this creates a latent collision risk.

**Issue Type:** api-blast-radius

**Scope:**
- constantine/math/matrix/toeplitz.nim:155 (new exported template)
- constantine/ethereum_verkle_ipa.nim:90, 100 (existing templates)
- constantine/commitments/kzg_multiproofs.nim:18 (imports `toeplitz`)

**Existing Pattern:** The project avoids exporting generic error-checking templates. `checkReturn` in `ethereum_verkle_ipa.nim` is NOT exported (no `*`).

**Suggested Change:** Either (a) remove the `*` export from `toeplitz.nim`'s `checkReturn` template, or (b) rename it to something more specific like `checkReturnToeplitz` to avoid future collisions.

---

### [CONSISTENCY] CONS-B-003: toOpenArray single-arg style diverges from project convention - constantine/commitments/kzg_multiproofs.nim:433-455

**Location:** constantine/commitments/kzg_multiproofs.nim:433-455
**Severity:** Medium
**Confidence:** 0.8

**Diff Under Review:**
```diff
   for offset in 0 ..< L:
-    makeCirculantMatrix(circulant.toOpenArray(CDS), poly, offset, L)
+    makeCirculantMatrix(circulant.toOpenArray(CDS), poly, offset, L)
     ...
     let status = accum.accumulate(
-      circulant.toOpenArray(CDS),
+      circulant.toOpenArray(CDS),
       polyphaseSpectrumBank[offset]
     )
   ...
-  let status2 = accum.finish(u.toOpenArray(CDS))
+  let status2 = accum.finish(u.toOpenArray(CDS))
-  let status3 = ec_fft_desc.ec_fft_nn(u.toOpenArray(CDS), u.toOpenArray(CDS))
+  let status3 = ec_fft_desc.ec_fft_nn(u.toOpenArray(CDS), u.toOpenArray(CDS))
```

**Issue:** **`toOpenArray(N)` single-arg form used where project convention is `toOpenArray(0, N-1)`**

The new `kzg_coset_prove` implementation uses `toOpenArray(CDS)` (single-arg form) consistently throughout. However, the project's predominant convention (found in 30+ locations across `hashes/`, `serialization/`, `math/pairings/`, `math_arbitrary_precision/`, etc.) is the explicit two-arg form `toOpenArray(0, N-1)`.

The benchmark file `benchmarks/bench_kzg_multiproofs.nim:111-113` correctly uses `toOpenArray(0, CDS-1)`, creating inconsistency between production code and its benchmark.

**Issue Type:** convention-drift

**Scope:**
- constantine/commitments/kzg_multiproofs.nim:433, 438, 447, 455 (uses single-arg form)
- benchmarks/bench_kzg_multiproofs.nim:111-113 (uses two-arg form)

**Existing Pattern:** constantine/eth_eip7594_peerdas.nim:300 (`poly_monomial[].coefs.toOpenArray(0, N-1)`), constantine/math/pairings/gt_multiexp.nim:215-216

**Suggested Change:** Change `toOpenArray(CDS)` to `toOpenArray(0, CDS-1)` for consistency with project-wide convention. Or document the single-arg form as acceptable.

---

### [CONSISTENCY] CONS-B-004: privateAccess used to mutate private ToeplitzAccumulator.offset field - benchmarks/bench_matrix_toeplitz.nim:171

**Location:** benchmarks/bench_matrix_toeplitz.nim:171
**Severity:** Low
**Confidence:** 0.9

**Diff Under Review:**
```diff
+  # Allow direct access to private 'offset' field for benchmark reuse
+  privateAccess(toeplitz.ToeplitzAccumulator)
+
+  # Initialize accumulator once outside the benchmark loop to avoid
+  # allocation overhead (3 x allocHeapAligned, ~772 KB total) in timing.
+  var acc: ToeplitzAccumulator[BLS12_381_G1_jac, BLS12_381_G1_aff, F]
+  let statusInit = acc.init(descs.frDesc, descs.ecDesc, size, L)
+  doAssert statusInit == Toeplitz_Success
+
+  bench("ToeplitzAccumulator_64accumulates", size, iters):
+    # Reset accumulator state for this iteration (avoids free+alloc)
+    acc.offset = 0
```

**Issue:** **Benchmark resets internal state via `privateAccess` to avoid reallocation**

The benchmark uses `privateAccess` to directly set `acc.offset = 0` inside the timed loop, avoiding the cost of `init` + `=destroy` per iteration. This is a valid benchmark optimization but creates a tight coupling between the benchmark and the internal structure of `ToeplitzAccumulator`.

**Issue Type:** inconsistent-pattern

**Scope:** benchmarks/bench_matrix_toeplitz.nim:171

**Existing Pattern:** Other benchmarks (e.g., `bench_elliptic_template.nim`) create fresh state inside the benchmark loop without `privateAccess`.

**Suggested Change:** Consider adding a `reset()` method to `ToeplitzAccumulator` that sets `offset = 0` without freeing buffers. This would eliminate the need for `privateAccess` in benchmarks.

---

### [CONSISTENCY] CONS-B-005: scratchScalars type punning via cast between F and F.getBigInt() - constantine/math/matrix/toeplitz.nim:286-287

**Location:** constantine/math/matrix/toeplitz.nim:286-287
**Severity:** Low
**Confidence:** 0.8

**Diff Under Review:**
```diff
+  # Invariant: scratchScalars is typed as F but re-interpreted as F.getBigInt() below.
+  # This requires sizeof(F) == sizeof(F.getBigInt()), which holds for all production
+  # field types (e.g. Fr[BLS12_381] is 32 bytes in both representations).
+  static: doAssert sizeof(F) == sizeof(F.getBigInt()), "scratchScalars cast requires sizeof(F) == sizeof(F.getBigInt())"
+
+  let scalars = cast[ptr UncheckedArray[F.getBigInt()]](ctx.scratchScalars)
```

**Issue:** **Type punning via raw pointer cast — protected by static assert but still fragile**

The `scratchScalars` buffer is typed as `F` (field elements) but reinterpreted as `F.getBigInt()` (big integers) via `cast`. While the `static: doAssert` catches mismatches at compile time, this pattern is fragile if new field types with different sizeof ratios are added.

**Issue Type:** convention-drift

**Scope:** constantine/math/matrix/toeplitz.nim:286-287

**Suggested Change:** Consider adding a comment linking to similar patterns in the codebase (e.g., `batchFromField` in FFT modules) to show this is an established optimization technique, not a one-off hack.

---

### [CONSISTENCY] CONS-B-006: batchAffine loses noInline pragma after stack allocation removal - constantine/math/elliptic/ec_twistededwards_batch_ops.nim:25

**Location:** constantine/math/elliptic/ec_twistededwards_batch_ops.nim:25
**Severity:** Low
**Confidence:** 0.8

**Diff Under Review:**
```diff
-       N: int) {.noInline, tags:[Alloca].} =
+       N: int) {.meter.} =
```

**Issue:** **`noInline` pragma removed along with `Alloca` tag — may increase compile-time**

The `batchAffine` function for twisted Edwards curves had `{.noInline, tags:[Alloca].}` changed to `{.meter.}`. The original `noInline` pragma was necessary because the function used `allocStackArray(SecretBool, N)` which doesn't work well with inlining. Since the stack allocation was removed (replaced by reusing `affs[i].y` for zero-tracking), inlining is now safe.

However, `batchAffine` is a relatively large function (80+ lines). Removing `noInline` could increase compile times for call sites that get it inlined.

**Issue Type:** convention-drift

**Scope:** constantine/math/elliptic/ec_twistededwards_batch_ops.nim:25

**Existing Pattern:** `ec_shortweierstrass_batch_ops.nim` keeps `noInline` off its `batchAffine` functions (they never had it), while this one had it historically.

**Suggested Change:** Acceptable change, but monitor compile times. Consider benchmarking compile-time impact.

---

### [CONSISTENCY] CONS-B-007: toOpenArray style inconsistency between benchmark and production - benchmarks/bench_kzg_multiproofs.nim:111-113

**Location:** benchmarks/bench_kzg_multiproofs.nim:111-113
**Severity:** Low
**Confidence:** 0.9

**Diff Under Review:**
```diff
     for offset in 0 ..< L:
-      makeCirculantMatrix(circulant.toOpenArray(0, CDS-1), poly.coefs, offset, L)
+      makeCirculantMatrix(circulant.toOpenArray(0, CDS-1), poly.coefs, offset, L)
       doAssert accum.accumulate(circulant.toOpenArray(0, CDS-1), ctx.polyphaseSpectrumBank[offset]) == Toeplitz_Success
     doAssert accum.finish(u.toOpenArray(0, CDS-1)) == Toeplitz_Success
```

**Issue:** **Benchmark uses `toOpenArray(0, CDS-1)` while production code uses `toOpenArray(CDS)`**

The benchmark file uses the two-arg `toOpenArray(0, CDS-1)` form while the production code in `kzg_multiproofs.nim` uses `toOpenArray(CDS)`. These are semantically equivalent but stylistically inconsistent within the same feature.

**Issue Type:** convention-drift

**Scope:**
- benchmarks/bench_kzg_multiproofs.nim:111-113
- constantine/commitments/kzg_multiproofs.nim:433, 438, 447

**Suggested Change:** Align both files to use the same `toOpenArray` style. Prefer `toOpenArray(0, CDS-1)` to match project convention (see CONS-B-003).

---

### [CONSISTENCY] CONS-B-008: bit_reversal_permutation renamed to bit_reversal_permutation_noalias + aliasing wrapper - constantine/math/polynomials/fft_common.nim:290

**Location:** constantine/math/polynomials/fft_common.nim:290-332
**Severity:** Informational
**Confidence:** 1.0

**Issue:** **Positive change: `bit_reversal_permutation` gains aliasing detection**

The original `bit_reversal_permutation` (with `{.noalias.}` constraint) was renamed to `bit_reversal_permutation_noalias`. A new `bit_reversal_permutation` wrapper detects aliasing at runtime via pointer comparison (`dst[0].addr == src[0].addr`) and falls back to a temporary buffer when needed. This correctly handles the case where `ec_fft_nn` calls bit reversal with the same buffer for input and output.

All 50+ call sites of `bit_reversal_permutation` were verified — they all call the two-arg or one-arg form, which now routes through the aliasing-aware wrapper. No call sites were broken.

**Issue Type:** missing-reuse (informational — positive change)

**Scope:** constantine/math/polynomials/fft_common.nim:290-332

**Suggested Change:** No change needed — this is a correct API improvement.

---

### [CONSISTENCY] CONS-B-009: N <= 0 guard added consistently to all batchAffine entry points - constantine/math/elliptic/ec_shortweierstrass_batch_ops.nim:30-32

**Location:** constantine/math/elliptic/ec_shortweierstrass_batch_ops.nim:30-32, 98-100, 185-187, 262-264
**Severity:** Informational
**Confidence:** 1.0

**Issue:** **Positive change: Defensive `N <= 0` guards added to all batchAffine variants**

Every entry point for both `batchAffine` and `batchAffine_vartime` (projective and Jacobian forms, short Weierstrass and twisted Edwards) now has a `if N <= 0: return` guard. This prevents undefined behavior from zero-length batch operations.

**Issue Type:** convention-drift (informational — positive change)

**Scope:**
- ec_shortweierstrass_batch_ops.nim: 4 entry points
- ec_twistededwards_batch_ops.nim: 2 entry points

**Suggested Change:** No change needed — this is a correct defensive programming improvement.

---

## Positive Changes

1. **`bit_reversal_permutation` aliasing awareness** — The rename of the no-alias version to `bit_reversal_permutation_noalias` and addition of an aliasing-detecting wrapper is a correct API improvement that prevents undefined behavior when callers pass overlapping buffers.

2. **`N <= 0` guards on all batchAffine entry points** — Defensive programming improvement applied consistently across all 6 `batchAffine`/`batchAffine_vartime` entry points (ShortWeierstrass + TwistedEdwards, const-time + vartime).

3. **`Alloca` tag removal from iterative EC FFT functions** — The `Alloca` tag was correctly removed only from functions that actually had their stack allocation eliminated (recursive → iterative transition). Functions that still use `alloca` (e.g., `ec_multi_scalar_mul.nim`) retain the tag, showing targeted and correct tag hygiene.

4. **`computeAggRandScaledInterpoly` bool→void with doAssert** — Converting from runtime error checking (`return false`) to assertions (`doAssert`) is appropriate for an internal function where callers are controlled. Simplifies the call site in `kzg_coset_verify_batch`.

5. **In-place FFT operations reduce heap allocations** — `computePolyphaseDecompositionFourierOffset` now writes directly to the output buffer instead of allocating a temporary `polyphaseComponent` buffer. Similarly, `ec_fft_nn` and `ec_ifft_nn` now support in-place operation, reducing allocations in `kzg_coset_prove`.
