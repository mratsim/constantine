---
**Branch:** `master` → `peerdas-perf-fix-rebased2` (commit `81784ecd`)
**Diff file:** `.REVIEWS/RID-202605022113-peerdas-perf-fix-rebased2-81784ecd/RID-202605022113-changes_under_review.diff`
**Date:** 2026-05-02
**Reviewer:** Math-Crypto Engineer (Pass B)
**Scope:** FK20 multiproof accumulator redesign, batch affine conversion vartime variants, polyphase spectrum bank coordinate change (Jacobian→Affine), Toeplitz API refactoring, bit reversal permutation aliasing fix
**Focus:** Elliptic curves, pairings, ZK proofs, FFTs, field arithmetic, protocol correctness, side-channels
---

# Math-Crypto Review (Pass B)

## Summary

| ID | Severity | Confidence | File | Issue |
|----|----------|------------|------|-------|
| MATH-B-001 | Medium | 0.9 | `constantine/commitments/kzg_multiproofs.nim:227-228` | `computePolyphaseDecompositionFourierOffset` invariant assertion removed — relies on static assertion at caller |
| MATH-B-002 | Medium | 0.8 | `constantine/math/elliptic/ec_shortweierstrass_batch_ops.nim:262-334` | `batchAffine_vartime` for Jacobian has distinct branching pattern vs original `batchAffine` — correct but divergent algorithm |
| MATH-B-003 | Low | 0.9 | `constantine/eth_eip7594_peerdas.nim:568-580` | `kzg_coset_verify_batch` caller chain: `evalsCols` from `cell_indices` (network input) — single validation layer |
| MATH-B-004 | Low | 0.9 | `constantine/math/matrix/toeplitz.nim:359` | `toeplitzMatVecMul` uses `batchAffine_vartime` on projective→affine conversion of FFT output — ~128/256 neutral points in batch |

**Key takeaways:**
1. **FK20 `ToeplitzAccumulator` mathematically correct**: The accumulator correctly implements the FK20 amortized convolution via transposed storage, per-position MSM, and amortized IFFT. Verified `T·v = IFFT(FFT(circulant) ⊙ FFT(v))` identity preservation.
2. **All `batchAffine_vartime` call sites process public data**: KZG proofs, IPA proofs, verification intermediates, polyphase spectra — no secret-dependent Z-coordinates. No exploitable timing side-channels.
3. **Jacobian batchAffine_vartime correctness verified**: Algebraic derivation confirms `x/Z²` and `y/Z³` conversions match Montgomery batch inversion for all infinity-point patterns.
4. **Polyphase bank conversion (Jacobian→Affine) handles ~50% infinity points correctly**: Second half of each phase set to neutral; vartime batchAffine's branching on Z=0 is safe for these public data points.
5. **Defense-in-depth regression**: Multiple layers of input validation were consolidated into `doAssert` assertions, but the top-layer caller (`kzg_coset_verify_batch`) retains `if ... return false` guards that cover the same conditions. Risk is low but structural.

## Findings

### [MATH-CRYPTO] MATH-B-001: `computePolyphaseDecompositionFourierOffset` runtime assertion removed — parameter validity now depends on caller's static assertion

**Location:** `constantine/commitments/kzg_multiproofs.nim:227-228`
**Severity:** Medium
**Confidence:** 0.9

**Diff Under Review:**
```diff
-  const L = N div CDSdiv2
-
-  static:
-    doAssert CDS.isPowerOf2_vartime(), "CDS must be a power of two"
-    doAssert CDS >= 4, "CDS must be >= 4 for the polyphase stride to stay in range"
+  const L = (2 * N) div CDS
+  static: doAssert CDS.isPowerOf2_vartime(), "CDS must be a power of two"
   doAssert ecfft_desc.order >= CDS, "EC FFT descriptor order must be >= CDS"
-  doAssert N >= L + 1 + offset, "N must be >= L + 1 + offset for valid polyphase extraction"
```

**Issue:** The runtime assertion `N >= L + 1 + offset` was removed from `computePolyphaseDecompositionFourierOffset`. This assertion validated that the polyphase extraction loop index `j` stays within bounds of `powers_of_tau.coefs` (length `N`). The extraction starts at `j = N - L - 1 - offset` and decrements by `L` for `CDSdiv2-1` iterations. Without this check, if `N` is too small relative to `L` and `offset`, the starting index could be negative, causing out-of-bounds array access.

However, the caller `computePolyphaseDecompositionFourier` enforces `static: doAssert CDS * L == 2 * N`, which for production parameters (N=4096, L=64, CDS=128) implies `L = 2N/CDS = 64` and `N = L*CDS/2 = 4096`. Under this invariant, `N >= L + 1 + offset` holds for all `offset < L` since `N = L*CDS/2` and `CDS/2 = 64 >> 1`.

The removed `doAssert CDS >= 4` was also a static-time check. Since `CDS * L == 2 * N` with `N >= 2048` and `L >= 2` implies `CDS >= 2*N/L`, the minimum CDS for valid parameters is already large enough.

**Primitive:** FK20 polyphase decomposition — Fourier-domain SRS preprocessing for Toeplitz matrix-vector multiplication.

**Attack:** Not exploitable with production PeerDAS parameters (CDS=128, L=64, N=4096). Could only trigger if someone instantiates with non-standard parameters where `N < L + 1 + offset`. The static assertion `CDS * L == 2 * N` at the call site provides compile-time protection.

**Impact:** In theory, a caller with non-standard parameters could trigger out-of-bounds reads on `powers_of_tau.coefs`. The `static` assertion makes this a compile-time catch, not a runtime vulnerability.

**Suggested Change:** The current approach is acceptable. The static assertion `CDS * L == 2 * N` at the call site is a stronger invariant that makes the per-offset runtime check redundant. Document this dependency in the function comment.

---

### [MATH-CRYPTO] MATH-B-002: `batchAffine_vartime` for Jacobian has distinct algorithmic path from original `batchAffine` — mathematically equivalent but structurally different branching

**Location:** `constantine/math/elliptic/ec_shortweierstrass_batch_ops.nim:262-334`
**Severity:** Low
**Confidence:** 0.9

**Diff Under Review:**
```diff
+func batchAffine_vartime*[F, G](
+       affs: ptr UncheckedArray[EC_ShortW_Aff[F, G]],
+       jacs: ptr UncheckedArray[EC_ShortW_Jac[F, G]],
+       N: int) {.tags:[VarTime], meter.} =
+  ...
+  for i in countdown(N-1, 1):
+    var invi {.noInit.}: F
+    if zero(i).bool():
+      affs[i].setNeutral()
+    else:
+      invi.prod(accInv, affs[i-1].x, lazyReduce = true)
+      accInv.prod(accInv, jacs[i].z, lazyReduce = true)
+      var invi2 {.noinit.}: F
+      invi2.square(invi, lazyReduce = true)
+      affs[i].x.prod(jacs[i].x, invi2)     # x/Z²
+      invi.prod(invi, invi2, lazyReduce = true)  # 1/Z³
+      affs[i].y.prod(jacs[i].y, invi)       # y/Z³
+
+  block: # tail
+    var invi2 {.noinit.}: F
+    if zero(0).bool():
+      affs[0].setNeutral()
+    else:
+      invi2.square(accInv, lazyReduce = true)
+      affs[0].x.prod(jacs[0].x, invi2)
+      accInv.prod(accInv, invi2, lazyReduce = true)
+      affs[0].y.prod(jacs[0].y, accInv)
```

**Issue:** The new `batchAffine_vartime` for Jacobian coordinates uses a distinct algorithm from the original constant-time `batchAffine`. Both compute Montgomery's batch inversion, but with different approaches to infinity point (Z=0) handling:

- **Original `batchAffine`**: Uses `SecretBool` zero-tracking with `allocStackArray(SecretBool, N)` and constant-time masking via `csetOne`/`csetZero`. Zero Z-coordinates are replaced with 1 in the product chain, and the final `invi` is zeroed via `csetZero` to skip affine conversion.
  
- **New `batchAffine_vartime`**: Uses explicit `if zero(i).bool()` branches with `SecretWord` zero-tracking stored in `affs[i].y.mres.limbs[0]`. Infinity points skip the product chain (multiply by 1) and output `setNeutral()` directly.

**Mathematical Verification of Correctness:**

For non-infinity points, the Jacobian-to-affine conversion requires:
- `x_aff = x_jac / Z²`
- `y_aff = y_jac / Z³`

The batch inversion computes `P = ∏ Z_i` (product of non-zero Zs), then `P⁻¹`. For point `i`:
- `invi = P⁻¹ · ∏_{j<i} Z_j = 1/Z_i`
- `invi² = 1/Z_i²` → used for x conversion
- `invi³ = 1/Z_i³` → used for y conversion

The new code computes `invi2 = invi²`, then `invi₃ = invi · invi² = invi³`, which correctly gives both `1/Z²` and `1/Z³`. This is algebraically equivalent to the original code's approach where `accInv · projs[i].z` implicitly accumulates to `1/Z³` through the product chain update.

For infinity points (Z=0), the new code outputs `setNeutral()` which sets `(x,y) = (0,0)` — the correct affine representation of the point at infinity for short Weierstrass curves.

**Primitive:** Montgomery's batch inversion for Jacobian-to-affine coordinate conversion.

**Attack:** No attack — the algorithm is mathematically correct. This is flagged because the structural difference between the constant-time and variable-time versions could introduce subtle bugs during maintenance if they diverge.

**Impact:** Low. The algorithm is correct but uses different code structure than the constant-time version. Future maintenance on one version may not be reflected in the other.

**Suggested Change:** Add a cross-reference comment between the constant-time and variable-time versions noting they implement the same Montgomery batch inversion but with different zero-handling strategies. Consider extracting the core inversion logic into a shared helper to reduce duplication.

---

### [MATH-CRYPTO] MATH-B-003: Verification input chain — `evalsCols` from `cell_indices` passes through single validation layer before reaching `computeAggRandScaledInterpoly`

**Location:** `constantine/eth_eip7594_peerdas.nim:568-580`
**Severity:** Low
**Confidence:** 0.9

**Diff Under Review:**
```nim
# eth_eip7594_peerdas.nim — the entry point for DAS verification
    let verifyStatus = kzg_coset_verify_batch(
      uniqueCommitments = uniqueCommitments.toOpenArray(numUniqueCommitments),
      commitmentIdx = commitmentIdx.toOpenArray(numCells),
      proofs = proofs.toOpenArray(numCells),
      evals = cosets_evals.toOpenArray(numCells),
      evalsCols = evalsCols.toOpenArray(numCells),  # ← from cell_indices
      ...
    )
```

**Issue:** Tracing the full verification chain from the DAS entry point (`eth_eip7594_peerdas.nim`) through to `computeAggRandScaledInterpoly`:

1. `cell_indices` (raw bytes from network, `CellIndex` type) → converted to `int` in `evalsCols`
2. `evalsCols` passed to `kzg_coset_verify_batch` which validates: `c < 0 or c >= numCols` → `return false`
3. Inside `kzg_coset_verify_batch`, `evalsCols` passed to `computeAggRandScaledInterpoly`
4. `computeAggRandScaledInterpoly` now uses `doAssert c >= 0 and c < NumCols` (compile-away in release)

The single validation layer at step 2 is correct and sufficient for the current code. However, the column index `c` is used in `computeAggRandScaledInterpoly` to index into `agg_cols[c]` (a heap-allocated array of `NumCols` elements). If the validation at step 2 is ever weakened or bypassed, the `doAssert` at step 4 would be a no-op in release builds.

**Note:** The caller `kzg_coset_verify_batch` (line 663 in kzg_multiproofs.nim) already performs:
```nim
for k in 0 ..< proofs.len:
  let c = evalsCols[k]
  if c < 0 or c >= numCols:
    return false
```
This is a complete runtime guard that runs before `computeAggRandScaledInterpoly` is called. The `doAssert` inside `computeAggRandScaledInterpoly` is now redundant but serves as a catch for any future code paths.

**Primitive:** KZG coset multiproof verification — column index validation in sparse verification.

**Attack:** Not exploitable with current code. The validation in `kzg_coset_verify_batch` provides complete coverage.

**Impact:** Low — informational finding. The defense-in-depth regression (bool→void + doAssert) is mitigated by caller-side validation, but the structural change means future maintenance could introduce gaps.

**Suggested Change:** No code change needed. Document the dependency between caller-side validation and inner function's `doAssert` assertions. Consider using `assert` (runtime in release) instead of `doAssert` for the column bounds check if defense-in-depth is desired.

---

### [MATH-CRYPTO] MATH-B-004: `toeplitzMatVecMul` degenerate L=1 accumulator — correctness with neutral-point-rich FFT output

**Location:** `constantine/math/matrix/toeplitz.nim:359`
**Severity:** Low
**Confidence:** 0.9

**Diff Under Review:**
```nim
proc toeplitzMatVecMul*[EC, F](...): ToeplitzStatus {.meter.} =
  ...
  batchAffine_vartime(vExtFftAff, vExt, n2)  # ← n2 = 2*n points, half are neutral

  check HappyPath, acc.init(frFftDesc, ecFftDesc, n2, L = 1)
  check HappyPath, acc.accumulate(circulant, vExtFftAff.toOpenArray(n2))

  ifftResult = allocHeapArrayAligned(EC, n2, 64)
  check HappyPath, acc.finish(ifftResult.toOpenArray(n2))
```

**Issue:** The `toeplitzMatVecMul` procedure uses the `ToeplitzAccumulator` in a degenerate case with `L = 1`. The input vector `vExt` is zero-extended: the first `n` elements are the input points, and elements `n` to `2n-1` are set to neutral (infinity). After FFT, these neutral points become some valid EC points in the frequency domain, but their structure is determined by the zero-extension pattern.

The `batchAffine_vartime(vExtFftAff, vExt, n2)` converts the post-FFT Jacobian points to affine. Since the FFT of a zero-extended vector has specific structure (the upper half of the FFT output represents the zero-padded portion), these points are NOT neutral after FFT — the FFT mixes all inputs. Therefore, `batchAffine_vartime` processes all `n2` points as potentially non-neutral, and the vartime branching on Z=0 would rarely trigger.

This is correct behavior — the FFT output points are all legitimate (non-infinity) EC points in general position.

However, the use of `L = 1` means the accumulator:
1. Allocates `size * 1 = n2` slots for both `coeffs` and `points`
2. Performs exactly one `accumulate` call
3. In `finish`, performs `n2` separate MSM operations with `ctx.L = 1` scalar each

The `multiScalarMul_vartime(scalars, pointsPtr, ctx.L)` with `L=1` degenerates to a single scalar multiplication: `output[i] = scalars[0] * points[0]`. This is mathematically correct but may be less efficient than a direct `scalarMul_vartime` call since `multiScalarMul_vartime` has overhead for the MSM setup (windowed precomputation, etc.).

**Primitive:** Toeplitz matrix-vector multiplication via circulant embedding — single-phase accumulator.

**Attack:** No attack — mathematically correct. Efficiency concern only.

**Impact:** Low. The `toeplitzMatVecMul` function is used in tests and general-purpose Toeplitz multiplication (not FK20 proving). The L=1 case is mathematically equivalent to the old `toeplitzMatVecMulPreFFT` but with potentially different performance characteristics.

**Suggested Change:** Consider an optimization for `L=1`: in `ToeplitzAccumulator.finish`, if `ctx.L == 1`, use direct `scalarMul_vartime` instead of `multiScalarMul_vartime` to avoid MSM overhead. Or add a fast path in `toeplitzMatVecMul` that bypasses the accumulator entirely for the single-phase case.

---

## Positive Changes

1. **`batchAffine_vartime` infinity handling verified across all four coordinate systems**: The variable-time implementations for Short Weierstrass (Projective and Jacobian) and Twisted Edwards (Projective) correctly handle points at infinity by maintaining the Montgomery product chain with identity multiplication (multiply by 1 instead of Z=0) and outputting `setNeutral()` for infinity points. Verified algebraic equivalence to the original constant-time implementations.

2. **FK20 accumulator redesign is mathematically sound**: The `ToeplitzAccumulator` correctly implements the FK20 amortized proof algorithm:
   - Phase 1: Accumulates FFT of circulant coefficients (transposed storage: `coeffs[i*L + offset]`) and affine polyphase spectrum points (`points[i*L + offset]`) in Fourier domain
   - Phase 2: Per-position MSM (`output[i] = Σ_{offset=0}^{L-1} coeffs[i*L+offset] * points[i*L+offset]`)
   - Phase 3: Single amortized EC IFFT
   This preserves the Toeplitz convolution identity `T·v = IFFT(FFT(circulant) ⊙ FFT(v))` as specified in FK20 Proposition 4.

3. **Polyphase spectrum bank storage optimization correct**: Converting from `EC_ShortW_Jac` to `EC_ShortW_Aff` for the `polyphaseSpectrumBank` eliminates per-prove Jacobian→affine conversions. The single `batchAffine_vartime` at the end of `computePolyphaseDecompositionFourier` (processing L×CDS points with ~50% being neutral) is correctly placed and handles infinity points.

4. **In-place FFT operations are safe with aliasing detection**: The new `bit_reversal_permutation` correctly detects dst/src aliasing via `dst[0].addr == src[0].addr` and uses a temporary buffer. All in-place FFT calls (e.g., `ec_fft_nn(u, u)`, `ifft_rn(buf, buf)`) are therefore safe.

5. **`N <= 0` defensive guard added to all `batchAffine` variants**: Prevents degenerate case bugs and out-of-bounds access when batch size is zero or negative. Good defensive programming.

6. **`checkCirculant` edge case fix for r=1**: The zero-padding check now properly bounds-checks before accessing `circulant[r+1]` when `r+1` may exceed the circulant length (k2). This prevents false negatives in circulant validation for small matrix sizes.

7. **Comprehensive test coverage for vartime conversions**: New tests cover all-neutral batches, single-element batches, mixed infinity/finite batches, and varied batch sizes (2, 16) across BLS12-381, BN254, Bandersnatch, and Banderwagon curves. Both Short Weierstrass and Twisted Edwards forms tested.

8. **Memory safety in `ToeplitzAccumulator`**: The type has proper `=destroy` (nil-checked heap free for all three buffers), `=copy` (marked as `{.error.}` to prevent accidental shallow copy), and defensive `init` that frees existing allocations on re-initialization.
