---
**Branch:** `master` → `peerdas-perf-fix-rebased2` (commit `81784ecd`)
**Diff file:** `.REVIEWS/RID-202605022113-peerdas-perf-fix-rebased2-81784ecd/RID-202605022113-changes_under_review.diff`
**Date:** 2026-05-02
**Reviewer:** Architecture Analyst (Pass B)
**Scope:** Perf-oriented refactoring of FK20 KZG multiproofs: new `ToeplitzAccumulator`, `batchAffine_vartime` family, aliasing-safe `bit_reversal_permutation`, and polyphase spectrum bank format change (Jacobian → Affine)
**Focus:** Interface design, data flow, dependency direction, module boundaries, incremental deliverability
---

# Architecture Review (Pass B)

## Summary

| ID | Severity | Confidence | File | Issue |
|----|----------|------------|------|-------|
| ARCH-B-001 | Medium | 0.9 | constantine/math/polynomials/fft_common.nim:290-332 | `bit_reversal_permutation` API semantic change: noalias contract removed, aliasing handled implicitly |
| ARCH-B-002 | Medium | 0.9 | constantine/math/matrix/toeplitz.nim:186-211 | New `ToeplitzStatus` error enum wraps `FFTStatus`, creating a redundant error type layer |
| ARCH-B-003 | High | 0.9 | constantine/commitments/kzg_multiproofs.nim:502-564 | `computeAggRandScaledInterpoly` return type changed `bool` → `void`, removing error reporting |
| ARCH-B-004 | Medium | 0.9 | constantine/math/matrix/toeplitz.nim:276-297 | `ToeplitzAccumulator.finish` uses `cast` to reinterpret `F` as `F.getBigInt()`, coupling to field repr |
| ARCH-B-005 | Medium | 0.8 | constantine/math/matrix/toeplitz.nim:186-211 | `ToeplitzAccumulator` lacks `reset()` API; benchmark uses `privateAccess` to mutate internal state |
| ARCH-B-006 | Low | 0.9 | constantine/math/polynomials/fft_ec.nim (12 sites) | `Alloca` system effect tag removed from FFT functions changes public effect annotations |
| ARCH-B-007 | Informational | 0.8 | constantine/commitments_setups/ethereum_kzg_srs.nim:206 | `polyphaseSpectrumBank` stored format changed Jac→Aff, altering SRS memory layout |

**Key takeaways:**
1. The `ToeplitzAccumulator` introduces a new abstraction layer with its own error type (`ToeplitzStatus`), state machine semantics, and memory management — a substantial architectural shift that replaces the flat `toeplitzMatVecMulPreFFT` API.
2. Several public functions have had their error handling contracts weakened: `computeAggRandScaledInterpoly` drops `bool` return for `doAssert`, and `bit_reversal_permutation` changes from explicit noalias contract to implicit aliasing detection.
3. The benchmark workarounds (`privateAccess` to reset `acc.offset`) signal a gap in the `ToeplitzAccumulator` public API that may need addressing.

## Findings

### [ARCHITECTURE] ARCH-B-001: `bit_reversal_permutation` API semantic change removes noalias contract — fft_common.nim:290-332

**Location:** constantine/math/polynomials/fft_common.nim:290-332
**Severity:** Medium
**Confidence:** 0.9

**Diff Under Review:**
```diff
-func bit_reversal_permutation*[T](dst{.noalias.}: var openArray[T], src{.noalias.}: openArray[T]) {.inline.} =
-  ## Out-of-place bit reversal permutation.
+func bit_reversal_permutation_noalias*[T](dst{.noalias.}: var openArray[T], src{.noalias.}: openArray[T]) {.inline.} =
+  ## Out-of-place bit reversal permutation (no aliasing between dst and src).
 
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

**Issue:** **Implicit aliasing detection replaces explicit noalias contract**

The original `bit_reversal_permutation` had `{.noalias.}` contracts on `dst` and `src`, making it the caller's responsibility to guarantee non-overlapping buffers. The new version removes this contract and instead detects aliasing at runtime via pointer comparison (`dst[0].addr == src[0].addr`), allocating a temporary buffer when aliasing is detected.

This changes the function from a **pure, allocation-free** operation (when used correctly under the noalias contract) to a **conditionally-allocating** operation. For callers like `ec_ifft_nn_via_bitrev_and_iterative_dit` at line 369 where `output` and `vals` are known to be different buffers, the old API let callers signal this guarantee. The new API silently adds a runtime check (pointer comparison) that's never false for those callers but still executes.

The `_noalias` variant is provided but is not the default — callers must opt-in to the zero-allocation path, whereas previously zero-allocation was the default and aliasing was undefined.

**Concern Type:** interface-design

**Suggested Change:** Consider keeping `bit_reversal_permutation` as the noalias version (renaming the aliasing-safe version to `bit_reversal_permutation_safe` or similar). This preserves the performance-critical default while still providing safety for callers who need it.

---

### [ARCHITECTURE] ARCH-B-002: `ToeplitzStatus` wraps `FFTStatus`, creating a redundant error type layer — toeplitz.nim:157-211

**Location:** constantine/math/matrix/toeplitz.nim:157-211
**Severity:** Medium
**Confidence:** 0.9

**Diff Under Review:**
```diff
+type
+  ToeplitzStatus* = enum
+    Toeplitz_Success
+    Toeplitz_SizeNotPowerOfTwo
+    Toeplitz_TooManyValues
+    Toeplitz_MismatchedSizes
+
+template check*(Section: untyped, evalExpr: untyped): untyped {.dirty.} =
+  block:
+    let status = evalExpr
+    when status is ToeplitzStatus:
+      if status != Toeplitz_Success:
+        result = status
+        break Section
+    elif status is FFTStatus:
+      if status != FFT_Success:
+        result = case status
+          of FFT_SizeNotPowerOfTwo: Toeplitz_SizeNotPowerOfTwo
+          of FFT_TooManyValues: Toeplitz_TooManyValues
+          of else: Toeplitz_MismatchedSizes
```

**Issue:** **Redundant error type abstraction with mechanical mapping**

`ToeplitzStatus` is a new enum that wraps `FFTStatus` with a 1:1 mapping for three values (`SizeNotPowerOfTwo`, `TooManyValues`) and a catch-all for the rest. The `check` template handles this mapping automatically, converting `FFTStatus` results into `ToeplitzStatus` on the fly.

This creates an unnecessary abstraction layer: the Toeplitz module already depends on FFT infrastructure, and the error conditions it can encounter are ultimately FFT errors plus one additional case (`MismatchedSizes`). By introducing `ToeplitzStatus`, callers must handle a second error enum that doesn't add new semantic information — it merely relabels FFT errors.

This has downstream impact: `toeplitzMatVecMul` now returns `ToeplitzStatus` instead of `FFTStatus`, requiring all callers to adapt their error handling. Tests at `t_toeplitz.nim` now check `Toeplitz_Success` instead of `FFT_Success`.

**Concern Type:** dependency-direction

**Suggested Change:** Consider returning `FFTStatus` directly for errors that originate from FFT operations, and either (a) extend `FFTStatus` with `MismatchedSizes`, or (b) use a result tuple `(FFTStatus, bool)` to distinguish Toeplitz-specific errors. This avoids the mechanical mapping layer.

---

### [ARCHITECTURE] ARCH-B-003: `computeAggRandScaledInterpoly` drops `bool` return, removing error reporting capability — kzg_multiproofs.nim:502-564

**Location:** constantine/constantine/commitments/kzg_multiproofs.nim:502-564
**Severity:** High
**Confidence:** 0.9

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
 
-  if evals.len != evalsCols.len or linearIndepRandNumbers.len < evalsCols.len:
-    return false
+  doAssert evals.len == evalsCols.len, "Internal error: evals and evalsCols must have same length"
+  doAssert linearIndepRandNumbers.len >= evalsCols.len, "Internal error: linearIndepRandNumbers must cover all evals"
 
   for k in 0 ..< evalsCols.len:
     let c = evalsCols[k]
-    if c < 0 or c >= NumCols:
-      return false
+    doAssert c >= 0 and c < NumCols, "Internal error: Column index out of bounds: " & $c
 
   # ...
-  return true
```

**Issue:** **Public function loses error reporting, converting recoverable errors to assertion failures**

The function `computeAggRandScaledInterpoly` is an internal helper (not exported with `*`), but it is called from `kzg_coset_verify_batch` which IS exported. The previous design allowed the caller to distinguish between "input validation failed" (return `false`) and "computation succeeded" (return `true`), enabling the verifying code to return `false` gracefully.

The new design replaces three `return false` paths with `doAssert` statements. In release builds, `doAssert` is a no-op, meaning **invalid inputs will silently produce garbage output** instead of failing gracefully. In debug builds, the program will crash/abort.

This is a significant reliability regression: the verification path `kzg_coset_verify_batch` no longer has a way to detect input validation failures. If malformed inputs reach this code, the behavior is undefined (in release) rather than returning `false`.

**Concern Type:** interface-design

**Suggested Change:** Keep the `bool` return type for `computeAggRandScaledInterpoly`, or use `result` with a default of `true` and only set it `false` on validation failure. At minimum, the `kzg_coset_verify_batch` caller should have a way to detect invalid inputs without crashing.

---

### [ARCHITECTURE] ARCH-B-004: `ToeplitzAccumulator.finish` reinterprets `F` as `F.getBigInt()` via `cast` — toeplitz.nim:276-297

**Location:** constantine/math/matrix/toeplitz.nim:276-297
**Severity:** Medium
**Confidence:** 0.9

**Diff Under Review:**
```diff
 proc finish*[EC, ECaff, F](
   ctx: var ToeplitzAccumulator[EC, ECaff, F],
   output: var openArray[EC]
 ): ToeplitzStatus {.raises: [], meter.} =
   ## MSM per position, then IFFT
   let n = ctx.size
   # Invariant: scratchScalars is typed as F but re-interpreted as F.getBigInt() below.
   # This requires sizeof(F) == sizeof(F.getBigInt()), which holds for all production
   # field types (e.g. Fr[BLS12_381] is 32 bytes in both representations).
   static: doAssert sizeof(F) == sizeof(F.getBigInt()), "scratchScalars cast requires sizeof(F) == sizeof(F.getBigInt())"
 
   let scalars = cast[ptr UncheckedArray[F.getBigInt()]](ctx.scratchScalars)
 
   for i in 0 ..< n:
     for offset in 0 ..< ctx.L:
       scalars[offset].fromField(ctx.coeffs[i * ctx.L + offset])
```

**Issue:** **Memory reinterpretation couples module to field internal representation invariant**

The `ToeplitzAccumulator` allocates `scratchScalars` as `ptr UncheckedArray[F]` (size `max(size, L)`), then in `finish()` casts it to `ptr UncheckedArray[F.getBigInt()]`. This type pun is guarded by a `static: doAssert sizeof(F) == sizeof(F.getBigInt())` check.

While the assertion is correct for current production types, this pattern:
1. Couples the Toeplitz module to the internal representation size of field elements
2. Makes the buffer allocation type (`F`) semantically inconsistent with its use type (`F.getBigInt()`)
3. The `fromField` call on line 293 converts the field element, but the scratch buffer was typed as `F`, not `BigInt` — this is only safe because of the size equality invariant

This is an optimization trade-off (avoiding a second allocation for `BigInt` buffers) that works but creates a hidden dependency on the field representation.

**Concern Type:** module-boundary

**Suggested Change:** Either (a) declare `scratchScalars` as the actual use type `ptr UncheckedArray[F.getBigInt()]` with a separate `scratchF` for FFT temp storage, or (b) document this invariant in the `ToeplitzAccumulator` type documentation and consider a named constraint like `when sizeof(F) == sizeof(F.getBigInt())` on the `finish` proc.

---

### [ARCHITECTURE] ARCH-B-005: `ToeplitzAccumulator` lacks `reset()` API; benchmark uses `privateAccess` — toeplitz.nim:186-211, bench_matrix_toeplitz.nim:170-171

**Location:** constantine/math/matrix/toeplitz.nim:186-211; benchmarks/bench_matrix_toeplitz.nim:170-181
**Severity:** Medium
**Confidence:** 0.8

**Diff Under Review:**
```diff
 # benchmarks/bench_matrix_toeplitz.nim
+  # Allow direct access to private 'offset' field for benchmark reuse
+  privateAccess(toeplitz.ToeplitzAccumulator)
+
+  bench("ToeplitzAccumulator_64accumulates", size, iters):
+    # Reset accumulator state for this iteration (avoids free+alloc)
+    acc.offset = 0
```

**Issue:** **State machine lacks public reset mechanism, forcing encapsulation breach in benchmarks**

The `ToeplitzAccumulator` follows an init→accumulate×L→finish lifecycle. Once `finish` is called, the accumulator is consumed. To reuse it in a benchmark loop without reallocating (which the comment correctly identifies as ~772 KB), the benchmark uses `privateAccess` to directly set `acc.offset = 0`.

This is a legitimate pattern for high-performance code (avoiding allocation in hot loops), but the current API design forces an encapsulation breach. A proper `reset()` method would:
1. Set `offset = 0` 
2. Optionally zero out internal buffers (or leave them for reuse)
3. Be a documented, supported public API

**Concern Type:** interface-design

**Suggested Change:** Add a `proc reset*(ctx: var ToeplitzAccumulator[EC, ECaff, F])` method that sets `ctx.offset = 0` and documents the reuse pattern. This eliminates the need for `privateAccess` in benchmarks and tests.

---

### [ARCHITECTURE] ARCH-B-006: `Alloca` system effect tag removed from FFT functions changes public effect annotations — fft_ec.nim (12 sites)

**Location:** constantine/math/polynomials/fft_ec.nim (multiple functions, e.g. lines 67, 93, 108, 134, etc.)
**Severity:** Low
**Confidence:** 0.9

**Diff Under Review:**
```diff
- func ec_fft_nn_impl_recursive[EC; bits: static int](
+ func ec_fft_nn_impl_recursive[EC; bits: static int](
-        rootsOfUnity: StridedView[BigInt[bits]]) {.tags: [VarTime, Alloca].} =
+        rootsOfUnity: StridedView[BigInt[bits]]) {.tags: [VarTime].} =

- func ec_fft_nn_recursive[EC](
+ func ec_fft_nn_recursive[EC](
-       vals: openarray[EC]): FFTStatus {.tags: [VarTime, Alloca], meter.} =
+       vals: openarray[EC]): FFTStatus {.tags: [VarTime], meter.} =

# ... and 10 more similar sites
```

**Issue:** **System effect annotations no longer reflect stack allocation behavior**

The `{.tags: [Alloca].}` annotation indicates that a function may perform stack (alloca) allocation. This was present on 12+ FFT-related functions and has been removed uniformly. Looking at the code, these functions still use `allocStackArray` internally (e.g., in `ec_fft_nn_impl_recursive` for temporary buffer allocation).

Removing `Alloca` from the tags is a lie about the function's effects: the compiler's effect system will no longer track that these functions may use stack allocation. This could affect callers who are sensitive to stack usage (e.g., deeply recursive callers in constrained environments).

**Concern Type:** interface-design

**Suggested Change:** Either (a) keep `Alloca` in the tags if stack allocation still occurs, or (b) document why it was removed (perhaps the recursive implementations were replaced with iterative ones that don't use alloca).

---

### [ARCHITECTURE] ARCH-B-007: `polyphaseSpectrumBank` stored format changed from Jacobian to Affine — ethereum_kzg_srs.nim:206

**Location:** constantine/commitments_setups/ethereum_kzg_srs.nim:206
**Severity:** Informational
**Confidence:** 0.8

**Diff Under Review:**
```diff
-    polyphaseSpectrumBank*{.align: 64.}: array[FIELD_ELEMENTS_PER_CELL, array[CELLS_PER_EXT_BLOB, EC_ShortW_Jac[Fp[BLS12_381], G1]]]
-    # Precomputed polyphase decomposition of the SRS in the Fourier domain.
+    polyphaseSpectrumBank*{.align: 64.}: array[FIELD_ELEMENTS_PER_CELL, array[CELLS_PER_EXT_BLOB, EC_ShortW_Aff[Fp[BLS12_381], G1]]]
+    # Precomputed polyphase decomposition of the SRS in the Fourier domain (affine form).
-    # Size: L × CDS = 64 × 128 = 8192 EC points in Jacobian form
+    # Size: L × CDS = 64 × 128 = 8192 EC points in affine form
```

**Issue:** **SRS context memory layout changes from Jacobian to Affine representation**

The `polyphaseSpectrumBank` in `EthereumKZGContext` stores precomputed Fourier transforms of the polyphase decomposition. This changes from Jacobian (projective, 3 coordinates per point) to Affine (2 coordinates per point) representation.

This is an intentional optimization: the FFT output in `computePolyphaseDecompositionFourier` now computes in Jacobian (for the FFT), then batch-converts to affine once for all L×CDS points, saving storage. The affine form is what the `ToeplitzAccumulator.accumulate` method expects.

Memory savings: Jacobian points use 3 field elements (96 bytes each for BLS12-381), Affine use 2 (64 bytes each). For 8192 points: 786 KB → 524 KB, a ~33% reduction.

**Concern Type:** data-flow

**Suggested Change:** No change needed. This is a clean, well-documented optimization. However, any code that persists or serializes the `EthereumKZGContext` (e.g., to disk or over the network) would need to be updated to handle the new format.

---

## Positive Changes

1. **`ToeplitzAccumulator` state machine pattern**: Replacing the flat `toeplitzMatVecMulPreFFT(accumulate=...)` call with a proper accumulator (init→accumulate→finish) is architecturally cleaner. It eliminates per-iteration heap allocations (coeffsFft, coeffsFftBig, product, convolutionResult) by pre-allocating transposed buffers during init. The `=copy {.error.}` and `=destroy` implementations follow the library's ownership conventions well.

2. **`batchAffine_vartime` family**: Adding variable-time variants alongside the constant-time `batchAffine` follows the established pattern of providing both security profiles (e.g., `scalarMul_vartime` alongside constant-time variants). The implementations correctly handle infinity points (z=0) with secret-word zero tracking, and the `N <= 0` early return is a sensible edge case guard.

3. **In-place FFT optimization**: The diff eliminates several unnecessary intermediate buffers across the FFT pipeline (e.g., `kzg_coset_prove` reuses `u` buffer for FFT, `computePolyphaseDecompositionFourierOffset` writes directly to output). This reduces peak memory usage and allocation count without changing the algorithmic complexity.

4. **Comprehensive test coverage for new code**: Tests for `ToeplitzAccumulator` error paths (init with invalid sizes, finish before accumulate), `batchAffine_vartime` across multiple curve/field combinations (BN254, BLS12-381, Bandersnatch, Banderwagon), and edge cases (single element, all neutral, varied batch sizes) provide good confidence in the new implementations.

5. **`ToeplitzAccumulator` scratch buffer design**: The single `scratchScalars` buffer of size `max(size, L)` is reused across FFT computation (accumulate) and scalar conversion (finish), demonstrating careful buffer management in a performance-critical path.

## Constraints

- Report written to: `.REVIEWS/RID-202605022113-peerdas-perf-fix-rebased2-81784ecd/RID-202605022113-architecture-B.md`
- Read-only review: No source code files modified.
- All findings reference actual code in the diff file with specific line numbers and file paths.
