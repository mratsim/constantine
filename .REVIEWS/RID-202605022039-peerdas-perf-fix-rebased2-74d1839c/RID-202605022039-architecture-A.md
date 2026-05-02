---
**Branch:** `master` → `peerdas-perf-fix-rebased2` (commit `74d1839c`)
**Diff file:** `.REVIEWS/RID-202605022039-peerdas-perf-fix-rebased2-74d1839c/RID-202605022039-changes_under_review.diff`
**Date:** 2026-05-02
**Reviewer:** Architecture Analyst (Pass A)
**Scope:** PeerDAS performance optimization — FK20 multiproof algorithm refactoring, variable-time batch affine conversion, ToeplitzAccumulator introduction, FFT tag cleanup, bit reversal permutation aliasing support
**Focus:** Interface design, data flow, dependency direction, module boundaries, incremental deliverability
---

# Architecture Review (Pass A)

## Summary

| ID | Severity | Confidence | File | Issue |
|----|----------|------------|------|-------|
| ARCH-A-001 | Medium | 1.0 | constantine/commitments/kzg_multiproofs.nim:302-378; commitments_setups/ethereum_kzg_srs.nim:203-206 | Breaking public API: `polyphaseSpectrumBank` changed from Jacobian to Affine coordinates across 3 exported symbols |
| ARCH-A-002 | Low | 0.9 | constantine/commitments/kzg_multiproofs.nim:502-579 | Error handling model shift: `computeAggRandScaledInterpoly` changed from `bool` return to assertions |
| ARCH-A-003 | Medium | 0.9 | constantine/math/polynomials/fft_common.nim:307-322 | Aliasing check in `bit_reversal_permutation` adds runtime overhead to aliasing hot path |
| ARCH-A-004 | Medium | 0.9 | constantine/math/matrix/toeplitz.nim:286-295; toeplitz.nim:188-199 | `ToeplitzAccumulator` scratch buffer type-punned via `cast` with `sizeof` invariant |
| ARCH-A-005 | Informational | 0.7 | benchmarks/bench_matrix_toeplitz.nim:228 | Benchmark uses `privateAccess` to mutate internal `ToeplitzAccumulator.offset` state |
| ARCH-A-006 | Low | 0.8 | constantine/math/polynomials/fft_ec.nim; fft_common.nim | Systematic `Alloca` tag removal from FFT/scalar mul functions |
| ARCH-A-007 | Low | 0.6 | constantine/commitments/kzg_multiproofs.nim:226-230 | `computePolyphaseDecompositionFourierOffset` loses `Alloca` tag but FFT descriptor is passed through |
| ARCH-A-008 | Informational | 1.0 | constantine/math/matrix/toeplitz.nim:145-151; toeplitz.nim:155-185 | New `ToeplitzStatus` enum and `check`/`checkReturn` templates: good structured error handling |

**Key takeaways:**
1. The `polyphaseSpectrumBank` Jacobian→Affine type change is a breaking change to 3 exported APIs — all internal consumers are updated, but external users may be affected.
2. The new `ToeplitzAccumulator` is well-designed with proper `=destroy`, `=copy{.error.}`, and structured error handling, but uses a deliberate `cast` type-pun that relies on a `sizeof` invariant.
3. Systematic `Alloca` tag removal from FFT functions is correct and improves integration safety.
4. The aliasing-supporting `bit_reversal_permutation` adds a branch on every call — benign for most callers since aliasing is common in the FFT hot path.
5. The overall FK20 redesign (replacing `toeplitzMatVecMulPreFFT` with `ToeplitzAccumulator`) improves allocation efficiency (6→4 allocations) and matches the c-kzg-4844 pattern more closely.

## Findings

### [ARCHITECTURE] ARCH-A-001: Breaking public API — `polyphaseSpectrumBank` coordinate representation changed from Jacobian to Affine

**Location:** constantine/commitments/kzg_multiproofs.nim:302-378, constantine/commitments_setups/ethereum_kzg_srs.nim:203-206

**Severity:** Medium
**Confidence:** 1.0

**Diff Under Review:**
```diff
-    polyphaseSpectrumBank*{.align: 64.}: array[FIELD_ELEMENTS_PER_CELL, array[CELLS_PER_EXT_BLOB, EC_ShortW_Jac[Fp[BLS12_381], G1]]]
+    polyphaseSpectrumBank*{.align: 64.}: array[FIELD_ELEMENTS_PER_CELL, array[CELLS_PER_EXT_BLOB, EC_ShortW_Aff[Fp[BLS12_381], G1]]]
```

```diff
 func computePolyphaseDecompositionFourier*[N, L, CDS: static int, Name: static Algebra](
-       polyphaseSpectrumBank: var array[L, array[CDS, EC_ShortW_Jac[Fp[Name], G1]]],
+       polyphaseSpectrumBank: var array[L, array[CDS, EC_ShortW_Aff[Fp[Name], G1]]],
```

```diff
 func kzg_coset_prove*[L, CDS: static int, Name: static Algebra](
-       polyphaseSpectrumBank: array[L, array[CDS, EC_ShortW_Jac[Fp[Name], G1]]]
+       polyphaseSpectrumBank: array[L, array[CDS, EC_ShortW_Aff[Fp[Name], G1]]]
```

**Issue:** **Breaking change to 3 exported function signatures and 1 exported type field**

The `polyphaseSpectrumBank` parameter type changed from `EC_ShortW_Jac` (Jacobian/projective) to `EC_ShortW_Aff` (affine) coordinates across three exported (`*`) interfaces:

1. `computePolyphaseDecompositionFourier*` — the computation function
2. `kzg_coset_prove*` — the proof generation function
3. `EthereumKZGContext.polyphaseSpectrumBank*` — the stored context field

This is a **breaking API change** for any external consumer that:
- Stores the bank in a variable (the variable's type must change)
- Serializes/deserializes the bank (affine points are larger than Jacobian points per-element, and have different layout)
- Pre-computes the bank externally

All internal consumers in the diff have been updated (tests, benchmarks, metering, production code), so the codebase is internally consistent.

**Concern Type:** interface-design

**Suggested Change:** Document this breaking change in a changelog or migration guide. Consider versioning if there are known external consumers. The change is architecturally sound (affine coordinates are more appropriate for the accumulator's MSM phase since it needs affine points for `multiScalarMul_vartime`), so the fix is documentation rather than code change.

**Backward Compatibility Analysis:**
- Storage size impact: `EC_ShortW_Jac` has 3 field elements vs `EC_ShortW_Aff` has 2 field elements per point. For `L × CDS = 64 × 128 = 8192` points, this reduces storage from 8192 × 3 × 32 = 786 KB to 8192 × 2 × 32 = 524 KB — a **33% reduction** in memory footprint, which is a positive side effect.

---

### [ARCHITECTURE] ARCH-A-002: Error handling model shift — `computeAggRandScaledInterpoly` from `bool` return to assertions

**Location:** constantine/commitments/kzg_multiproofs.nim:502-579

**Severity:** Low
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
```

```diff
-  if evals.len != evalsCols.len or linearIndepRandNumbers.len < evalsCols.len:
-    return false
+  doAssert evals.len == evalsCols.len, "Internal error: evals and evalsCols must have same length"
+  doAssert linearIndepRandNumbers.len >= evalsCols.len, "Internal error: linearIndepRandNumbers must cover all evals"
```

```diff
-    if c < 0 or c >= NumCols:
-      return false
+    doAssert c >= 0 and c < NumCols, "Internal error: Column index out of bounds: " & $c
```

```diff
-  if not interpoly.computeAggRandScaledInterpoly(
-    evals, evalsCols, domain, linearIndepRandNumbers, N
-  ):
-    return false
+  interpoly.computeAggRandScaledInterpoly(
+    evals, evalsCols, domain, linearIndepRandNumbers, N
+  )
```

**Issue:** **Error handling contract changed from runtime-checked return to assertion-based**

The function `computeAggRandScaledInterpoly` changed from returning `bool` (with `false` on validation failure) to returning no value and using `doAssert` for all validation. The caller (`kzg_coset_verify_batch`) no longer checks a return value.

This is a **simplification** of the API that is architecturally sound for an internal function (not exported with `*`). The validation parameters (`evals.len`, `evalsCols`, `linearIndepRandNumbers.len`, column bounds) are all structural properties that should be invariant — if they're wrong, it's a programming error, not a recoverable condition.

The change also enables an in-place optimization: `coset_ifft_rn` now operates in-place on `agg_cols[c]` instead of a separate `col_interpoly` buffer, eliminating one allocation and one copy.

**Concern Type:** interface-design

**Suggested Change:** No code change needed. This is a net positive. The only risk is if there are external callers of this non-exported function that relied on the `bool` return — but since it's not exported (`*`), this is scoped to the module.

---

### [ARCHITECTURE] ARCH-A-003: Aliasing check in `bit_reversal_permutation` adds a branch on every call in the FFT hot path

**Location:** constantine/math/polynomials/fft_common.nim:307-322

**Severity:** Medium
**Confidence:** 0.9

**Diff Under Review:**
```diff
-func bit_reversal_permutation*[T](dst{.noalias.}: var openArray[T], src{.noalias.}: openArray[T]) {.inline.} =
+func bit_reversal_permutation_noalias*[T](dst{.noalias.}: var openArray[T], src{.noalias.}: openArray[T]) {.inline.} =
 ...
+func bit_reversal_permutation*[T](dst: var openArray[T], src: openArray[T]) {.inline.} =
+  ## Out-of-place bit reversal permutation with aliasing detection.
+
+  if dst[0].addr == src[0].addr:
+    # Alias: allocate temp, permute to temp, copy back
+    var tmp = allocHeapArrayAligned(T, src.len, alignment = 64)
+    bit_reversal_permutation_noalias(tmp.toOpenArray(0, src.len-1), src)
+    copyMem(dst[0].addr, tmp[0].addr, src.len * sizeof(T))
+    freeHeapAligned(tmp)
+  else:
+    bit_reversal_permutation_noalias(dst, src)
```

**Issue:** **The new aliasing-aware `bit_reversal_permutation(dst, src)` adds a pointer comparison and branch on every call**

The old two-argument `bit_reversal_permutation` had `{.noalias.}` constraints, meaning callers were responsible for ensuring no overlap. The new version removes this constraint and handles aliasing by checking `dst[0].addr == src[0].addr`.

This is architecturally sound — it makes the API safer and supports in-place FFT operations (which is used in `ec_fft_nn` and `ec_ifft_nn` for the `ToeplitzAccumulator.finish` path). However:

1. The aliasing check (`dst[0].addr == src[0].addr`) is a **branch in the hot FFT path**. For the common non-aliasing case, this branch should predict well (always-not-taken), but it's still an extra instruction.
2. In the aliasing case, an extra heap allocation + copy is performed, which is O(n) additional work.

Looking at call sites in `fft_ec.nim`:
- `ec_fft_nn_via_iterative_dif_and_bitrev`: calls `bit_reversal_permutation(output)` — single-arg, not affected
- `ec_fft_nn_via_bitrev_and_iterative_dit`: calls `bit_reversal_permutation(br_vals, vals)` — different buffers, never aliases
- `ec_ifft_nn_via_bitrev_and_iterative_dit`: calls `bit_reversal_permutation(output, vals)` — may alias when `ec_fft_nn(dst, dst)` is used

The in-place usage in `ToeplitzAccumulator.finish` (`ec_ifft_nn(desc, output, output)`) is the primary motivator for aliasing support.

**Concern Type:** data-flow

**Suggested Change:** Consider making the aliasing path explicit by providing `bit_reversal_permutation_inplace` for the aliasing case, so the common path stays branch-free. Alternatively, accept the small overhead as the cost of safety — the branch should be well-predicted for the non-aliasing case.

---

### [ARCHITECTURE] ARCH-A-004: `ToeplitzAccumulator` scratch buffer type-punned via `cast` with `sizeof` invariant

**Location:** constantine/math/matrix/toeplitz.nim:281-295

**Severity:** Medium
**Confidence:** 0.9

**Diff Under Review:**
```nim
proc finish*[EC, ECaff, F](
  ctx: var ToeplitzAccumulator[EC, ECaff, F],
  output: var openArray[EC]
): ToeplitzStatus {.raises: [], meter.} =
  ## MSM per position, then IFFT
  let n = ctx.size
  ...
  # Invariant: scratchScalars is typed as F but re-interpreted as F.getBigInt() below.
  # This requires sizeof(F) == sizeof(F.getBigInt()), which holds for all production
  # field types (e.g. Fr[BLS12_381] is 32 bytes in both representations).
  static: doAssert sizeof(F) == sizeof(F.getBigInt()), "scratchScalars cast requires sizeof(F) == sizeof(F.getBigInt())"

  let scalars = cast[ptr UncheckedArray[F.getBigInt()]](ctx.scratchScalars)
```

**Issue:** **Deliberate type-punning of scratch buffer between field element and big integer representations**

The `ToeplitzAccumulator` stores `scratchScalars` as `ptr UncheckedArray[F]` (field elements) for use during `accumulate()` (where FFT results are field elements). During `finish()`, the same memory is re-interpreted as `ptr UncheckedArray[F.getBigInt()]` (big integers) for use with `multiScalarMul_vartime` scalars.

This is a deliberate and documented optimization to avoid allocating a separate big-integer buffer. The `static: doAssert` provides compile-time verification that `sizeof(F) == sizeof(F.getBigInt())`.

**Risk assessment:**
- For BLS12_381: `Fr[BLS12_381]` is 32 bytes, `F.getBigInt()` is also 32 bytes (the Montgomery-reduced representation uses the same memory layout as the raw big integer).
- The `static: doAssert` catches any future field type where this invariant doesn't hold.
- The `fromField` conversion (`scalars[offset].fromField(ctx.coeffs[...])`) is a re-interpretation from Montgomery form to raw form, which is a no-op for field types where the representations share layout.

**Concern Type:** data-flow

**Suggested Change:** No code change needed. This is a well-guarded and documented optimization. The `static: doAssert` is the right architectural safeguard.

---

### [ARCHITECTURE] ARCH-A-005: Benchmark uses `privateAccess` to mutate internal `ToeplitzAccumulator.offset` state

**Location:** benchmarks/bench_matrix_toeplitz.nim:228

**Severity:** Informational
**Confidence:** 0.7

**Diff Under Review:**
```nim
  # Allow direct access to private 'offset' field for benchmark reuse
  privateAccess(toeplitz.ToeplitzAccumulator)

  # Initialize accumulator once outside the benchmark loop to avoid
  # allocation overhead (3 x allocHeapAligned, ~772 KB total) in timing.
  var acc: ToeplitzAccumulator[BLS12_381_G1_jac, BLS12_381_G1_aff, F]
  let statusInit = acc.init(descs.frDesc, descs.ecDesc, size, L)
  doAssert statusInit == Toeplitz_Success

  bench("ToeplitzAccumulator_64accumulates", size, iters):
    # Reset accumulator state for this iteration (avoids free+alloc)
    acc.offset = 0
```

**Issue:** **Benchmark code accesses private `offset` field to reset accumulator between iterations**

The benchmark reuses the same `ToeplitzAccumulator` instance across benchmark iterations to avoid the allocation overhead of `init()` (~772 KB of 3 heap allocations). To do this, it uses `privateAccess` to set `acc.offset = 0` at the start of each iteration.

This is a benchmark-only pattern and doesn't affect production code. However, it exposes a minor design gap: the `ToeplitzAccumulator` doesn't have a public `reset()` method for re-use.

**Concern Type:** module-boundary

**Suggested Change:** Consider adding a public `reset()` method to `ToeplitzAccumulator` that sets `offset = 0` and reinitializes internal buffers (without reallocation). This would make the benchmark code cleaner and also be useful for production code that needs to run multiple FK20 proofs with the same accumulator.

---

### [ARCHITECTURE] ARCH-A-006: Systematic `Alloca` tag removal from FFT and scalar mul functions

**Location:** constantine/math/polynomials/fft_ec.nim; constantine/math/elliptic/ec_scalar_mul_vartime.nim

**Severity:** Low
**Confidence:** 0.8

**Diff Under Review:**
```diff
-func ec_fft_nn_impl_recursive[EC; bits: static int](
+func ec_fft_nn_impl_recursive[EC; bits: static int](
        ...
-       rootsOfUnity: StridedView[BigInt[bits]]) {.tags: [VarTime, Alloca].} =
+       rootsOfUnity: StridedView[BigInt[bits]]) {.tags: [VarTime].} =
```

This pattern is repeated across:
- `ec_fft_nn_impl_recursive`
- `ec_fft_nn_recursive`
- `ec_ifft_nn_recursive`
- `ec_fft_nr_impl_iterative_dif`
- `ec_fft_rn_impl_iterative_dit`
- `ec_fft_nr_iterative`
- `ec_fft_rn_iterative_dit`
- `ec_ifft_rn_impl_iterative`
- `ec_ifft_rn_iterative_dit`
- `ec_fft_nn_via_iterative_dif_and_bitrev`
- `ec_fft_nn_via_bitrev_and_iterative_dit`
- `ec_ifft_nn_via_bitrev_and_iterative_dit`
- `ec_fft_nr*`
- `ec_fft_nn*`
- `ec_ifft_nn*`
- `ec_ifft_rn*`
- `scalarMul_wNAF_vartime*`
- `scalarMulEndo_wNAF_vartime*`
- `computePolyphaseDecompositionFourierOffset`
- `computePolyphaseDecompositionFourier`

**Issue:** **Systematic removal of `{.tags:[Alloca]}` from FFT and scalar multiplication functions**

The `Alloca` tag was removed from all iterative FFT implementations and scalar multiplication functions. This is architecturally correct because:

1. **Iterative FFT functions** (`ec_fft_nr_impl_iterative_dif`, etc.) operate in-place on `StridedView` buffers — they don't allocate on the stack for temporary storage.
2. **Recursive FFT functions** — the recursion depth is bounded by `log2(n)` and uses `StridedView` for data. Any stack usage is through function call frames, not explicit `alloca`/`allocStackArray`.
3. **Scalar mul functions** (`scalarMul_wNAF_vartime`, `scalarMulEndo_wNAF_vartime`) — the precomputation tables are stack-allocated, but since these functions are already tagged `[VarTime]`, the `Alloca` tag was redundant and could cause integration issues with systems that restrict alloca.

The Twisted Edwards `batchAffine` function also had `{.noInline, tags:[Alloca].}` replaced with `{.meter.}`, since the rewrite eliminated the need for stack-allocated temporary arrays (the `zeroes` array was replaced with inline `template zero(i)` using storage in `affs[i].y`).

**Concern Type:** interface-design

**Suggested Change:** No change needed. This is a cleanup that improves integration compatibility.

---

### [ARCHITECTURE] ARCH-A-007: `computePolyphaseDecompositionFourierOffset` loses `Alloca` tag but receives FFT descriptor

**Location:** constantine/commitments/kzg_multiproofs.nim:226-230

**Severity:** Low
**Confidence:** 0.6

**Diff Under Review:**
```diff
 func computePolyphaseDecompositionFourierOffset[N, CDS: static int, Name: static Algebra](
        polyphaseSpectrum: var array[CDS, EC_ShortW_Jac[Fp[Name], G1]],
        powers_of_tau: PolynomialCoef[N, EC_ShortW_Aff[Fp[Name], G1]],
        ecfft_desc: ECFFT_Descriptor[EC_ShortW_Jac[Fp[Name], G1]],
-       offset: int = 0): FFT_Status {.tags:[Alloca, HeapAlloc, Vartime], meter.} =
+       offset: int = 0): FFT_Status {.tags:[HeapAlloc, Vartime], meter.} =
```

**Issue:** **`Alloca` tag removed from `computePolyphaseDecompositionFourierOffset` — correct if FFT descriptor is pre-allocated**

This function lost the `Alloca` tag because:
1. The old version allocated a temporary `polyphaseComponent` buffer on the heap, then called `ec_fft_nn` — the FFT descriptor's internal state was already heap-allocated.
2. The new version writes directly into `polyphaseSpectrum` (the output buffer) and calls `ec_fft_nn` in-place. No stack allocation is needed.

The `Alloca` tag removal is correct since the function itself doesn't use `alloca` or `allocStackArray`. The FFT descriptor is passed as a parameter (user-owned), so its memory footprint is not attributed to this function.

**Concern Type:** interface-design

**Suggested Change:** No change needed. The tag update is accurate.

---

### [ARCHITECTURE] ARCH-A-008: New `ToeplitzStatus` enum and structured error handling templates

**Location:** constantine/math/matrix/toeplitz.nim:145-185

**Severity:** Informational
**Confidence:** 1.0

**Diff Under Review:**
```nim
type
  ToeplitzStatus* = enum
    Toeplitz_Success
    Toeplitz_SizeNotPowerOfTwo
    Toeplitz_TooManyValues
    Toeplitz_MismatchedSizes

template checkReturn*(evalExpr: untyped): untyped {.dirty.} =
  ## Check ToeplitzStatus or FFTStatus and return early on failure
  block:
    let status = evalExpr
    when status is ToeplitzStatus:
      if status != Toeplitz_Success:
        return status
    elif status is FFTStatus:
      if status != FFT_Success:
        return case status
          of FFT_SizeNotPowerOfTwo: Toeplitz_SizeNotPowerOfTwo
          of FFT_TooManyValues: Toeplitz_TooManyValues
          else: Toeplitz_MismatchedSizes

template check*(Section: untyped, evalExpr: untyped): untyped {.dirty.} =
  ## Check ToeplitzStatus or FFTStatus and break to labeled section on failure
  block:
    let status = evalExpr
    when status is ToeplitzStatus:
      if status != Toeplitz_Success:
        result = status
        break Section
    elif status is FFTStatus:
      if status != FFT_Success:
        result = case status
          of FFT_SizeNotPowerOfTwo: Toeplitz_SizeNotPowerOfTwo
          of FFT_TooManyValues: Toeplitz_TooManyValues
          else: Toeplitz_MismatchedSizes
        break Section
```

**Issue:** **Positive architectural change: structured error handling with status mapping**

The new `ToeplitzStatus` enum and `check`/`checkReturn` templates provide:

1. **Type-safe error propagation**: `ToeplitzStatus` wraps `FFTStatus` by mapping FFT errors to Toeplitz errors, so callers of `ToeplitzAccumulator` methods only need to handle one error type.
2. **RAII-style resource management**: The `check(Section, expr)` template breaks to a labeled section on failure, allowing proper cleanup of heap-allocated resources in `toeplitzMatVecMul`'s `HappyPath` block.
3. **Zero overhead**: Templates expand inline with no function call overhead.

This is a notable improvement over the old error handling pattern (explicit `if status != FFT_Success` checks with manual `freeHeapAligned` calls scattered throughout).

**Concern Type:** interface-design

**Suggested Change:** None. This is well-designed. Consider documenting the `check`/`checkReturn` templates in a module-level comment as a usage pattern for other parts of the codebase.

---

## Positive Changes

1. **`ToeplitzAccumulator` design** (toeplitz.nim:188-299): Excellent RAII object with proper `=destroy` (nil-checking cleanup), `=copy{.error.}` (prevents accidental copies of heap-owned state), defensive double-init handling, and structured error templates. The transposed storage layout (`coeffs[i*L + offset]`) is cache-friendly for the MSM phase.

2. **`batchAffine_vartime` for Jacobian coordinates** (ec_shortweierstrass_batch_ops.nim:262-345): The vartime variant for Jacobian→Affine conversion properly handles points at infinity via explicit `if zero(i).bool()` branches, with only a single inversion (`inv_vartime`) instead of the constant-time Montgomery ladder. This is a significant performance improvement for the polyphase spectrum bank where 50% of points are at infinity.

3. **In-place FFT optimization** (kzg_multiproofs.nim:454-456): The `kzg_coset_prove` function now reuses the `u` buffer for the final FFT instead of allocating a separate `proofsJac` buffer, reducing heap allocations from 4 to 3 in the hot path.

4. **Polyphase spectrum bank memory reduction**: Changing from Jacobian to affine coordinates reduces the `polyphaseSpectrumBank` storage from ~786 KB to ~524 KB (33% reduction), since affine points use 2 field elements instead of 3.

5. **`bit_reversal_permutation` aliasing support** (fft_common.nim:307-322): The new two-argument version with aliasing detection makes the API safer while maintaining the single-argument in-place version. The old `{.noalias.}` constraint was error-prone.

6. **New `checkCirculant` bounds fix** (toeplitz.nim:74-79): The circulant validation now correctly handles the edge case where `r=1` (circulant length 2) by checking `r+1 < k2` before accessing index `r+1`.

7. **`computeAggRandScaledInterpoly` in-place IFFT** (kzg_multiproofs.nim:571): The per-column IFFT now operates in-place on `agg_cols[c]` instead of a separate `col_interpoly` buffer, eliminating an allocation and a copy operation.

## Constraints

No architectural constraints prevent incremental delivery. All internal consumers have been updated consistently. The main delivery consideration is the `polyphaseSpectrumBank` type change (ARCH-A-001), which is a breaking change to exported APIs but is scoped to the KZG multiproof subsystem.
