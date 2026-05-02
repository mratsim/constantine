---
**Branch:** `master` → `peerdas-perf-fix-rebased2` (commit `81784ecd`)
**Diff file:** `.REVIEWS/RID-202605022113-peerdas-perf-fix-rebased2-81784ecd/RID-202605022113-changes_under_review.diff`
**Date:** 2026-05-02
**Reviewer:** Math-Crypto Engineer (Pass A)
**Scope:** PeerDAS FK20 KZG multiproof performance optimizations — ToeplitzAccumulator, batchAffine_vartime, polyphase spectrum bank type change (Jacobian→Affine), in-place FFT, bit reversal permutation aliasing detection
**Focus:** Elliptic curves, pairings, ZK proofs, FFTs, field arithmetic, protocol correctness, side-channels
---

# Math-Crypto Review (Pass A)

## Summary

| ID | Severity | Confidence | File | Issue |
|----|----------|------------|------|-------|
| MATH-A-001 | High | 0.7 | constantine/commitments/kzg_multiproofs.nim:502-579 | Runtime validation removed from `computeAggRandScaledInterpoly` (bool→void, `if` checks replaced by `doAssert`) |

**Key takeaways:**
1. The FK20 algorithm refactoring (ToeplitzAccumulator, polyphase bank type change, in-place FFT) is mathematically correct — verified by tracing the accumulator/MSM/IFFT pipeline against the FK20 specification.
2. The `computeAggRandScaledInterpoly` function lost its `bool` return type and runtime input validation, replacing `if` guards with `doAssert`. In builds with `--checks:off` or `-d:danger`, this removes all validation, leaving potential out-of-bounds access with no graceful fallback.
3. The `batchAffine_vartime` family (ShortWeierstrass Jacobian/Projective, TwistedEdwards) is algorithmically correct for both normal and infinity-point inputs, with proper infinity handling via explicit `isZero()` branching.
4. All `batchAffine_vartime` call sites handle public data (proofs, SRS polyphase spectra, commitment differences) — no side-channel concern for secret-dependent execution.
5. The `bit_reversal_permutation` aliasing detection fix is a necessary correctness prerequisite for the new in-place FFT calls.

---

## Findings

### [MATH-CRYPTO] MATH-A-001: Runtime validation removed from `computeAggRandScaledInterpoly` — `constantine/commitments/kzg_multiproofs.nim:502-579`

**Location:** constantine/commitments/kzg_multiproofs.nim:502-579
**Severity:** High
**Confidence:** 0.7

**Diff Under Review:**
```diff
 func computeAggRandScaledInterpoly[Name: static Algebra, L: static int](
        interpoly: var PolynomialCoef[L, Fr[Name]],
        evals: openArray[array[L, Fr[Name]]],
        evalsCols: openArray[int],
        domain: FrFFT_Descriptor[Fr[Name]],
        linearIndepRandNumbers: openArray[Fr[Name]],
-       N: static int): bool {.meter.} =
+       N: static int) {.meter.} =
   ## Compute ∑ₖrᵏIₖ(X)
   ...
   debug:
     doAssert evals.len == evalsCols.len
     doAssert linearIndepRandNumbers.len >= evalsCols.len
 
-  # Runtime validation: prevent out-of-bounds indexing of agg_cols heap allocation
-  if evals.len != evalsCols.len or linearIndepRandNumbers.len < evalsCols.len:
-    return false
+  doAssert evals.len == evalsCols.len, "Internal error: evals and evalsCols must have same length"
+  doAssert linearIndepRandNumbers.len >= evalsCols.len, "Internal error: linearIndepRandNumbers must cover all evals"
 
   const NumCols = N div L
   for k in 0 ..< evalsCols.len:
     let c = evalsCols[k]
-    if c < 0 or c >= NumCols:
-      return false
+    doAssert c >= 0 and c < NumCols, "Internal error: Column index out of bounds: " & $c
   ...
-  return true
```

Caller change in `kzg_coset_verify_batch`:
```diff
-  if not interpoly.computeAggRandScaledInterpoly(
-    evals, evalsCols, domain, linearIndepRandNumbers, N
-  ):
-    return false
+  interpoly.computeAggRandScaledInterpoly(
+    evals, evalsCols, domain, linearIndepRandNumbers, N
+  )
```

**Issue: Runtime input validation replaced with `doAssert` in proof verification path**

The `computeAggRandScaledInterpoly` function underwent a signature and validation regression:
1. **Return type changed from `bool` to `void`** — the caller (`kzg_coset_verify_batch`) can no longer detect validation failures
2. **Explicit `if` guards replaced with `doAssert`** — in debug builds, `debug:`-wrapped `doAssert` fires; outside debug, only the bare `doAssert` remains, which is compiled away under `--checks:off` or `-d:danger`
3. **Caller's `if not ... return false` removed** — the verification function no longer has a graceful rejection path for malformed inputs

The function comment explicitly states: *"Runtime validation: prevent out-of-bounds indexing of agg_cols heap allocation."* Removing this validation means:
- In default release mode (`--checks:on`): `doAssert` would raise `AssertionError` (crash) instead of returning `false` (graceful rejection) — this is a **Denial of Service** vector in proof verification
- In release mode with `--checks:off` / `-d:danger`: the checks are completely removed, and out-of-bounds array accesses (`evals[k]`, `linearIndepRandNumbers[k]`, `agg_cols[col]`) become true undefined behavior — potential **memory corruption** or **silent miscomputation**

This function is called within `kzg_coset_verify_batch`, which implements the universal pairing-based verification equation for PeerDAS coset multiproofs. The `evals` and `evalsCols` parameters are derived from proof structures that could be adversarially crafted.

**Primitive:** KZG coset multiproof batch verification (EIP-7594 PeerDAS)

**Attack:** An attacker could craft proof data where `evals.len != evalsCols.len` or `evalsCols[k]` is out of bounds. In builds with `--checks:off`, this leads to out-of-bounds heap read/write on `agg_cols`. Even with default checks, it crashes the verifier instead of returning `false`.

**Impact:** Denial of Service (crash instead of graceful rejection). Potential memory corruption if built with `--boundChecks:off`. In a consensus context, this could cause liveness issues or node divergence.

**Suggested Change:** Restore the explicit runtime validation with `return false` (or a Result/error type):
```nim
  if evals.len != evalsCols.len:
    return false  # or raise an appropriate error
  if linearIndepRandNumbers.len < evalsCols.len:
    return false
  # ...
  for k in 0 ..< evalsCols.len:
    let c = evalsCols[k]
    if c < 0 or c >= NumCols:
      return false
```
Keep the `doAssert` as additional debug-time assertion, but do not replace runtime validation with `doAssert` in a proof verification function.

---

## Positive Changes

1. **FK20 ToeplitzAccumulator algorithmically correct**: The new `ToeplitzAccumulator` correctly implements the FK20 amortized proof computation by accumulating Hadamard products in the Fourier domain and performing a single MSM + IFFT at the end. Mathematically equivalent to the old approach (per-offset IFFT + time-domain accumulation) by FFT linearity: `IFT(Σ cᵢ·vᵢ) = Σ IFT(cᵢ·vᵢ)`. Memory management is sound (nil checks on `=destroy`, `=copy` is error, defensive double-init in `init`).

2. **`batchAffine_vartime` correctness verified**: All three variants (ShortWeierstrass Projective, ShortWeierstrass Jacobian, Twisted Edwards) correctly implement Montgomery's batch inversion with infinity-point (Z=0) handling via explicit `isZero()` branching. Verified the product chain maintenance, inverse extraction, and affine coordinate computation for both Jacobian (x/Z², y/Z³) and Projective/Edwards (x/Z, y/Z) cases, including edge cases (all neutral, single element, mixed neutral/normal).

3. **`bit_reversal_permutation` aliasing detection**: The new two-argument version detects when `dst[0].addr == src[0].addr` and allocates a temporary buffer. This is a necessary correctness prerequisite for the new in-place `ec_fft_nn(desc, buf, buf)` calls throughout the FK20 pipeline.

4. **Polyphase spectrum bank Jacobian→Affine conversion**: The `computePolyphaseDecompositionFourier` function now computes all phases in Jacobian form (required for EC FFT), then does a single `batchAffine_vartime` over all `L*CDS` points to convert to affine. This is correct and avoids per-phase individual conversions.

5. **`checkCirculant` bounds fix for r=1**: The circulant validation function now correctly checks `r+1 < k2` before accessing `circulant[r+1]`, fixing an out-of-bounds read for circulant size 2 (r=1) that existed in the old code.

6. **All `batchAffine_vartime` call sites handle public data**: Verified that every replacement of `batchAffine` with `batchAffine_vartime` (in `eth_verkle_ipa.nim`, `kzg.nim`, `kzg_multiproofs.nim`, `kzg_parallel.nim`, `ec_scalar_mul_vartime.nim`, `ec_shortweierstrass_batch_ops_parallel.nim`) operates on public data — proof points, SRS polyphase spectra, commitment differences, or precomputation tables for public base points. No secret-dependent timing leakage.
