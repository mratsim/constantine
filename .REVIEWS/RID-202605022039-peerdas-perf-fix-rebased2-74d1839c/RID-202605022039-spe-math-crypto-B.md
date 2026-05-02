---
**Branch:** `master` → `peerdas-perf-fix-rebased2` (commit `74d1839c`)
**Diff file:** `.REVIEWS/RID-202605022039-peerdas-perf-fix-rebased2-74d1839c/RID-202605022039-changes_under_review.diff`
**Date:** 2026-05-02
**Reviewer:** Math-Crypto Engineer (Pass B)
**Scope:** PeerDAS performance optimization — new `batchAffine_vartime` functions, `ToeplitzAccumulator` replacing `toeplitzMatVecMulPreFFT`, polyphase spectrum bank format change (Jacobian → Affine), in-place FFT operations, `Alloca` tag removal from FFT functions
**Focus:** Elliptic curve batch operations, FFT correctness, Toeplitz/FK20 linear algebra, vartime safety, memory safety in error paths
---

# Math-Crypto Review (Pass B)

## Summary

| ID | Severity | Confidence | File | Issue |
|----|----------|------------|------|-------|
| (none) | — | — | — | — |

**Key takeaways:**
1. All `batchAffine_vartime` invocations operate exclusively on **public data** (KZG proofs, IPA challenges, commitments, batch verification intermediates) — no secret-dependent execution paths introduced.
2. The new `ToeplitzAccumulator` is **mathematically equivalent** to the original FK20 `toeplitzMatVecMulPreFFT` loop: it reorganizes the computation from "L × (Hadamard + IFFT + accumulate)" to "L × (FFT + store transposed) → 1 × (MSM + IFFT)", yielding the same convolution result.
3. The polyphase spectrum bank format change (Jacobian → Affine storage) is a **pure storage optimization** — the FFT is still computed in Jacobian form, then batch-converted to affine once via a single `batchAffine_vartime(L*CDS)`. This saves `3*L*CDS` multiplications vs per-phase conversion.
4. Memory safety in the new `ToeplitzAccumulator` and `toeplitzMatVecMul` error paths is correct: all heap allocations are tracked via nil-checked pointers and freed in cleanup sections.
5. The `bit_reversal_permutation` aliasing detection (`dst[0].addr == src[0].addr`) correctly protects in-place FFT operations from data corruption.

## Detailed Analysis

### 1. `batchAffine_vartime` Correctness

Three new variable-time batch affine conversion functions were added:

- **`batchAffine_vartime` for Projective → Affine** (Short Weierstrass): Lines 185–260 in `ec_shortweierstrass_batch_ops.nim`
  - Forward phase: accumulates product of z-coordinates, skipping z=0 via `if zero(i).bool():` branching
  - Single `inv_vartime` on the accumulated product
  - Backward phase: extracts `1/z_i` from chain, computes `x * (1/z_i)`, `y * (1/z_i)`
  - **Verified correct**: standard Montgomery batch inversion with early returns for infinity points

- **`batchAffine_vartime` for Jacobian → Affine** (Short Weierstrass): Lines 262–344
  - Same forward/backward structure as Projective
  - Additional Jacobian correction: `invi2.square(invi)` for z⁻², `invi.prod(invi, invi2)` for z⁻³
  - Affine x = `x * z⁻²`, affine y = `y * z⁻³`
  - **Verified correct**: the z²/z³ derivation is standard for Jacobian-to-affine conversion
  - `lazyReduce` flags: all intermediate operations use `lazyReduce = true` to defer modular reduction; the final coordinate `prod` calls implicitly ensure reduced output (standard field arithmetic invariant)

- **`batchAffine_vartime` for Twisted Edwards** (Projective → Affine): Lines 98–170 in `ec_twistededwards_batch_ops.nim`
  - Identical algorithm to Short Weierstrass Projective (Twisted Edwards uses the same z-coordinate relationship)
  - **Verified correct**

**Edge case analysis** (all verified):
- N=0: guarded by `if N <= 0: return`
- N=1: forward phase sets `affs[0].x = projs[0].z` (or `setOne()` if z=0); backward phase correctly computes affine
- All points at infinity: product = 1 (since z=0 is replaced by 1 in the chain); `inv_vartime(1) = 1`; all output points correctly set to neutral
- Mixed infinity/finite: the chain correctly maintains the product of only finite z values; backward phase correctly identifies each point's status

### 2. Vartime Safety Assessment

**All `batchAffine_vartime` calls in this diff process exclusively public data:**

| Call Site | Data Processed | Secret? |
|-----------|---------------|---------|
| `eth_verkle_ipa.nim:568` | IPA proof L/R commitments | No (public) |
| `eth_verkle_ipa.nim:577` | IPA generator points after scalar mul | No (public) |
| `eth_verkle_ipa.nim:586` | IPA commitment aggregation | No (public) |
| `kzg.nim:598` | Batch verification intermediate `C - [e]G` | No (public) |
| `kzg_parallel.nim:167` | Same as above, parallel path | No (public) |
| `kzg_multiproofs.nim:364` | Polyphase spectrum bank (SRS-derived) | No (public) |
| `kzg_multiproofs.nim:458` | FK20 proof output points | No (public) |
| `ec_scalar_mul_vartime.nim:999` | wNAF precomputation table (base point is public) | No (already vartime context) |
| `ec_shortweierstrass_batch_ops_parallel.nim:224` | Parallel chunk results (public) | No (public) |

No secret-dependent data flows through the new variable-time paths. The `{.tags:[VarTime]}` markers correctly annotate these functions.

### 3. `ToeplitzAccumulator` Mathematical Correctness

The old FK20 algorithm (`toeplitzMatVecMulPreFFT`):
```
For each offset in 0..L-1:
    cFft = FFT(circulant)                        // Fr field elements
    u[i] += vFft[i] * cFft[i]                    // scalar × EC point
IFFT(u) → output
```

The new `ToeplitzAccumulator`:
```
For each offset in 0..L-1:
    FFT(circulant) → stored in coeffs[:, offset]  // transposed layout
    vFft → stored in points[:, offset]            // transposed layout

For each i in 0..size-1:
    output[i] = MSM(coeffs[i, :], points[i, :])   // Σ c * p
IFFT(output) → output
```

**Equivalence proof**:
- Old per-element: `output[i] = Σ_offset (circulant_fft[i]_offset × vFft[i]_offset)` (Hadamard then IFFT)
- New per-element: `output[i] = Σ_offset (cFft[i][offset] × vFft[i][offset])` (MSM)
- Both compute `Σ_offset cFft[i][offset] · vFft[i][offset]` — identical mathematical expression
- The Hadamard product followed by IFFT in the old code, and the MSM followed by IFFT in the new code, produce the same result

**Memory layout correctness**:
- `coeffs` buffer: `[size * L]` elements, indexed as `coeffs[i * L + offset]`
- `points` buffer: `[size * L]` elements, indexed as `points[i * L + offset]`
- In `finish`, `pointsPtr = cast[ptr UncheckedArray[ECaff]](addr ctx.points[i * ctx.L])` gives L consecutive affine points for position i
- `multiScalarMul_vartime(scalars, pointsPtr, ctx.L)` correctly computes the MSM

### 4. `toeplitzMatVecMul` Equivalence

The high-level `toeplitzMatVecMul` function was rewritten to use `ToeplitzAccumulator`:

- Old: zero-extend v → FFT → toeplitzMatVecMulPreFFT (FFT circulant + Hadamard + IFFT) → truncate
- New: zero-extend v → FFT (in-place) → batchAffine → ToeplitzAccumulator(accumulate + finish) → truncate

Both paths:
1. Zero-extend input vector to length 2n
2. FFT of extended vector (EC points)
3. FFT of circulant (field elements)
4. Pointwise scalar multiplication (Hadamard / MSM)
5. IFFT → convolution result
6. Truncate to first n elements

**Identical mathematical result**.

### 5. `kzg_coset_prove` Correctness

The new implementation:
1. Initializes `ToeplitzAccumulator[CDS, L]`
2. For each offset: makes circulant matrix, calls `accum.accumulate(circulant, polyphaseSpectrumBank[offset])`
3. `accum.finish(u)` → MSM + IFFT → u contains convolution result in Jacobian
4. Zero upper half: `u[CDSdiv2..CDS] = neutral`
5. In-place FFT: `ec_fft_nn(u, u)` → proofs in Jacobian
6. `batchAffine_vartime(proofs, u)` → affine output

**Verified**: This matches the FK20 algorithm's Phase 1 (Toeplitz convolution) + Phase 2 (zero upper half + FFT + affine conversion). The in-place FFT at step 5 is safe because `u` is freshly allocated and not shared.

### 6. Polyphase Spectrum Bank Change (Jacobian → Affine)

The SRS context's `polyphaseSpectrumBank` changed from `array[L, array[CDS, EC_ShortW_Jac]]` to `array[L, array[CDS, EC_ShortW_Aff]]`.

**How correctness is maintained**:
- `computePolyphaseDecompositionFourier` computes all L phases in Jacobian form internally (temporary heap allocation)
- After all L FFTs complete, a single `batchAffine_vartime(L * CDS)` converts the entire bank to affine
- The `kzg_coset_prove` accumulator's `ECaff` type parameter matches the affine bank

**Storage savings**: Each G1 point drops from 3 × 48 = 144 bytes (Jacobian) to 2 × 48 = 96 bytes (Affine), saving ~384 KB for the full bank (64 × 128 × 48 = 393,216 bytes).

### 7. In-place FFT Operations

Multiple functions now use in-place FFT:
- `computePolyphaseDecompositionFourierOffset`: `ec_fft_nn(polyphaseSpectrum, polyphaseSpectrum)`
- `eth_peerdas.nim`: `fft_desc.ifft_rn(extended_times_zero, extended_times_zero)`
- `eth_peerdas.nim`: `fft_desc.coset_fft_nr(ext_eval_over_coset, extended_times_zero, cosetShift)`
- `kzg_coset_prove`: `ec_fft_nn(u, u)`
- `toeplitzMatVecMul`: `ec_fft_nn(vExt, vExt)`
- `ToeplitzAccumulator.finish`: `ec_ifft_nn(ctx.ecFftDesc, output, output)`

**Aliasing safety**: The new `bit_reversal_permutation` function (line 307–322 in `fft_common.nim`) detects aliasing via `dst[0].addr == src[0].addr` and allocates a temporary buffer when needed. The in-place FFT implementations (`ec_fft_nn`, `ec_ifft_nn`, etc.) route through this protected path.

### 8. Memory Safety in Error Paths

**`toeplitzMatVecMul`**: Uses labeled block pattern:
```nim
block HappyPath:
    check HappyPath, ec_fft_nn(...)
    vExtFftAff = allocHeapArrayAligned(...)
    check HappyPath, acc.init(...)
    ifftResult = allocHeapArrayAligned(...)
    check HappyPath, acc.finish(...)
if vExtFftAff != nil: freeHeapAligned(vExtFftAff)
if ifftResult != nil: freeHeapAligned(ifftResult)
freeHeapAligned(vExt)
```
All allocations are tracked and freed. **Correct.**

**`ToeplitzAccumulator`**: `=destroy` procedure nil-checks all three pointer fields before freeing. `init` defensively frees existing allocations before allocating new ones. **Correct.**

### 9. Error Handling Change in `computeAggRandScaledInterpoly`

The function changed from returning `bool` (with `return false` on validation failure) to returning `void` (with `doAssert` on validation failure):

**Old**:
```nim
if evals.len != evalsCols.len or linearIndepRandNumbers.len < evalsCols.len:
    return false
if c < 0 or c >= NumCols:
    return false
```

**New**:
```nim
doAssert evals.len == evalsCols.len, "..."
doAssert linearIndepRandNumbers.len >= evalsCols.len, "..."
doAssert c >= 0 and c < NumCols, "..."
```

This is acceptable because:
1. The caller (`kzg_coset_verify_batch`) already validates all lengths before calling
2. The function is called in a controlled context where input length mismatches would be bugs, not adversarial inputs
3. The `doAssert` will panic in debug builds (exposing the bug) and be optimized away in release builds (trusting the caller's validation)

### 10. `Alloca` Tag Removal

The `Alloca` tag was removed from all FFT functions. This is correct because the iterative FFT implementations no longer use `allocStackArray` — the recursive implementations (which did use stack arrays) have been replaced by iterative versions. The remaining `Alloca` tags are in functions like `accum_half_vartime` and `accumSum_chunk_vartime` that still use `allocStackArray`.

## Positive Changes

1. **ToeplitzAccumulator reorganization**: The shift from per-offset IFFT to batch MSM + single IFFT is a sound optimization that reduces the number of expensive EC IFFT operations from L to 1.

2. **Polyphase spectrum bank affine storage**: Saving 393 KB of SRS memory and 3×64×128 = 24,576 fewer field multiplications per setup is a meaningful improvement.

3. **`batchAffine_vartime` with infinity-point awareness**: The vartime versions correctly handle z=0 coordinates by maintaining the product chain and skipping infinity points, matching the constant-time behavior on all non-secret inputs.

4. **Aliasing-safe `bit_reversal_permutation`**: The new two-argument version with automatic aliasing detection is a robust addition that prevents a class of subtle data corruption bugs.

5. **Comprehensive test coverage**: The diff adds new tests for `ToeplitzAccumulator.init` error paths, `ToeplitzAccumulator.finish` error paths, `checkCirculant` with r=1 edge case, and vartime batch affine conversion across all curve types (BN254, BLS12-381, Bandersnatch, Banderwagon).

No findings.
