---
**Branch:** `master` → `peerdas-perf-fix-rebased2` (commit `74d1839c`)
**Diff file:** `.REVIEWS/RID-202605022039-peerdas-perf-fix-rebased2-74d1839c/RID-202605022039-changes_under_review.diff`
**Date:** 2026-05-02
**Reviewer:** Architecture Analyst (Pass B)
**Scope:** Architectural review of PeerDAS performance fix: ToeplitzAccumulator abstraction, batchAffine_vartime, polyphaseSpectrumBank type change, bit_reversal_permutation split, FFT tag cleanup, and new transpose module
**Focus:** Module coupling, API surface changes, data ownership, abstraction quality, new abstractions warranted
---

# Architecture Review (Pass B)

## Summary

| ID | Severity | Confidence | File | Issue |
|----|----------|------------|------|-------|
| ARCH-B-001 | Medium | 0.9 | `constantine/math/matrix/toeplitz.nim` | Procedural API replaced by stateful object breaks composability expectations |
| ARCH-B-002 | Medium | 0.9 | `constantine/math/matrix/toeplitz.nim` | Dual error type hierarchy (ToeplitzStatus / FFT_Status) adds caller burden |
| ARCH-B-003 | Medium | 0.9 | `constantine/commitments_setups/ethereum_kzg_srs.nim` | polyphaseSpectrumBank type change (Jac→Aff) is a struct-layout breaking change |
| ARCH-B-004 | Medium | 0.9 | `constantine/commitments/kzg_multiproofs.nim` | computeAggRandScaledInterpoly shifts from return-code error handling to doAssert crash |
| ARCH-B-005 | Low | 0.9 | `constantine/math/polynomials/fft_common.nim` | bit_reversal_permutation rename + dispatcher adds indirection for existing callers |
| ARCH-B-006 | Low | 0.8 | `constantine/math/polynomials/fft_ec.nim` | Removing Alloca tag from functions that may still use stack arrays obscures stack profile |
| ARCH-B-007 | Low | 0.9 | `constantine/math/matrix/toeplitz.nim` | Scratch buffer type-punned via pointer cast relies on fragile sizeof invariant |
| ARCH-B-008 | Low | 0.8 | `constantine/math/elliptic/ec_shortweierstrass_batch_ops.nim` | batchAffine (ct) and batchAffine_vartime have inconsistent N≤0 guard semantics |
| ARCH-B-009 | Informational | 1.0 | `constantine/math/matrix/transpose.nim` | New transpose module is standalone and clean, but not referenced by any production path |

**Key takeaways:**
1. The shift from procedural `toeplitzMatVecMulPreFFT` to stateful `ToeplitzAccumulator` is the most consequential architectural change — it introduces lifecycle management (init/accumulate/finish) where none existed before, and adds a new error type hierarchy.
2. The `polyphaseSpectrumBank` type change from `EC_ShortW_Jac` to `EC_ShortW_Aff` changes the binary layout of `EthereumKZGContext`, which is a breaking ABI change for any persisted setup or cross-module contract.
3. Several error-handling contracts shift from return-code (caller can decide) to `doAssert` (unconditional crash), reducing caller flexibility.
4. New `batchAffine_vartime` family and `ToeplitzAccumulator` are properly guarded with `{.error.}` on copy and RAII destroy, following good patterns.

## Findings

### [ARCHITECTURE] ARCH-B-001: Procedural API replaced by stateful object breaks composability expectations — `constantine/math/matrix/toeplitz.nim`

**Location:** `constantine/math/matrix/toeplitz.nim` (lines 145–300 in new code)
**Severity:** Medium
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
+proc init*[EC, ECaff, F](ctx: var ToeplitzAccumulator[EC, ECaff, F], ...): ToeplitzStatus
+proc accumulate*[EC, ECaff, F](ctx: var ToeplitzAccumulator[EC, ECaff, F], circulant: openArray[F], vFft: openArray[ECaff]): ToeplitzStatus
+proc finish*[EC, ECaff, F](ctx: var ToeplitzAccumulator[EC, ECaff, F], output: var openArray[EC]): ToeplitzStatus
```

**Issue:** **Stateful accumulator replaces stateless procedural API**

The old `toeplitzMatVecMulPreFFT` was a pure function: given inputs, it produced an output. It was composable, testable, and had no lifecycle concerns. The new `ToeplitzAccumulator` introduces a state machine with `init → accumulate(N times) → finish` lifecycle. This means:

1. **Callers must now manage object lifetime.** While `=destroy` is defined, the caller must ensure `finish` is called before the accumulator goes out of scope for correct results. If `finish` is skipped (e.g., due to an early return), the internal buffers are freed but the computation is incomplete — no diagnostic.

2. **The `toeplitzMatVecMul` wrapper** for the L=1 case now internally uses `ToeplitzAccumulator`, hiding the complexity but also masking the internal structure. This is a "leaky" composition: the caller sees a simple function but the implementation goes through 3 heap allocations (coeffs, points, scratchScalars) that were not needed in the direct path.

3. **Error recovery is harder.** In the old model, each call to `toeplitzMatVecMulPreFFT` was independent. If one failed, the caller could retry. With the accumulator, failure mid-sequence leaves the object in an uncertain state (offset partially incremented), and there's no `reset` method — the caller must re-init.

**Concern Type:** module-boundary

**Suggested Change:** Add a `reset` method or document that `init` can be called to reuse an existing accumulator. Consider adding an `offset != L` check in `=destroy` to warn about unfinished accumulators in debug builds.

---

### [ARCHITECTURE] ARCH-B-002: Dual error type hierarchy (ToeplitzStatus / FFT_Status) adds caller burden — `constantine/math/matrix/toeplitz.nim`

**Location:** `constantine/math/matrix/toeplitz.nim` (lines 145–185)
**Severity:** Medium
**Confidence:** 0.9

**Diff Under Review:**
```diff
-proc toeplitzMatVecMulPreFFT[...]: FFTStatus
+type ToeplitzStatus* = enum
+    Toeplitz_Success
+    Toeplitz_SizeNotPowerOfTwo
+    Toeplitz_TooManyValues
+    Toeplitz_MismatchedSizes
+
+template checkReturn*(evalExpr: untyped): untyped {.dirty.} =
+  block:
+    let status = evalExpr
+    when status is ToeplitzStatus:
+      if status != Toeplitz_Success: return status
+    elif status is FFTStatus:
+      if status != FFT_Success:
+        return case status
+          of FFT_SizeNotPowerOfTwo: Toeplitz_SizeNotPowerOfTwo
+          of FFT_TooManyValues: Toeplitz_TooManyValues
+          else: Toeplitz_MismatchedSizes
+
+template check*(Section: untyped, evalExpr: untyped): untyped {.dirty.} =
+  # ... same mapping logic ...
```

**Issue:** **Two status types with implicit mapping creates hidden coupling**

`ToeplitzStatus` is presented as a distinct error domain, but its values are just a thin wrapper around `FFTStatus`. The mapping in `checkReturn` and `check` templates:
- Loses information: multiple `FFTStatus` values can map to the same `ToeplitzStatus`
- Creates two parallel hierarchies that callers must understand
- The `Toeplitz_MismatchedSizes` catch-all in the FFTStatus mapping obscures the original error cause

This also creates a split in the `kzg_multiproofs.nim` caller: some paths return `FFT_Status` (from `ec_fft_nn`) and others return `ToeplitzStatus` (from `accum.accumulate`), requiring the caller to handle both types.

**Concern Type:** interface-design

**Suggested Change:** Either (a) make `ToeplitzStatus` a true superset with Toeplitz-specific errors (e.g., `Toeplitz_OffsetMismatch`, `Toeplitz_AccumulateWithoutInit`) and keep FFT errors transparent, or (b) unify on a single status type. The current partial mapping is the worst of both worlds.

---

### [ARCHITECTURE] ARCH-B-003: polyphaseSpectrumBank type change (Jac→Aff) is a struct-layout breaking change — `constantine/commitments_setups/ethereum_kzg_srs.nim`

**Location:** `constantine/commitments_setups/ethereum_kzg_srs.nim` (line ~203)
**Severity:** Medium
**Confidence:** 0.9

**Diff Under Review:**
```diff
-    polyphaseSpectrumBank*{.align: 64.}: array[FIELD_ELEMENTS_PER_CELL, array[CELLS_PER_EXT_BLOB, EC_ShortW_Jac[Fp[BLS12_381], G1]]]
+    polyphaseSpectrumBank*{.align: 64.}: array[FIELD_ELEMENTS_PER_CELL, array[CELLS_PER_EXT_BLOB, EC_ShortW_Aff[Fp[BLS12_381], G1]]]
```

**Issue:** **Binary-incompatible change to a public context struct**

`EthereumKZGContext` is the central context type for KZG operations. Changing `polyphaseSpectrumBank` from `EC_ShortW_Jac` to `EC_ShortW_Aff` changes:

1. **Memory layout:** `EC_ShortW_Jac` has 3 field elements (x, y, z) while `EC_ShortW_Aff` has 2 (x, y). For BLS12-381, this changes the struct size by ~64×128×32 bytes ≈ 256 KB. Any code that depends on the struct size or offset will break.

2. **Persisted data:** If the context is ever serialized/deserialized (e.g., from disk), existing serialized data will be incompatible.

3. **Cross-module contracts:** Any module that holds a reference to `EthereumKZGContext` and expects Jacobian coordinates must be updated.

The change is well-motivated (affine points are smaller and directly usable by the ToeplitzAccumulator), but it is a breaking ABI change that should be documented.

**Concern Type:** incremental-deliverability

**Suggested Change:** Document this as a breaking change in a migration guide. If there's any persisted setup data, provide a migration path. Consider a version tag on the context struct.

---

### [ARCHITECTURE] ARCH-B-004: computeAggRandScaledInterpoly shifts from return-code error handling to doAssert crash — `constantine/commitments/kzg_multiproofs.nim`

**Location:** `constantine/commitments/kzg_multiproofs.nim` (lines 502–579)
**Severity:** Medium
**Confidence:** 0.9

**Diff Under Review:**
```diff
-func computeAggRandScaledInterpoly[Name: static Algebra, L: static int](
-      ...
-      N: static int): bool {.meter.} =
-  ...
-  if evals.len != evalsCols.len or linearIndepRandNumbers.len < evalsCols.len:
-    return false
-  ...
-  for k in 0 ..< evalsCols.len:
-    let c = evalsCols[k]
-    if c < 0 or c >= NumCols:
-      return false
-  ...
-  return true
+func computeAggRandScaledInterpoly[Name: static Algebra, L: static int](
+      ...
+      N: static int) {.meter.} =
+  doAssert evals.len == evalsCols.len, "Internal error: evals and evalsCols must have same length"
+  doAssert linearIndepRandNumbers.len >= evalsCols.len, "Internal error: linearIndepRandNumbers must cover all evals"
+  ...
+  for k in 0 ..< evalsCols.len:
+    let c = evalsCols[k]
+    doAssert c >= 0 and c < NumCols, "Internal error: Column index out of bounds: " & $c
```

**Issue:** **Error handling contract changed from graceful to fatal**

The function changed from returning `bool` (allowing the caller to handle validation failures gracefully) to using `doAssert` (crashing with an assertion failure). This is a semantic change that affects all callers:

- Before: `kzg_coset_verify_batch` could check `if not interpoly.computeAggRandScaledInterpoly(...): return false`
- After: `interpoly.computeAggRandScaledInterpoly(...)` — on failure, the program aborts

This tightens the contract: the function now asserts that inputs are always valid (hence "Internal error" messages). This is appropriate if callers are internal and inputs are validated upstream, but it removes a layer of defensive programming.

**Concern Type:** interface-design

**Suggested Change:** If this is intentional (the function is now "internal" with invariant-checked inputs), add a non-exported marker or rename to indicate the contract change (e.g., prefix with `computeAssumeValid*`).

---

### [ARCHITECTURE] ARCH-B-005: bit_reversal_permutation rename + dispatcher adds indirection for existing callers — `constantine/math/polynomials/fft_common.nim`

**Location:** `constantine/math/polynomials/fft_common.nim` (lines 287–348)
**Severity:** Low
**Confidence:** 0.9

**Diff Under Review:**
```diff
-func bit_reversal_permutation*[T](dst{.noalias.}: var openArray[T], src{.noalias.}: openArray[T]) {.inline.} =
-  ## Out-of-place bit reversal permutation.
+func bit_reversal_permutation_noalias*[T](dst{.noalias.}: var openArray[T], src{.noalias.}: openArray[T]) {.inline.} =
+  ## Out-of-place bit reversal permutation (no aliasing between dst and src).
+
+func bit_reversal_permutation*[T](dst: var openArray[T], src: openArray[T]) {.inline.} =
+  ## Out-of-place bit reversal permutation with aliasing detection.
+  if dst[0].addr == src[0].addr:
+    var tmp = allocHeapArrayAligned(T, src.len, alignment = 64)
+    bit_reversal_permutation_noalias(tmp.toOpenArray(0, src.len-1), src)
+    copyMem(dst[0].addr, tmp[0].addr, src.len * sizeof(T))
+    freeHeapAligned(tmp)
+  else:
+    bit_reversal_permutation_noalias(dst, src)
```

**Issue:** **API rename with dispatcher introduces heap allocation in previously allocation-free path**

The original `bit_reversal_permutation` had `{.noalias.}` constraints, meaning callers were responsible for ensuring non-aliasing. The function was allocation-free.

The new dispatcher:
1. Checks for aliasing at runtime (adding a branch)
2. On alias, allocates a temporary buffer on the heap
3. The `_noalias` version is a new export that existing callers might not know about

While this makes the API more robust (handles aliasing automatically), it changes the performance profile: a previously zero-allocation call now has a runtime check and potential allocation. Callers who know their data is non-aliased should use `_noalias` directly to avoid the overhead, but this creates a discoverability problem.

**Concern Type:** data-flow

**Suggested Change:** Document the performance difference between `_noalias` and the dispatcher. Consider keeping both with clear naming conventions (e.g., `_unchecked` for the non-aliasing variant instead of `_noalias`).

---

### [ARCHITECTURE] ARCH-B-006: Removing Alloca tag from functions that may still use stack arrays obscures stack profile — `constantine/math/polynomials/fft_ec.nim`

**Location:** `constantine/math/polynomials/fft_ec.nim` (multiple lines, removing `Alloca` from `{.tags: [VarTime, Alloca].}` → `{.tags: [VarTime].}`)
**Severity:** Low
**Confidence:** 0.8

**Diff Under Review:**
```diff
 func ec_fft_nn_impl_recursive[EC; bits: static int](
        output: var StridedView[EC],
        vals: StridedView[EC],
-       rootsOfUnity: StridedView[BigInt[bits]]) {.tags: [VarTime, Alloca].} =
+       rootsOfUnity: StridedView[BigInt[bits]]) {.tags: [VarTime].} =

 func ec_fft_nr_impl_iterative_dif[EC; bits: static int](
        output: var StridedView[EC],
-       rootsOfUnity: StridedView[BigInt[bits]]) {.tags: [VarTime, Alloca].} =
+       rootsOfUnity: StridedView[BigInt[bits]]) {.tags: [VarTime].} =
```

**Issue:** **Tag removal may be inaccurate and misleads callers about resource requirements**

Multiple EC FFT functions had the `Alloca` tag removed. However, some of these functions call `allocStackArray` internally (via `accum_half_vartime` in `ec_shortweierstrass_batch_ops.nim` or via `ec_fft_nn_via_iterative_dif_and_bitrev` which uses `bit_reversal_permutation`).

Removing `Alloca` from the tag list means Nim's static system analysis won't track stack allocation through these functions. Callers doing resource-constrained analysis (e.g., embedded targets or real-time systems) may incorrectly conclude these functions are stack-safe when they may not be.

**Concern Type:** interface-design

**Suggested Change:** Verify each function individually before removing `Alloca`. If some truly don't use stack allocation, document why. If others still do (through transitive calls), keep the tag.

---

### [ARCHITECTURE] ARCH-B-007: Scratch buffer type-punned via pointer cast relies on fragile sizeof invariant — `constantine/math/matrix/toeplitz.nim`

**Location:** `constantine/math/matrix/toeplitz.nim` (lines 280–295)
**Severity:** Low
**Confidence:** 0.9

**Diff Under Review:**
```nim
  # Invariant: scratchScalars is typed as F but re-interpreted as F.getBigInt() below.
  # This requires sizeof(F) == sizeof(F.getBigInt()), which holds for all production
  # field types (e.g. Fr[BLS12_381] is 32 bytes in both representations).
  static: doAssert sizeof(F) == sizeof(F.getBigInt()), "scratchScalars cast requires sizeof(F) == sizeof(F.getBigInt())"

  let scalars = cast[ptr UncheckedArray[F.getBigInt()]](ctx.scratchScalars)
```

**Issue:** **Pointer type punning between F and F.getBigInt() is a structural fragility**

The `ToeplitzAccumulator.finish` method stores scratch data as `F` (field elements) during `accumulate`, then casts the same buffer to `F.getBigInt()` during `finish` for use as MSM scalars. This works because `sizeof(F) == sizeof(F.getBigInt())` for current field implementations, but:

1. The `static: doAssert` only catches this at instantiation time for the specific generic type, not for all possible field types.
2. If a new field type is added where this invariant doesn't hold, the `static: doAssert` will fire, but the damage is that the accumulator was already `init`-ed and buffers allocated with the wrong size assumption.
3. The dual-purpose buffer (field elements → big integers) is a clever optimization but violates the principle of type safety — the same memory is interpreted as two different types.

**Concern Type:** data-flow

**Suggested Change:** The `static: doAssert` is the right defensive mechanism for Nim generics. Consider adding a comment at the `scratchScalars` field declaration explaining the dual interpretation, so readers understand the type contract.

---

### [ARCHITECTURE] ARCH-B-008: batchAffine (ct) and batchAffine_vartime have inconsistent N≤0 guard semantics — `constantine/math/elliptic/ec_shortweierstrass_batch_ops.nim`

**Location:** `constantine/math/elliptic/ec_shortweierstrass_batch_ops.nim` (lines 29–34 and 185–190)
**Severity:** Low
**Confidence:** 0.8

**Diff Under Review:**
```diff
 func batchAffine*[F, G](
        affs: ptr UncheckedArray[EC_ShortW_Aff[F, G]],
        projs: ptr UncheckedArray[EC_ShortW_Prj[F, G]],
        N: int) {.meter.} =
+  if N <= 0:
+    return

 func batchAffine_vartime*[F, G](
        affs: ptr UncheckedArray[EC_ShortW_Aff[F, G]],
        projs: ptr UncheckedArray[EC_ShortW_Prj[F, G]],
        N: int) {.tags:[VarTime], meter.} =
   if N <= 0:
     return
```

**Issue:** **Defensive guard added only to new vartime variants, not to existing ct variants**

The diff adds `if N <= 0: return` guards to the NEW `batchAffine_vartime` functions and the existing `batchAffine` ct versions for ShortWeierstrass. However, looking at the current code, the ct `batchAffine` for ShortWeierstrass also got the guard added (it was missing before). The TwistedEdwards ct `batchAffine` also got the guard.

But the guard is `N <= 0`, while the Montgomery batch inversion algorithm fundamentally requires `N >= 1` (it accesses index 0 and index N-1). A caller passing `N = 0` with the ct version previously would have crashed with undefined behavior (accessing `affs[0]` and `affs[N-1]` where N=0). The vartime version also had this issue before the fix.

The concern is **consistency**: if this guard was needed for the vartime versions, it was equally needed for the ct versions. The fact that it's being added now means the existing ct code was always calling with potentially-invalid N, relying on caller discipline.

**Concern Type:** module-boundary

**Suggested Change:** Ensure ALL batchAffine variants (ct and vartime, for both curve types) have the same defensive guard. Consider adding `doAssert N > 0` in debug builds for an extra safety net.

---

### [ARCHITECTURE] ARCH-B-009: New transpose module is standalone and clean, but not referenced by any production path — `constantine/math/matrix/transpose.nim`

**Location:** `constantine/math/matrix/transpose.nim` (new file, 79 lines)
**Severity:** Informational
**Confidence:** 1.0

**Issue:** **Production-quality module with no production consumers**

The new `transpose.nim` module provides a cache-optimized 2D blocked matrix transposition with benchmark-validated performance (20 GB/s vs 10 GB/s for naive). However, grepping the codebase reveals no production code references this module — it's only used in benchmarks.

This is not a problem per se (it may be infrastructure for a future optimization), but it means the module:
1. Has no integration tests in the test suite
2. Its public API (`transpose*`) is unexercised in production paths
3. The `{.inline.}` on the proc is a good choice but the actual code path through the inline is never exercised

**Concern Type:** incremental-deliverability

**Suggested Change:** If this is infrastructure for a future change (e.g., optimizing the transpose step in ToeplitzAccumulator), add a TODO or comment linking to the planned integration point. Otherwise, consider if it belongs in the benchmarks directory rather than the core math module.

## Positive Changes

1. **`ToeplitzAccumulator` RAII pattern is well-designed:** The object has `{.error.}` on `=copy` preventing accidental aliasing, `=destroy` properly frees all three pointer fields with nil-checks, and the `init` procedure defensively frees existing allocations. This is a textbook example of resource management in Nim.

2. **`batchAffine_vartime` consistently follows the `batchAffine` API surface:** Both Jacobian and Projective variants exist for ShortWeierstrass, both single-array and 2D-array overloads are provided, and the `VarTime` tag is consistently applied. The export through `lowlevel_elliptic_curves.nim` makes the API discoverable.

3. **`bit_reversal_permutation` aliasing detection is a correctness improvement:** The old API relied on `{.noalias.}` which the compiler might not enforce at runtime. The new dispatcher detects aliasing and handles it correctly, preventing silent data corruption.

4. **`kzg_coset_prove` in-place optimization reduces allocations:** The function now reuses the `u` buffer for both the IFFT input and output (`ec_fft_nn(u, u)`), and frees the `circulant` buffer earlier in the function. This reduces peak memory usage and improves cache locality.

5. **Comprehensive test coverage for vartime batch affine:** The test template `run_EC_affine_conversion` now supports `isVartime` mode, testing single-element, all-neutral, and varied batch sizes — covering edge cases that the ct version didn't exercise.
