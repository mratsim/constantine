---
**Branch:** `master` → `peerdas-perf-fix-rebased2` (commit `74d1839c`)
**Diff file:** `.REVIEWS/RID-202605022039-peerdas-perf-fix-rebased2-74d1839c/RID-202605022039-changes_under_review.diff`
**Date:** 2026-05-02
**Reviewer:** Consistency Analyst (Pass B)
**Scope:** PeerDAS performance fix — `batchAffine_vartime`, `ToeplitzAccumulator`, polyphase bank layout change (Jacobian→Affine), FFT `Alloca` tag removal, matrix transpose
**Focus:** Naming consistency, coding style drift, dead code, abstraction patterns, API synchronization
---

# Consistency Review (Pass B)

## Summary

| ID | Severity | Confidence | File | Issue |
|----|----------|------------|------|-------|
| CONS-B-001 | Medium | 0.9 | `constantine/nimble` | `bench_matrix_transpose.nim` not registered in `benchDesc` or tasks |
| CONS-B-002 | Medium | 0.9 | `constantine/math/elliptic/ec_twistededwards_batch_ops.nim` | `.noInline` tag removed but kept in `ec_shortweierstrass_batch_ops.nim` |
| CONS-B-003 | Medium | 0.8 | `constantine/math/matrix/toeplitz.nim` | `checkCirculant*` exported but only used in `debug:` block |
| CONS-B-004 | Medium | 0.8 | `constantine/math/matrix/toeplitz.nim` | `checkReturn`/`check` templates overlap with `eth_peerdas.nim` and `eth_verkle_ipa.nim` patterns |
| CONS-B-005 | Low | 0.8 | `constantine/math/elliptic/ec_shortweierstrass_batch_ops.nim` | `batchAffine_vartime` uses `.bool()` while project standard is `.bool` (property) |
| CONS-B-006 | Low | 0.7 | `constantine/math/polynomials/fft_common.nim` | `bit_reversal_permutation_noalias` naming inconsistent with `noalias` pragma convention |
| CONS-B-007 | Low | 0.7 | `constantine/commitments/kzg_multiproofs.nim` | `computeAggRandScaledInterpoly` return type `bool→void` — no external callers but API contract change |
| CONS-B-008 | Low | 0.6 | `benchmarks/bench_matrix_toeplitz.nim` | `privateAccess` to reset `ToeplitzAccumulator.offset` — should use a public `reset()` method |
| CONS-B-009 | Informational | 0.9 | `constantine/commitments/kzg_multiproofs.nim` | `kzg_coset_prove` doc comment separator alignment inconsistency |

**Key takeaways:**
1. **Missing benchmark registration** — `bench_matrix_transpose.nim` is a new file but not registered in `constantine.nimble`, meaning it won't be compiled or run by CI.
2. **Inconsistent `.noInline` tag removal** — Twisted Edwards had `.noInline` stripped but Short Weierstrass retained it, creating asymmetry between sibling modules.
3. **Export surface bloat** — `checkCirculant*` is exported but production code never calls it; should be unexported or moved to a debug-only module.
4. **Template naming collision** — New `checkReturn`/`check` templates in `toeplitz.nim` duplicate patterns from `eth_peerdas.nim` and `eth_verkle_ipa.nim` with different behavior.

## Findings

### [CONSISTENCY] CONS-B-001: `bench_matrix_transpose.nim` not registered in `benchDesc` or nimble tasks - constantine.nimble

**Location:** `constantine.nimble` (lines 699-755 for `benchDesc`, lines 1200+ for tasks)
**Severity:** Medium
**Confidence:** 0.9

**Diff Under Review:**
```diff
+ # New file: benchmarks/bench_matrix_transpose.nim (214 lines)
+ # But no corresponding entry in:
+ #   constantine.nimble → benchDesc array
+ #   constantine.nimble → task bench_matrix_transpose
```

**Issue:** **New benchmark file not registered in build system**

The file `benchmarks/bench_matrix_transpose.nim` was created as a new benchmark for matrix transposition strategies, but it has no corresponding entry in `constantine.nimble`. The renamed `bench_matrix_toeplitz` was properly registered:

```
constantine.nimble:739:   "bench_matrix_toeplitz",
constantine.nimble:1212: task bench_matrix_toeplitz, "Run Toeplitz matrix benchmarks...":
constantine.nimble:1213:   runBench("bench_matrix_toeplitz")
```

But `bench_matrix_transpose` is missing both a `benchDesc` entry and a `task`. This means:
- The benchmark won't be compiled by the `benches` compile-check task
- There's no `nimble bench_matrix_transpose` command to run it
- CI won't verify it compiles

**Issue Type:** missing-reuse

**Existing Pattern:** `constantine.nimble:739` — `bench_matrix_toeplitz` properly registered in `benchDesc` and has a `task` definition.

**Suggested Change:** Add `bench_matrix_transpose` to `benchDesc` and create a matching `task bench_matrix_transpose` in `constantine.nimble`:

```nim
const benchDesc = [
  # ...
  "bench_matrix_toeplitz",
  "bench_matrix_transpose",  # ADD THIS
  # ...
]

task bench_matrix_transpose, "Run matrix transpose benchmarks (Naive vs 1D/2D Blocked) - CC compiler":
  runBench("bench_matrix_transpose")
```

---

### [CONSISTENCY] CONS-B-002: `.noInline` tag removed from Twisted Edwards but kept in Short Weierstrass batch ops - ec_twistededwards_batch_ops.nim:28

**Location:** `constantine/math/elliptic/ec_twistededwards_batch_ops.nim:28`
**Severity:** Medium
**Confidence:** 0.9

**Diff Under Review:**
```diff
-       N: int) {.noInline, tags:[Alloca].} =
+       N: int) {.meter.} =
```

**Issue:** **Asymmetric tag treatment between sibling batch ops modules**

The `batchAffine` function in `ec_twistededwards_batch_ops.nim` had its `.noInline` tag removed (along with `Alloca`, which was correctly removed since the function doesn't use VLA). However, equivalent functions in the sibling `ec_shortweierstrass_batch_ops.nim` module still retain `.noInline`:

- `ec_shortweierstrass_batch_ops.nim:455` — `batchFromAffine*` still has `.noInline, tags:[VarTime, Alloca]`
- `ec_shortweierstrass_batch_ops.nim:582` — `batchFromJac*` still has `.noInline, tags:[VarTime, Alloca]`
- `ec_shortweierstrass_batch_ops.nim:686` — `accumSum_chunk_vartime*` still has `.noInline, tags:[VarTime, Alloca]`

The rationale for removing `Alloca` from the iterative implementations is sound (they don't use VLA). But the removal of `.noInline` from the Twisted Edwards version creates inconsistency. Both modules' batch affine functions are large enough that inlining would blow up code size.

**Issue Type:** convention-drift

**Existing Pattern:** `constantine/math/elliptic/ec_shortweierstrass_batch_ops.nim:455` — `batchFromAffine` retains `.noInline` on comparable batch operations.

**Suggested Change:** Either:
1. Restore `.noInline` on the Twisted Edwards `batchAffine` to match the Short Weierstrass convention: `{.noInline, meter.}`
2. Or remove `.noInline` from ALL equivalent batch ops in `ec_shortweierstrass_batch_ops.nim` to make the treatment uniform.

---

### [CONSISTENCY] CONS-B-003: `checkCirculant*` is exported but only used in a `debug:` block - toeplitz.nim:40

**Location:** `constantine/math/matrix/toeplitz.nim:40`
**Severity:** Medium
**Confidence:** 0.8

**Diff Under Review:**
```diff
 func checkCirculant*[F](
```

**Issue:** **Exported utility only used in debug context**

The `checkCirculant*` function is marked as exported (`*`) but its only call site in the codebase is in a `debug:` block:

```nim
# toeplitz.nim:142
debug: doAssert checkCirculant(output, poly, offset, stride)
```

Exporting a function that's exclusively used for debug assertions inflates the public API surface. The function also requires understanding of circulant matrix structure to use correctly, making it a poor candidate for general export.

**Issue Type:** convention-drift

**Existing Pattern:** Debug-only utilities in the codebase typically use `debug:` guards or are unexported. The `checkCirculant` function follows the naming convention of other `check*` functions but is the only one exported that's solely debug-use.

**Suggested Change:** Remove the `*` export marker from `checkCirculant` to make it a private utility:

```nim
func checkCirculant[F](  # remove *
```

If external test code needs it, the benchmark/test files can use `privateAccess` to access it, similar to how `ToeplitzAccumulator.offset` is accessed.

---

### [CONSISTENCY] CONS-B-004: `checkReturn`/`check` templates duplicate patterns from other modules - toeplitz.nim:155-177

**Location:** `constantine/math/matrix/toeplitz.nim:155-177`
**Severity:** Medium
**Confidence:** 0.8

**Diff Under Review:**
```diff
+ template checkReturn*(evalExpr: untyped): untyped {.dirty.} =
+   block:
+     let status = evalExpr
+     when status is ToeplitzStatus:
+       if status != Toeplitz_Success:
+         return status
+     elif status is FFTStatus:
+       if status != FFT_Success:
+         return case status
+           of FFT_SizeNotPowerOfTwo: Toeplitz_SizeNotPowerOfTwo
+           of FFT_TooManyValues: Toeplitz_TooManyValues
+           else: Toeplitz_MismatchedSizes
+
+ template check*(Section: untyped, evalExpr: untyped): untyped {.dirty.} =
```

**Issue:** **Template names and patterns overlap with existing modules**

The new `checkReturn` and `check` templates in `toeplitz.nim` have similar names but different semantics from templates in other modules:

1. **`checkReturn`** in `toeplitz.nim` — takes `untyped`, dispatches on type, returns status. Generic and exported.
2. **`checkReturn`** in `eth_verkle_ipa.nim:90` — takes specific codec status types, returns early. NOT exported.
3. **`check`** in `toeplitz.nim` — takes a section label + expr, breaks on failure with status conversion.
4. **`check`** in `eth_peerdas.nim:79` — takes `FFT_Status`, uses `doAssert`. Different behavior.
5. **`check`** in `eth_verkle_ipa.nim:113` — takes specific codec status types, breaks on failure. NOT exported.
6. **`check`** in `ethereum_eip4844_kzg.nim:272` — takes codec status types, breaks on failure. NOT exported.

The toeplitz templates are the only ones exported and generic. This creates naming confusion when multiple modules are imported simultaneously, and makes it unclear whether there's a shared utility or intentionally divergent implementations.

**Issue Type:** inconsistent-pattern

**Existing Pattern:** `constantine/data_availability_sampling/eth_peerdas.nim:79` — `template check(expression: FFT_Status)` with `doAssert` semantics. `constantine/commitments/eth_verkle_ipa.nim:113` — `template check(Section, evalExpr)` with codec-specific status handling.

**Suggested Change:** Either:
1. Consolidate into a shared `constantine/platforms/error_handling.nim` module with a unified `checkStatus` template that handles both `FFTStatus` and `ToeplitzStatus`.
2. Or rename the toeplitz templates to be more specific: `checkToeplitzReturn`, `checkToeplitz`, to avoid name collisions.

---

### [CONSISTENCY] CONS-B-005: `batchAffine_vartime` uses `.bool()` while project standard is `.bool` - ec_shortweierstrass_batch_ops.nim:211

**Location:** `constantine/math/elliptic/ec_shortweierstrass_batch_ops.nim:211-328`
**Severity:** Low
**Confidence:** 0.8

**Diff Under Review:**
```diff
+   if zero(0).bool():
+   if zero(i).bool():
```

**Issue:** **Inconsistent `.bool()` vs `.bool` access pattern**

The new `batchAffine_vartime` functions consistently use `.bool()` (function call syntax) to extract boolean values from `SecretWord`:

```nim
if zero(0).bool():
if zero(i).bool():
```

However, the broader codebase predominantly uses `.bool` (property access, no parens) on `SecretBool`/`CTBool` types:

- `ec_shortweierstrass_projective.nim:491`: `if p.isNeutral().bool:` (no parens)
- `ec_scalar_mul_vartime.nim:410`: `if negatePoints[0].bool:` (no parens)
- `ec_multi_scalar_mul.nim:181`: `elif negate.bool:` (no parens)
- `ethereum_bls_signatures_parallel.nim:74`: `if pubkeys[i].raw.isNeutral().bool:` (no parens)

The `.bool()` syntax works because `SecretWord` is `Ct[BaseType]` which is `distinct BaseType` (uint32/uint64), and Nim allows implicit conversion to `bool`. But the established convention in this codebase is `.bool` (property access).

**Issue Type:** convention-drift

**Existing Pattern:** `constantine/math/elliptic/ec_scalar_mul_vartime.nim:410` — `if negatePoints[0].bool:` — property access without parens.

**Suggested Change:** Replace all `.bool()` calls in the new `batchAffine_vartime` code with `.bool` to match the project convention. Since `zero(i)` returns `SecretWord` (not `SecretBool`), the fix would be to either:
1. Change the `zero` template to return `SecretBool` instead of `SecretWord`, matching the constant-time pattern.
2. Or keep `SecretWord` and use `.bool` (property) consistently.

---

### [CONSISTENCY] CONS-B-006: `bit_reversal_permutation_noalias` naming inconsistent with `noalias` pragma convention - fft_common.nim:290

**Location:** `constantine/math/polynomials/fft_common.nim:290`
**Severity:** Low
**Confidence:** 0.7

**Diff Under Review:**
```diff
- func bit_reversal_permutation*[T](dst{.noalias.}: var openArray[T], src{.noalias.}: openArray[T]) {.inline.} =
+ func bit_reversal_permutation_noalias*[T](dst{.noalias.}: var openArray[T], src{.noalias.}: openArray[T]) {.inline.} =
```

**Issue:** **Naming pattern for no-alias variants not aligned with project convention**

The original `bit_reversal_permutation` was renamed to `bit_reversal_permutation_noalias`, and a new aliasing-safe wrapper was created. While the intent is clear, the `_noalias` suffix naming convention is not used elsewhere in the project for similar patterns.

The `{.noalias.}` pragma is used throughout the codebase, but there's no established pattern of creating `_noalias` suffixed function variants. Other similar patterns use different approaches:
- Functions with different aliasing requirements use different parameter names (e.g., `dst{.noalias.}` vs `dst`)
- Overloaded functions with different signatures

**Issue Type:** naming convention

**Existing Pattern:** `constantine/math/elliptic/ec_shortweierstrass_batch_ops.nim` — Overloaded `batchAffine*` functions for different coordinate systems (Prj vs Jac) don't use `_prj`/`_jac` suffixes; they rely on Nim's overload resolution.

**Suggested Change:** Consider using function overloading instead of suffix naming:

```nim
func bit_reversal_permutation*[T](dst{.noalias.}: var openArray[T], src{.noalias.}: openArray[T]) {.inline.} =
  ## Out-of-place bit reversal permutation (no aliasing between dst and src).

func bit_reversal_permutation*[T](dst: var openArray[T], src: openArray[T]) {.inline.} =
  ## Out-of-place bit reversal permutation with aliasing detection.
```

Nim can distinguish these by the presence/absence of `{.noalias.}` on parameters. However, if the current approach is intentional for clarity, document the naming convention.

---

### [CONSISTENCY] CONS-B-007: `computeAggRandScaledInterpoly` return type changed from `bool` to `void` - kzg_multiproofs.nim:502

**Location:** `constantine/commitments/kzg_multiproofs.nim:502`
**Severity:** Low
**Confidence:** 0.7

**Diff Under Review:**
```diff
-      N: static int): bool {.meter.} =
+      N: static int) {.meter.} =
```

**Issue:** **Return type change from `bool` to `void` changes API contract**

The function `computeAggRandScaledInterpoly` previously returned `bool` (true on success, false on invalid input). The new version removes the return type and uses `doAssert` for all validation, effectively making it `void`. The call site was updated:

```diff
-  if not interpoly.computeAggRandScaledInterpoly(...):
-    return false
+  interpoly.computeAggRandScaledInterpoly(...)
```

While this is internally correct (the single call site is properly updated), the function's return type change means that any future code that tries to check the return value will get a compile error. This is a breaking API change for any external code that might call this function directly.

**Issue Type:** breaking-change

**Existing Pattern:** `constantine/commitments/kzg_multiproofs.nim:700` — The call site in `kzg_coset_verify_batch` is updated to not check the return value.

**Suggested Change:** Document the breaking change or provide a `deprecated` wrapper that returns `true` always, to give downstream code time to adapt. Alternatively, the function can be made `proc` instead of `func` and return `void` explicitly with a deprecation note in the changelog.

---

### [CONSISTENCY] CONS-B-008: `privateAccess` used to reset `ToeplitzAccumulator.offset` — should use public `reset()` method - bench_matrix_toeplitz.nim:181

**Location:** `benchmarks/bench_matrix_toeplitz.nim:181`
**Severity:** Low
**Confidence:** 0.7

**Diff Under Review:**
```diff
+  privateAccess(toeplitz.ToeplitzAccumulator)
...
+    acc.offset = 0
```

**Issue:** **Benchmark uses `privateAccess` to reset accumulator state**

The benchmark reuses the same `ToeplitzAccumulator` instance across benchmark iterations to avoid allocation overhead. To reset the offset counter, it uses `privateAccess(toeplitz.ToeplitzAccumulator)` to directly set `acc.offset = 0`.

While this is a pragmatic benchmark optimization, it exposes an internal implementation detail and would break if the field name changes. A cleaner approach would be to provide a public `reset()` or `clear()` method.

**Issue Type:** missing-reuse

**Existing Pattern:** `constantine/math/matrix/toeplitz.nim:214` — The `init()` method defensively handles double-init by freeing existing allocations, but doesn't provide a cheap reset path.

**Suggested Change:** Add a public `reset()` or `clear()` method to `ToeplitzAccumulator` that resets `offset = 0` without freeing reallocations:

```nim
proc reset*[EC, ECaff, F](ctx: var ToeplitzAccumulator[EC, ECaff, F]) {.raises: [].} =
  ctx.offset = 0
  # Optionally clear coeffs/points buffers
```

Then the benchmark can use `acc.reset()` instead of `privateAccess`.

---

### [CONSISTENCY] CONS-B-009: Doc comment separator alignment inconsistency - kzg_multiproofs.nim:373

**Location:** `constantine/commitments/kzg_multiproofs.nim:373`
**Severity:** Informational
**Confidence:** 0.9

**Diff Under Review:**
```diff
-  ##   ─────────────────────────────────────────────────────────────────────────
+  ##   ─────────────────────────────────────────────────────────────────────
```

**Issue:** **Doc comment table separator alignment adjusted**

The `kzg_coset_prove` function's doc comment has a table separator line that was shortened. The original line (94 dashes) and the new line (80 dashes) both serve as visual separators. The new length more closely matches the actual content width above it.

**Issue Type:** cosmetic

**Existing Pattern:** `constantine/commitments/kzg_multiproofs.nim:673` — A similar separator line at line 673 was also shortened from 94 to 80 dashes.

**Suggested Change:** No action needed. The alignment is improved and consistent within the file. This is noted for awareness only.

---

## Positive Changes

1. **`polyphaseSpectrumBank` layout change (Jacobian→Affine)** — Changing the precomputed polyphase spectrum bank from Jacobian to Affine coordinates is a well-thought-out optimization. It avoids repeated Jacobian→Affine conversions in the hot path and leverages a single batch inversion during setup. The API changes are properly synchronized across `ethereum_kzg_srs.nim`, `kzg_multiproofs.nim`, benchmarks, and tests.

2. **`ToeplitzAccumulator` abstraction** — The new `ToeplitzAccumulator` object cleanly encapsulates the FK20 accumulation pattern with proper memory management (`=destroy`, `=copy` disabled). The `init/accumulate/finish` lifecycle is clear and follows the existing descriptor pattern (`FrFFT_Descriptor`, `ECFFT_Descriptor`).

3. **FFT `Alloca` tag removal** — Removing `Alloca` tags from iterative FFT implementations is correct. The iterative variants don't use VLA (stack arrays), so the tag was misleading. This enables proper effect tracking and prevents the compiler from unnecessarily reserving stack space.

4. **In-place FFT operations** — Multiple changes leverage in-place FFT operations (`ec_fft_nn(u, u)`, `ifft_rn(buf, buf)`) to avoid extra allocations. This is consistent with the project's zero-allocation philosophy.

5. **Comprehensive test coverage for `batchAffine_vartime`** — The test template `run_EC_affine_conversion` was extended with `isVartime` parameter, edge case tests (single element, all neutral, varied batch sizes), and twisted Edwards coverage. This is thorough and follows the existing test infrastructure well.

6. **`bit_reversal_permutation` aliasing support** — The new aliasing-aware wrapper correctly detects when `dst` and `src` overlap and uses a temporary buffer. The `noalias` version preserves performance for the common case. This is a robust fix for a real safety concern.
