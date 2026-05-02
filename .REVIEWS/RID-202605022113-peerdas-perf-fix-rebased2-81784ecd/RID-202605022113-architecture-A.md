---
**Branch:** `master` → `peerdas-perf-fix-rebased2` (commit `81784ecd`)
**Diff file:** `.REVIEWS/RID-202605022113-peerdas-perf-fix-rebased2-81784ecd/RID-202605022113-changes_under_review.diff`
**Date:** 2026-05-02
**Reviewer:** Architecture Analyst (Pass A)
**Scope:** PeerDAS performance optimization — new ToeplitzAccumulator, batchAffine_vartime, polyphase spectrum format change, FFT tag cleanup, bit_reversal aliasing fix
**Focus:** Interface design, data flow, dependency direction, module boundaries, incremental deliverability
---

# Architecture Review (Pass A)

## Summary

| ID | Severity | Confidence | File | Issue |
|----|----------|------------|------|-------|
| ARCH-A-001 | High | 1.0 | constantine/commitments_setups/ethereum_kzg_srs.nim:206 | Breaking API: `polyphaseSpectrumBank` type changed from Jacobian to Affine in `EthereumKZGContext` |
| ARCH-A-002 | High | 0.9 | constantine/math/matrix/toeplitz.nim:146–297 | `toeplitzMatVecMulPreFFT` removed — public API surface replaced by stateful `ToeplitzAccumulator` object |
| ARCH-A-003 | Medium | 0.9 | constantine/commitments/kzg_multiproofs.nim:502–594 | `computeAggRandScaledInterpoly` return type changed from `bool` to `void`; error path lost |
| ARCH-A-004 | Medium | 0.8 | constantine/math/matrix/toeplitz.nim:146–185 | Dual error type hierarchy: `ToeplitzStatus` maps `FFT_Status` but creates an ad-hoc union |
| ARCH-A-005 | Medium | 0.9 | benchmarks/bench_matrix_toeplitz.nim:170–181 | Benchmark uses `privateAccess` to mutate `ToeplitzAccumulator.offset` — leaks implementation detail |
| ARCH-A-006 | Medium | 0.9 | constantine/math/elliptic/ec_shortweierstrass_batch_ops.nim:185–344 | `batchAffine_vartime` replaces `batchAffine` across commitment layer — variable-time semantics propagate into verification paths |
| ARCH-A-007 | Low | 0.8 | constantine/math/polynomials/fft_ec.nim:67–415 | `Alloca` effect tag removed from all FFT functions — effect contracts no longer reflect implementation |
| ARCH-A-008 | Low | 0.9 | constantine/math/polynomials/fft_common.nim:290–324 | `bit_reversal_permutation` split into `_noalias` + aliasing dispatcher — new public symbol added |
| ARCH-A-009 | Low | 0.7 | constantine/math/matrix/toeplitz.nim:297 | `toeplitzMatVecMul` delegates to `ToeplitzAccumulator` — general-purpose API leaks FK20-specific pattern |

**Key takeaways:**
1. The `ToeplitzAccumulator` is the most significant new abstraction, replacing the old function-based `toeplitzMatVecMulPreFFT` API with a stateful accumulator pattern. This is a clean design for the FK20 use case but introduces state management concerns.
2. The polyphase spectrum bank type change (Jacobian → Affine) is a breaking API change to `EthereumKZGContext` that requires coordinated migration across all consumers.
3. The widespread replacement of `batchAffine` with `batchAffine_vartime` propagates variable-time semantics into paths that previously used constant-time operations, including verification code.
4. Error handling is downgraded: `computeAggRandScaledInterpoly` went from returning `bool` to using `doAssert`, losing graceful error recovery for callers.

## Findings

### [ARCHITECTURE] ARCH-A-001: Breaking API — `polyphaseSpectrumBank` type changed from Jacobian to Affine in `EthereumKZGContext` — constantine/commitments_setups/ethereum_kzg_srs.nim:206

**Location:** constantine/commitments_setups/ethereum_kzg_srs.nim:206
**Severity:** High
**Confidence:** 1.0

**Diff Under Review:**
```diff
-    polyphaseSpectrumBank*{.align: 64.}: array[FIELD_ELEMENTS_PER_CELL, array[CELLS_PER_EXT_BLOB, EC_ShortW_Jac[Fp[BLS12_381], G1]]]
+    polyphaseSpectrumBank*{.align: 64.}: array[FIELD_ELEMENTS_PER_CELL, array[CELLS_PER_EXT_BLOB, EC_ShortW_Aff[Fp[BLS12_381], G1]]]
```

**Issue:** **Breaking type change to a public context struct**

The `polyphaseSpectrumBank` field in `EthereumKZGContext` changed from Jacobian form (`EC_ShortW_Jac`) to Affine form (`EC_ShortW_Aff`). This is a breaking API change because:

1. **Memory layout change:** Affine points (2 × 32 bytes = 64 bytes per point) vs Jacobian points (3 × 32 bytes = 96 bytes per point) — the total bank size changes from ~1.18 MB to ~0.78 MB.
2. **All type declarations break:** Any code declaring the spectrum bank type must update from `EC_ShortW_Jac` to `EC_ShortW_Aff`. This affects test files, benchmarks, and the `kzg_coset_prove` API.
3. **Serialization incompatibility:** If the context is serialized/deserialized (e.g., for trusted setup caching), the new format is incompatible with old data.

The change is internally consistent across the diff (all call sites updated), but it is a breaking change that cannot be deployed incrementally without ensuring all consumers are updated simultaneously.

**Concern Type:** interface-design

**Suggested Change:** 
- Document the breaking change in a migration guide or changelog
- If the context supports loading from files, add format version detection to handle both Jacobian and Affine formats during a migration period
- Consider a `deprecated` transition period where the context can load either format but always produces the new format

**Migration Path:** All consumers of `EthereumKZGContext.polyphaseSpectrumBank` must update their type declarations from `EC_ShortW_Jac` to `EC_ShortW_Aff`. Verified in the diff that all test and benchmark files have been updated.

---

### [ARCHITECTURE] ARCH-A-002: `toeplitzMatVecMulPreFFT` removed — public API surface replaced by stateful `ToeplitzAccumulator` object — constantine/math/matrix/toeplitz.nim:146–297

**Location:** constantine/math/matrix/toeplitz.nim:146–297
**Severity:** High
**Confidence:** 0.9

**Diff Under Review:**
```diff
-proc toeplitzMatVecMulPreFFT*[EC, F](
-  output: var openArray[EC],
-  circulant: openArray[F],
-  vFft: openArray[EC],
-  frFftDesc: FrFFT_Descriptor[F],
-  ecFftDesc: ECFFT_Descriptor[EC],
-  accumulate: bool = false
-): FFTStatus {.meter.} =
...
+type
+  ToeplitzAccumulator*[EC, ECaff, F] = object
+    frFftDesc: FrFFT_Descriptor[F]
+    ecFftDesc: ECFFT_Descriptor[EC]
+    coeffs: ptr UncheckedArray[F]
+    points: ptr UncheckedArray[ECaff]
+    scratchScalars: ptr UncheckedArray[F]
+    size: int
+    L: int
+    offset: int
+proc init* / accumulate* / finish* ...
```

**Issue:** **Public API redesign from function-based to stateful object pattern**

The `toeplitzMatVecMulPreFFT` function (exported with `*`) has been removed entirely and replaced by the `ToeplitzAccumulator` object type with `init`/`accumulate`/`finish` methods. This is a significant API surface change:

1. **State management:** The old API was stateless — each call was independent. The new API requires the caller to manage an accumulator lifecycle: `init()` → `accumulate()` × L → `finish()`.
2. **Resource ownership:** `ToeplitzAccumulator` owns heap-allocated buffers (`coeffs`, `points`, `scratchScalars`) managed by `=destroy`. The `=copy` is deliberately disabled (`.error.`), requiring careful ownership semantics.
3. **`toeplitzMatVecMul` repurposed:** The remaining public `toeplitzMatVecMul` function now internally uses `ToeplitzAccumulator` as an implementation detail, creating an unnecessary layer of indirection for the non-FK20 use case.
4. **`FFT_Status` → `ToeplitzStatus`:** Return types changed from `FFT_Status` to `ToeplitzStatus`, requiring callers to update assertions.

The new API is well-designed for the FK20 accumulation pattern (64 accumulate calls + 1 finish with MSM + IFFT). However, for code that only needed a single Toeplitz multiply without accumulation, this is a regression in API simplicity.

**Concern Type:** interface-design

**Suggested Change:**
- Keep `toeplitzMatVecMul` as the primary public API for single-shot use (already done — it wraps the accumulator)
- Document that `ToeplitzAccumulator` is the preferred API for FK20-style multi-accumulate patterns
- Consider whether `ToeplitzAccumulator` should be `*[...]` (public) or only accessible via `toeplitzMatVecMul` if the accumulation pattern is too FK20-specific

---

### [ARCHITECTURE] ARCH-A-003: `computeAggRandScaledInterpoly` return type changed from `bool` to `void`; error path lost — constantine/commitments/kzg_multiproofs.nim:502–594

**Location:** constantine/commitments/kzg_multiproofs.nim:502–594
**Severity:** Medium
**Confidence:** 0.9

**Diff Under Review:**
```diff
-     N: static int): bool {.meter.} =
+     N: static int) {.meter.} =
...
-  if evals.len != evalsCols.len or linearIndepRandNumbers.len < evalsCols.len:
-    return false
+  doAssert evals.len == evalsCols.len, "Internal error: evals and evalsCols must have same length"
+  doAssert linearIndepRandNumbers.len >= evalsCols.len, "Internal error: linearIndepRandNumbers must cover all evals"
...
-  if not interpoly.computeAggRandScaledInterpoly(
+  interpoly.computeAggRandScaledInterpoly(
     evals,
     evalsCols,
     domain,
     linearIndepRandNumbers,
     N
-  ):
-    return false
```

**Issue:** **Error handling downgraded from return-value to assertion**

The function `computeAggRandScaledInterpoly` previously returned `bool` to indicate validation success/failure. The caller (`kzg_coset_verify_batch`) would check the return value and propagate `false` upward. The change replaces all validation checks with `doAssert` and removes the return value entirely.

**Architectural concern:** The verification path (`kzg_coset_verify_batch`) previously could reject invalid input gracefully by returning `false`. After this change:
- In **debug builds**: Invalid input triggers `doAssert` → crash (acceptable for development)
- In **release builds**: `doAssert` is stripped → invalid input silently produces garbage output (concerning for production verification)

This is an architectural regression in error handling: the boundary between "trustworthy caller" and "potentially untrusted input" has shifted. If the caller is always trusted (internal API only), this is acceptable. If there's any external input path, this is a reliability concern.

**Concern Type:** module-boundary

**Suggested Change:**
- If this is strictly an internal API (caller always trusted), document the contract explicitly
- Consider keeping the `bool` return type but converting validation to `when debug:` assertions in release, with return-value checks in debug
- Alternative: use `doAssert` for invariants but keep a `bool` return for preconditions

---

### [ARCHITECTURE] ARCH-A-004: Dual error type hierarchy — `ToeplitzStatus` maps `FFT_Status` but creates an ad-hoc union — constantine/math/matrix/toeplitz.nim:146–185

**Location:** constantine/math/matrix/toeplitz.nim:146–185
**Severity:** Medium
**Confidence:** 0.8

**Diff Under Review:**
```diff
+type
+  ToeplitzStatus* = enum
+    Toeplitz_Success
+    Toeplitz_SizeNotPowerOfTwo
+    Toeplitz_TooManyValues
+    Toeplitz_MismatchedSizes
...
+    elif status is FFTStatus:
+      if status != FFT_Success:
+        result = case status
+          of FFT_SizeNotPowerOfTwo: Toeplitz_SizeNotPowerOfTwo
+          of FFT_TooManyValues: Toeplitz_TooManyValues
+          else: Toeplitz_MismatchedSizes
```

**Issue:** **Redundant error type with lossy mapping from `FFT_Status`**

The new `ToeplitzStatus` enum is a 1:3 mapping from `FFT_Status` — three distinct `FFT_Status` values collapse into a single `Toeplitz_MismatchedSizes`. This creates:

1. **Loss of diagnostic information:** A caller checking `Toeplitz_MismatchedSizes` cannot distinguish between `FFT_InvalidStride`, `FFT_OrderMismatch`, or other FFT-specific errors.
2. **Dual error handling:** Callers must handle two different error enums when the underlying domain (FFT) produces errors.
3. **Maintenance burden:** If `FFT_Status` gains new variants, the `case` mapping must be updated (no `else` branch to catch missing cases — the `else: Toeplitz_MismatchedSizes` silently absorbs unknown errors).

**Concern Type:** interface-design

**Suggested Change:**
- Either make `ToeplitzStatus` a true superset (include all `FFT_Status` variants) 
- Or use a wrapper type like `Result[void, ToeplitzError]` that can carry the original `FFT_Status` as context
- At minimum, add a `static: doAssert` to verify that the mapping covers all `FFT_Status` variants

---

### [ARCHITECTURE] ARCH-A-005: Benchmark uses `privateAccess` to mutate `ToeplitzAccumulator.offset` — leaks implementation detail — benchmarks/bench_matrix_toeplitz.nim:170–181

**Location:** benchmarks/bench_matrix_toeplitz.nim:170–181
**Severity:** Medium
**Confidence:** 0.9

**Diff Under Review:**
```diff
+  # Allow direct access to private 'offset' field for benchmark reuse
+  privateAccess(toeplitz.ToeplitzAccumulator)
...
+    # Reset accumulator state for this iteration (avoids free+alloc)
+    acc.offset = 0
```

**Issue:** **Benchmark depends on private implementation detail of `ToeplitzAccumulator`**

The benchmark file uses `privateAccess` to directly mutate the `offset` field of `ToeplitzAccumulator` to reset its state between benchmark iterations, avoiding the cost of `free` + `init`. This is a valid optimization for benchmarking, but it:

1. **Couples benchmark to implementation:** If the `offset` field is renamed or its semantics change, the benchmark silently breaks.
2. **Bypasses the reset protocol:** The accumulator's `init()` method does more than just set `offset = 0` — it also clears the `coeffs` and `points` buffers. Direct mutation leaves stale data in those buffers.
3. **Should be a public API:** If the use case (reusing an accumulator across iterations) is legitimate, a `reset()` method should be provided.

**Concern Type:** module-boundary

**Suggested Change:**
- Add a `reset*()` method to `ToeplitzAccumulator` that reinitializes `offset = 0` and clears internal buffers
- Remove `privateAccess` from the benchmark and call `acc.reset()` instead
- If `reset()` is benchmark-only, document it as such and consider not exporting it with `*`

---

### [ARCHITECTURE] ARCH-A-006: `batchAffine_vartime` replaces `batchAffine` across commitment layer — variable-time semantics propagate into verification paths — constantine/math/elliptic/ec_shortweierstrass_batch_ops.nim:185–344

**Location:** constantine/math/elliptic/ec_shortweierstrass_batch_ops.nim:185–344 (definition); constantine/commitments/kzg.nim:363, constantine/commitments/kzg_parallel.nim:170, constantine/commitments/eth_verkle_ipa.nim:225/260/649, constantine/commitments/kzg_multiproofs.nim:364/458 (call sites)
**Severity:** Medium
**Confidence:** 0.9

**Diff Under Review:**
```diff
-  commits_min_evals.batchAffine(commits_min_evals_jac, n)
+  commits_min_evals.batchAffine_vartime(commits_min_evals_jac, n)
...
-    lrAff.batchAffine(lr)
+    lrAff.batchAffine_vartime(lr)
...
-    tab.batchAffine(tabEC)
+    tab.batchAffine_vartime(tabEC)
```

**Issue:** **Variable-time batch conversion propagated into verification and general-purpose paths**

The `batchAffine_vartime` functions are new implementations that skip constant-time masking of zero (infinity) coordinates. They are used to save computation when ~50% of points are infinity (as in the polyphase spectrum bank where half the points are neutral).

The concern is architectural: the diff replaces `batchAffine` with `batchAffine_vartime` in multiple paths:

1. **`kzg_verify_batch`** (kzg.nim) — A **verification** path. Variable-time behavior here means timing depends on the input data (number of non-neutral points). While the number of non-neutral points is deterministic in this context (n is always the same), the function contract no longer guarantees constant-time behavior.
2. **`kzg_parallel.nim`** — Parallel verification batch, same concern.
3. **`eth_verkle_ipa.nim`** — IPA proving paths, where `batchAffine_vartime` is used.
4. **`ec_scalar_mul_vartime.nim`** — Scalar multiplication precomputation tables use `batchAffine_vartime`. This is acceptable because the parent function is already `vartime`.

**Concern Type:** interface-design

**Suggested Change:**
- Add explicit `{.tags: [VarTime].}` markers to all call sites that use `batchAffine_vartime` so the effect system tracks variable-time paths
- In verification paths (`kzg_verify_batch`), document whether variable-time is acceptable or if constant-time is required
- Consider keeping the original `batchAffine` as the default and requiring callers to explicitly opt into `batchAffine_vartime` with a comment justifying the vartime choice

---

### [ARCHITECTURE] ARCH-A-007: `Alloca` effect tag removed from all FFT functions — effect contracts no longer reflect implementation — constantine/math/polynomials/fft_ec.nim:67–415

**Location:** constantine/math/polynomials/fft_ec.nim:67–415
**Severity:** Low
**Confidence:** 0.8

**Diff Under Review:**
```diff
-       vals: openarray[EC]): FFTStatus {.tags: [VarTime, Alloca], meter.} =
+       vals: openarray[EC]): FFTStatus {.tags: [VarTime], meter.} =
...
-       vals: openarray[EC]): FFTStatus {.tags: [VarTime, Alloca], meter.} =
+       vals: openarray[EC]): FFTStatus {.tags: [VarTime], meter.} =
```

**Issue:** **`Alloca` tag systematically removed from FFT function signatures**

The `Alloca` effect tag has been removed from all EC FFT functions (iterative DIF, DIT, and NN variants). This reflects the implementation change where stack-allocated temporary buffers have been eliminated in favor of heap allocation or in-place operations.

While this is technically correct (the functions no longer use alloca), it represents an **effect contract change** that callers depending on the `Alloca` tag for their own effect analysis may need to update. The `HeapAlloc` tag was already present on the NN variants, so this is a narrowing rather than a widening of effects.

**Concern Type:** interface-design

**Suggested Change:**
- Verify that no callers have `{.raises: [AllocaError].}` handlers that would no longer trigger
- Update any documentation or comments that reference stack allocation in FFT functions
- This is a low-priority change — the effect narrowing is generally safe (fewer side effects)

---

### [ARCHITECTURE] ARCH-A-008: `bit_reversal_permutation` split into `_noalias` + aliasing dispatcher — new public symbol added — constantine/math/polynomials/fft_common.nim:290–324

**Location:** constantine/math/polynomials/fft_common.nim:290–324
**Severity:** Low
**Confidence:** 0.9

**Diff Under Review:**
```diff
-func bit_reversal_permutation*[T](dst{.noalias.}: var openArray[T], src{.noalias.}: openArray[T]) {.inline.} =
+func bit_reversal_permutation_noalias*[T](dst{.noalias.}: var openArray[T], src{.noalias.}: openArray[T]) {.inline.} =
...
+func bit_reversal_permutation*[T](dst: var openArray[T], src: openArray[T]) =
+  if dst[0].addr == src[0].addr:
+    var tmp = allocHeapArrayAligned(T, src.len, alignment = 64)
+    bit_reversal_permutation_noalias(tmp.toOpenArray(0, src.len-1), src)
+    copyMem(dst[0].addr, tmp[0].addr, src.len * sizeof(T))
+    freeHeapAligned(tmp)
+  else:
+    bit_reversal_permutation_noalias(dst, src)
```

**Issue:** **Public API adds aliasing-aware dispatch with new exported symbol**

The original `bit_reversal_permutation` (out-of-place, noalias) was renamed to `bit_reversal_permutation_noalias`. A new `bit_reversal_permutation` now dispatches based on aliasing detection. This:

1. **Adds a new public symbol:** `bit_reversal_permutation_noalias` is exported with `*`, expanding the public API surface.
2. **Changes semantics of the original:** Code that directly called `bit_reversal_permutation(dst, src)` previously had the `{.noalias.}` constraint enforced by the compiler. Now it does aliasing detection at runtime. The `{.noalias.}` constraint is removed, so callers can no longer rely on compiler enforcement.
3. **Performance impact:** The aliasing check (`dst[0].addr == src[0].addr`) adds a branch to what was previously a simple inline call.

This is a beneficial change for correctness (in-place FFT was previously UB), but it is a public API change.

**Concern Type:** interface-design

**Suggested Change:**
- Consider whether `bit_reversal_permutation_noalias` should remain public (`*`) or be internal — it's only needed if callers want to guarantee no aliasing
- Document the aliasing behavior in the `bit_reversal_permutation` docstring

---

### [ARCHITECTURE] ARCH-A-009: `toeplitzMatVecMul` delegates to `ToeplitzAccumulator` — general-purpose API leaks FK20-specific pattern — constantine/math/matrix/toeplitz.nim:308–378

**Location:** constantine/math/matrix/toeplitz.nim:308–378
**Severity:** Low
**Confidence:** 0.7

**Diff Under Review:**
```diff
+  ## This implements the circulant embedding method using the ToeplitzAccumulator API:
+  ## 1. FFT of zero-extended vector (EC points)
+  ## 2. FFT of circulant coefficients (field elements)
+  ## 3. Accumulate into ToeplitzAccumulator (stores FFT results transposed)
+  ## 4. MSM per output position, then IFFT
...
+  var acc: ToeplitzAccumulator[EC, ECaff, F]
...
+    check HappyPath, acc.init(frFftDesc, ecFftDesc, n2, L = 1)
+    check HappyPath, acc.accumulate(circulant, vExtFftAff.toOpenArray(n2))
```

**Issue:** **General-purpose `toeplitzMatVecMul` uses FK20-specific `ToeplitzAccumulator` internally**

The `toeplitzMatVecMul` function is a general-purpose Toeplitz matrix-vector multiply. After this change, it internally creates a `ToeplitzAccumulator` with `L = 1` (single accumulate call) to do the work. This:

1. **Over-allocates for single-shot use:** The accumulator pre-allocates `coeffs[size * L]` and `points[size * L]` buffers. With `L = 1`, this is `size` elements each — not terrible, but the `ToeplitzAccumulator` was designed for `L = 64` (FK20).
2. **Couples general API to FK20 implementation:** The general-purpose function is now an implementation detail of the FK20 pattern rather than an independent algorithm.
3. **Extra batchAffine step:** The function does `batchAffine_vartime` on the FFT output before accumulating, which was not needed in the old direct FFT→Hadamard→IFFT pipeline.

**Concern Type:** dependency-direction

**Suggested Change:**
- Consider keeping a direct implementation of `toeplitzMatVecMul` (FFT circulant, Hadamard, IFFT) as the baseline
- Use `ToeplitzAccumulator` only for the FK20 multi-accumulate pattern in `kzg_coset_prove`
- Alternatively, document that `ToeplitzAccumulator` is the canonical implementation and `toeplitzMatVecMul` is a convenience wrapper

---

## Positive Changes

1. **`ToeplitzAccumulator` pre-allocates buffers:** The accumulator's `init()` allocates `coeffs`, `points`, and `scratchScalars` once, eliminating per-iteration heap allocation in the FK20 hot path. This is a clean optimization that separates allocation concerns from computation.

2. **`batchAffine_vartime` handles infinity points efficiently:** The new vartime batch conversion skips inversion for points at infinity, saving ~3×L×CDS field inversions in the polyphase spectrum bank (where 50% of points are neutral). This is a well-targeted optimization for the FK20 use case.

3. **`bit_reversal_permutation` aliasing fix:** The aliasing-aware dispatcher makes in-place FFT (`dst == src`) safe instead of undefined behavior. This is a correctness improvement with a clean implementation pattern.

4. **In-place FFT in `computePolyphaseDecompositionFourierOffset`:** Eliminated the temporary `polyphaseComponent` buffer by computing directly into `polyphaseSpectrum`, reducing peak memory usage by one CDS-sized EC point array.

5. **`Alloca` tag removal:** Eliminating stack allocation from FFT functions improves predictability of resource usage and avoids potential stack overflow on deep recursive FFT calls.

---

## No additional findings.
