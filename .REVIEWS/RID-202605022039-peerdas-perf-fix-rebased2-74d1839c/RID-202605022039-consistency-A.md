---
**Branch:** `master` → `peerdas-perf-fix-rebased2` (commit `74d1839c`)
**Diff file:** `.REVIEWS/RID-202605022039-peerdas-perf-fix-rebased2-74d1839c/RID-202605022039-changes_under_review.diff`
**Date:** 2026-05-02
**Reviewer:** Consistency Analyst (Pass A)
**Scope:** PeerDAS performance overhaul — `ToeplitzAccumulator` replacing `toeplitzMatVecMulPreFFT`, `batchAffine_vartime` family, polyphase spectrum bank Jacobian→affine, `bit_reversal_permutation` aliasing support, `computeAggRandScaledInterpoly` bool→void, new `transpose` module, FFT `Alloca` tag removal
**Focus:** Convention drift, duplication, missing reuse, API blast-radius
---

# Consistency Review (Pass A)

## Summary

| ID | Severity | Confidence | File | Issue |
|----|----------|------------|------|-------|
| CONS-A-001 | High | 1.0 | `benchmarks/bench_kzg_multiproofs.nim:104-113` | `ToeplitzAccumulator.init()` inside benchmark loop — inconsistent with `bench_matrix_toeplitz.nim` pattern |
| CONS-A-002 | Medium | 1.0 | `constantine/math/polynomials/fft_common.nim:311,328` | Stale variable references in debug assertions after `bit_reversal_permutation` signature split |
| CONS-A-003 | Medium | 0.9 | `benchmarks/bench_matrix_toeplitz.nim:171,181` | `privateAccess` to `ToeplitzAccumulator.offset` for benchmark reset — no `reset()` API |
| CONS-A-004 | Medium | 0.9 | `constantine/math/elliptic/ec_twistededwards_batch_ops.nim:37-96` | Twisted Edwards `batchAffine` (CT) inconsistent with ShortWeierstrass `batchAffine` (CT) pattern |
| CONS-A-005 | Low | 0.8 | `benchmarks/bench_elliptic_template.nim:132-156` | Benchmarks test both `batchAffine` and `batchAffine_vartime`; naming convention drift from existing |
| CONS-A-006 | Low | 0.8 | `benchmarks/bench_kzg_multiproofs.nim:105-106` | Type aliases inside `bench` loop body vs outside in `bench_matrix_toeplitz.nim` |
| CONS-A-007 | Informational | 1.0 | `constantine/commitments/kzg_multiproofs.nim:832-882` | `computeAggRandScaledInterpoly` API contract change: `bool` → `void` with `doAssert` |

**Key takeaways:**
1. The `ToeplitzAccumulator` benchmark in `bench_kzg_multiproofs.nim` initializes the accumulator inside the timed loop, while the same benchmark in `bench_matrix_toeplitz.nim` correctly moves init outside. This produces misleading performance numbers and is inconsistent between the two benchmark files.
2. The `bit_reversal_permutation` refactoring introduced stale variable names in debug assertions (`buf` and `src` instead of `dst` and `buf` respectively).
3. The Twisted Edwards constant-time `batchAffine` was restructured to use a different zero-tracking pattern (template on `affs[i].y`) that diverges from the original `allocStackArray(SecretBool, N)` approach and from the ShortWeierstrass CT pattern.
4. All major API changes (`toeplitzMatVecMul` return type, `polyphaseSpectrumBank` type, `batchAffine_vartime` export, `ToeplitzStatus` enum) have call sites properly synchronized across benchmarks, tests, and production code.

## Findings

### [CONSISTENCY] CONS-A-001: `ToeplitzAccumulator.init()` inside benchmark loop — inconsistent with `bench_matrix_toeplitz.nim` pattern

**Location:** `benchmarks/bench_kzg_multiproofs.nim:104-113`
**Severity:** High
**Confidence:** 1.0

**Diff Under Review:**
```diff
+  bench("fk20_phase1_accumulation_loop", CDS, iters):
+    type BLS12_381_G1_aff = EC_ShortW_Aff[Fp[BLS12_381], G1]
+    type BLS12_381_G1_jac = EC_ShortW_Jac[Fp[BLS12_381], G1]
+    var accum: ToeplitzAccumulator[BLS12_381_G1_jac, BLS12_381_G1_aff, Fr[BLS12_381]]
+    doAssert accum.init(ctx.fft_desc_ext, ctx.ecfft_desc_ext, CDS, L) == Toeplitz_Success
+    var circulant: array[CDS, Fr[BLS12_381]]
+    for offset in 0 ..< L:
+      makeCirculantMatrix(circulant.toOpenArray(0, CDS-1), poly.coefs, offset, L)
+      doAssert accum.accumulate(circulant.toOpenArray(0, CDS-1), ctx.polyphaseSpectrumBank[offset]) == Toeplitz_Success
+    doAssert accum.finish(u.toOpenArray(0, CDS-1)) == Toeplitz_Success
```

**Issue:** The `ToeplitzAccumulator.init()` call (which allocates ~772 KB of heap memory via 3× `allocHeapAligned`) is inside the `bench()` timing loop. This means every benchmark iteration includes the full init+allocate+accumulate+finish cycle.

**Existing Pattern:** `benchmarks/bench_matrix_toeplitz.nim:171-181` correctly moves `init()` **outside** the bench loop and resets only `acc.offset = 0` inside:

```nim
# Initialize accumulator once outside the benchmark loop to avoid
# allocation overhead (3 x allocHeapAligned, ~772 KB total) in timing.
var acc: ToeplitzAccumulator[...]
let statusInit = acc.init(descs.frDesc, descs.ecDesc, size, L)
doAssert statusInit == Toeplitz_Success

bench("ToeplitzAccumulator_64accumulates", size, iters):
    # Reset accumulator state for this iteration (avoids free+alloc)
    acc.offset = 0
    for i in 0 ..< L:
      let status = acc.accumulate(...)
```

The inconsistency is notable because the two benchmark files benchmark the same `ToeplitzAccumulator` type, but produce different measured costs. The `bench_kzg_multiproofs.nim` version includes init/alloc/destroy overhead in every iteration while `bench_matrix_toeplitz.nim` measures only accumulate+finish.

**Issue Type:** inconsistent-pattern

**Scope:** 
- `benchmarks/bench_kzg_multiproofs.nim:104-113` — init inside bench loop
- `benchmarks/bench_matrix_toeplitz.nim:171-181` — init outside bench loop (correct)

**Suggested Change:** Move `ToeplitzAccumulator.init()` outside the `bench()` loop in `bench_kzg_multiproofs.nim`, matching the `bench_matrix_toeplitz.nim` pattern. Use `privateAccess` to reset `offset = 0` inside the loop.

---

### [CONSISTENCY] CONS-A-002: Stale variable references in debug assertions after `bit_reversal_permutation` signature split

**Location:** `constantine/math/polynomials/fft_common.nim:311,328`
**Severity:** Medium
**Confidence:** 1.0

**Diff Under Review:**
```diff
+func bit_reversal_permutation*[T](dst: var openArray[T], src: openArray[T]) {.inline.} =
+  ## Out-of-place bit reversal permutation with aliasing detection.
+  debug: doAssert buf.len.uint.isPowerOf2_vartime()  # ← should be dst.len
+  debug: doAssert dst.len == src.len
+  debug: doAssert dst.len > 0

+func bit_reversal_permutation*[T](buf: var openArray[T]) {.inline.} =
+  ## In-place bit reversal permutation.
+  debug: doAssert src.len.uint.isPowerOf2_vartime()  # ← should be buf.len
+  debug: doAssert buf.len > 0
```

**Issue:** After splitting `bit_reversal_permutation` into `bit_reversal_permutation_noalias` (no-alias version) and a new aliased-aware `bit_reversal_permutation`, the debug assertions in the new overloads reference variable names that don't exist:
- Line 311: `buf.len` should be `dst.len` (this overload has parameters `dst` and `src`, not `buf`)
- Line 328: `src.len` should be `buf.len` (this overload has parameter `buf`, not `src`)

These are stale variable references from the original function that had parameter `buf` and was renamed to `bit_reversal_permutation_noalias`.

**Existing Pattern:** The original function before the split:
```nim
func bit_reversal_permutation*[T](dst{.noalias.}: var openArray[T], src{.noalias.}: openArray[T]) {.inline.} =
```
had `debug: doAssert buf.len.uint.isPowerOf2_vartime()` — where `buf` came from the single-arg in-place overload.

**Issue Type:** convention-drift

**Scope:** `constantine/math/polynomials/fft_common.nim` only

**Suggested Change:** 
- Line 311: `buf.len` → `dst.len` 
- Line 328: `src.len` → `buf.len`

---

### [CONSISTENCY] CONS-A-003: `privateAccess` to `ToeplitzAccumulator.offset` for benchmark reset — no `reset()` API

**Location:** `benchmarks/bench_matrix_toeplitz.nim:171,181`
**Severity:** Medium
**Confidence:** 0.9

**Diff Under Review:**
```diff
+  # Allow direct access to private 'offset' field for benchmark reuse
+  privateAccess(toeplitz.ToeplitzAccumulator)
+
+  bench("ToeplitzAccumulator_64accumulates", size, iters):
+    # Reset accumulator state for this iteration (avoids free+alloc)
+    acc.offset = 0
```

**Issue:** The benchmark resets `ToeplitzAccumulator` state by directly accessing the private `offset` field via `privateAccess`. This is a benchmark-specific workaround because `ToeplitzAccumulator` has no public `reset()` method.

The `init()` method handles defensive double-init (freed + reallocates), but calling `init()` per-iteration is expensive. The benchmark workarounds this by directly resetting `offset`, but this is fragile — if other fields are added to the accumulator (e.g., accumulated state), this reset pattern will silently produce wrong results.

**Existing Pattern:** Other stateful objects in Constantine typically provide either:
- A `reset()` or `clear()` method for state reuse
- A cheap default initialization that the caller can invoke per-iteration

**Issue Type:** missing-reuse

**Scope:** `benchmarks/bench_matrix_toeplitz.nim:171,181`; `constantine/math/matrix/toeplitz.nim:188-223`

**Suggested Change:** Add a public `reset*(ctx: var ToeplitzAccumulator[...])` method to the `ToeplitzAccumulator` type that resets `offset = 0` and any other state. This eliminates the need for `privateAccess` and provides a stable API for benchmarks that reuse the accumulator.

---

### [CONSISTENCY] CONS-A-004: Twisted Edwards `batchAffine` (CT) inconsistent with ShortWeierstrass `batchAffine` (CT) pattern

**Location:** `constantine/math/elliptic/ec_twistededwards_batch_ops.nim:37-96`
**Severity:** Medium
**Confidence:** 0.9

**Diff Under Review:**
```diff
 func batchAffine*[F](
        affs: ptr UncheckedArray[EC_TwEdw_Aff[F]],
        projs: ptr UncheckedArray[EC_TwEdw_Prj[F]],
-       N: int) {.noInline, tags:[Alloca].} =
+       N: int) {.meter.} =
+  if N <= 0:
+    return
   # ... 
-  let zeroes = allocStackArray(SecretBool, N)
+  template zero(i: int): SecretWord =
+    affs[i].y.mres.limbs[0]
   # ...
-  zeroes[0] = affs[0].x.isZero()
-  affs[0].x.csetOne(zeroes[0])
+  zero(0) = SecretWord affs[0].x.isZero()
+  affs[0].x.csetOne(SecretBool zero(0))
```

**Issue:** The Twisted Edwards constant-time `batchAffine` was substantially restructured:
1. **Tag change:** `{.noInline, tags:[Alloca].}` → `{.meter.}` — removes `noInline` and `Alloca` tags, adds `meter`. This is inconsistent with the ShortWeierstrass CT `batchAffine` which uses `{.meter.}` without explicit `noInline` or `Alloca`.
2. **Zero tracking:** Changed from `allocStackArray(SecretBool, N)` (stack allocation of a separate array) to a `template zero(i)` that reuses `affs[i].y` as a scratch register. This matches the ShortWeierstrass `batchAffine_vartime` pattern, but the ShortWeierstrass CT `batchAffine` still uses `allocStackArray(SecretBool, N)`.
3. **Guard:** Added `if N <= 0: return` — consistent with new guards in ShortWeierstrass CT `batchAffine`.

The structural rewrite (replacing `SecretBool` stack array with template-based register reuse) in the CT version is notable because it diverges from the ShortWeierstrass CT version while converging with the ShortWeierstrass vartime version. This may be intentional (optimization) but creates an inconsistency between CT implementations of different curve forms.

**Existing Pattern:** 
- ShortWeierstrass CT `batchAffine` (`ec_shortweierstrass_batch_ops.nim`): Uses `allocStackArray(SecretBool, N)`, `{.meter.}` tags
- ShortWeierstrass vartime `batchAffine_vartime` (`ec_shortweierstrass_batch_ops.nim`): Uses `template zero(i)` on `affs[i].y`, `{.tags:[VarTime], meter.}` tags
- Twisted Edwards vartime `batchAffine_vartime` (`ec_twistededwards_batch_ops.nim`): Uses `template zero(i)` on `affs[i].y`, `{.tags:[VarTime], meter.}` tags

**Issue Type:** inconsistent-pattern

**Scope:** `constantine/math/elliptic/ec_twistededwards_batch_ops.nim`, `constantine/math/elliptic/ec_shortweierstrass_batch_ops.nim`

**Suggested Change:** Consider whether the Twisted Edwards CT `batchAffine` restructuring is intentional or accidental. If intentional, consider applying the same optimization to the ShortWeierstrass CT `batchAffine` for consistency. If the ShortWeierstrass CT version should remain unchanged, add a comment explaining why the Twisted Edwards version diverges.

---

### [CONSISTENCY] CONS-A-005: Benchmarks test both `batchAffine` and `batchAffine_vartime`; naming convention drift

**Location:** `benchmarks/bench_elliptic_template.nim:132-156`
**Severity:** Low
**Confidence:** 0.8

**Diff Under Review:**
```diff
   if useBatching:
-    bench("EC Projective to Affine -   batched " & $EC.G & " (" & $numPoints & " points)", EC, iters):
-      r.asUnchecked().batchAffine(points.asUnchecked(), numPoints)
+    block:
+      bench("EC Projective to Affine -   batched " & $EC.G & " (" & $numPoints & " points)", EC, iters):
+        r.asUnchecked().batchAffine(points.asUnchecked(), numPoints)
+    block:
+      bench("EC Projective to Affine -   batched_vt " & $EC.G & " (" & $numPoints & " points)", EC, iters):
+        r.asUnchecked().batchAffine_vartime(points.asUnchecked(), numPoints)
```

**Issue:** The benchmark naming uses `batched_vt` suffix to distinguish variable-time from constant-time. This follows a consistent convention within the diff, but uses an abbreviation (`vt`) rather than the full `vartime` suffix used in the actual function names (`batchAffine_vartime`).

The project convention for variable-time functions uses the `_vartime` suffix (e.g., `batchAffine_vartime`, `scalarMul_wNAF_vartime`, `inv_vartime`). The benchmark labels use `_vt` which is inconsistent with the function naming convention.

**Existing Pattern:** Function naming: `batchAffine_vartime`, `scalarMul_vartime`, `diff_vartime`, `inv_vartime`. Test naming in `t_ec_template.nim`: `isVartime = true` with suffix `" (vartime)"` and `"_vartime"` in test module names.

**Issue Type:** convention-drift

**Scope:** `benchmarks/bench_elliptic_template.nim:132-156`

**Suggested Change:** Rename `batched_vt` to `batched_vartime` in benchmark labels to match the function naming convention. Alternatively, standardize on `batched_vt` if space is a concern in benchmark output.

---

### [CONSISTENCY] CONS-A-006: Type aliases inside `bench` loop body vs outside in `bench_matrix_toeplitz.nim`

**Location:** `benchmarks/bench_kzg_multiproofs.nim:105-106`
**Severity:** Low
**Confidence:** 0.8

**Diff Under Review:**
```diff
+  bench("fk20_phase1_accumulation_loop", CDS, iters):
+    type BLS12_381_G1_aff = EC_ShortW_Aff[Fp[BLS12_381], G1]
+    type BLS12_381_G1_jac = EC_ShortW_Jac[Fp[BLS12_381], G1]
+    var accum: ToeplitzAccumulator[BLS12_381_G1_jac, BLS12_381_G1_aff, Fr[BLS12_381]]
```

**Issue:** In `bench_kzg_multiproofs.nim`, type aliases for `ToeplitzAccumulator` template parameters are defined inside the `bench()` loop body. In `bench_matrix_toeplitz.nim`, the equivalent aliases are defined at proc scope:

```nim
# bench_matrix_toeplitz.nim:147-148
# Type aliases matching ToeplitzAccumulator (following bench_kzg_multiproofs.nim pattern)
type BLS12_381_G1_aff = EC_ShortW_Aff[Fp[BLS12_381], G1]
type BLS12_381_G1_jac = EC_ShortW_Jac[Fp[BLS12_381], G1]
```

The comment in `bench_matrix_toeplitz.nim` even claims to follow the `bench_kzg_multiproofs.nim` pattern, but the pattern placement differs (proc-scope vs block-scope). Both are valid Nim, but the inconsistency within the same benchmark suite is notable.

**Issue Type:** convention-drift

**Scope:** `benchmarks/bench_kzg_multiproofs.nim:105-106`, `benchmarks/bench_matrix_toeplitz.nim:147-148`

**Suggested Change:** Move type aliases to proc scope in `bench_kzg_multiproofs.nim` to match `bench_matrix_toeplitz.nim`, or vice versa. Update the comment in `bench_matrix_toeplitz.nim` if the patterns intentionally differ.

---

### [CONSISTENCY] CONS-A-007: `computeAggRandScaledInterpoly` API contract change: `bool` → `void` with `doAssert`

**Location:** `constantine/commitments/kzg_multiproofs.nim:832-882`
**Severity:** Informational
**Confidence:** 1.0

**Diff Under Review:**
```diff
- func computeAggRandScaledInterpoly[Name: static Algebra, L: static int](
+ func computeAggRandScaledInterpoly[Name: static Algebra, L: static int](
        ...,
-      N: static int): bool {.meter.} =
+      N: static int) {.meter.} =
   ## ...
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

-  if not interpoly.computeAggRandScaledInterpoly(...):
-    return false
+  interpoly.computeAggRandScaledInterpoly(...)
```

**Issue:** The function's API contract changed from returning `bool` (caller checks for error) to returning `void` with internal `doAssert` validation. The only caller (`kzg_coset_verify_batch`) no longer checks a return value — it assumes success.

The assertions are labeled "Internal error" which implies these conditions should never occur with valid inputs. However, the previous `bool` return allowed the caller to handle invalid inputs gracefully (returning `false` from `kzg_coset_verify_batch`). Now, invalid inputs cause assertion failures rather than graceful rejection.

This is consistent with a project-wide pattern shift seen in the diff — converting runtime-return-error patterns to `doAssert` patterns — but represents a behavioral change in the public verification API surface.

**Issue Type:** api-blast-radius

**Scope:** 
- `constantine/commitments/kzg_multiproofs.nim:502-882` — function definition and caller
- All call sites of `kzg_coset_verify_batch` (verification entry point) are affected

**Suggested Change:** Document the API contract change. If this is intended to be an internal-only function (never called with untrusted input), mark it as such. If it's a public verification API, consider keeping the `bool` return for graceful error handling.

---

## Positive Changes

1. **Unified `_vartime` naming convention**: The new `batchAffine_vartime` functions across ShortWeierstrass (projective + Jacobian) and Twisted Edwards follow a consistent naming pattern matching `inv_vartime`, `scalarMul_vartime`, etc.

2. **Complete `batchAffine_vartime` overload set**: Both curve families (ShortWeierstrass, Twisted Edwards) receive the same family of overloads — ptr/UncheckedArray, single-dimension array, and 2D array — matching the existing `batchAffine` overload pattern exactly.

3. **`ToeplitzAccumulator` lifecycle management**: The new type properly uses `=copy {.error.}` to prevent accidental copies, `=destroy` with nil-checks for RAII cleanup, and the `init` method handles defensive double-init. This follows established patterns in the project (e.g., `EcAddAccumulator_vartime`).

4. **`N <= 0` guard consistency**: All new `batchAffine` and `batchAffine_vartime` functions (ShortWeierstrass projective, ShortWeierstrass Jacobian, Twisted Edwards projective) include the `if N <= 0: return` guard. This was also added to existing CT functions in the diff, creating uniform defensive behavior across the family.

5. **`bit_reversal_permutation_noalias` as a clear internal primitive**: The refactoring correctly splits the aliased and non-aliased cases, providing a clean `_noalias` variant for performance-critical callers (FFT code) while maintaining a safe default `bit_reversal_permutation` that handles aliasing automatically.

## API Blast-Radius Verification

| Changed API | Old Signature | New Signature | All Call Sites Updated? |
|------------|--------------|---------------|------------------------|
| `toeplitzMatVecMul` return type | `FFTStatus` | `ToeplitzStatus` | ✅ `bench_matrix_toeplitz.nim`, `t_toeplitz.nim` |
| `polyphaseSpectrumBank` type | `EC_ShortW_Jac[...]` | `EC_ShortW_Aff[...]` | ✅ `ethereum_kzg_srs.nim`, `kzg_multiproofs.nim`, `bench_kzg_multiproofs.nim`, `t_kzg_multiproofs.nim` |
| `batchAffine` → `batchAffine_vartime` | `batchAffine(...)` | `batchAffine_vartime(...)` | ✅ All 10 production call sites in diff |
| `batchAffine` export | Not exported from `lowlevel_elliptic_curves.nim` | `export ec_shortweierstrass.batchAffine_vartime` | ✅ Added for both ShortWeierstrass and Twisted Edwards |
| `ToeplitzAccumulator` (new) | N/A | `ToeplitzAccumulator[EC, ECaff, F]` | ✅ `kzg_multiproofs.nim`, `bench_kzg_multiproofs.nim`, `bench_matrix_toeplitz.nim`, `t_toeplitz.nim` |
| `FFT` `Alloca` tag removal | `{.tags:[VarTime, Alloca].}` | `{.tags:[VarTime].}` | ✅ 15+ functions in `fft_ec.nim` — callers not affected (tags are metadata) |
| `computeAggRandScaledInterpoly` return | `bool` | `void` | ✅ Only caller `kzg_coset_verify_batch` updated |
| `bit_reversal_permutation` split | Single function | `bit_reversal_permutation_noalias` + `bit_reversal_permutation` | ✅ All internal callers use `_noalias`; public API unchanged |
| `toeplitzMatVecMulPreFFT` (removed) | Public `proc` | Removed | ✅ All callers migrated to `ToeplitzAccumulator` API |
