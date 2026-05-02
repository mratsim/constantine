---
**Branch:** `master` → `peerdas-perf-fix-rebased2` (commit `81784ecd`)
**Diff file:** `.REVIEWS/RID-202605022113-peerdas-perf-fix-rebased2-81784ecd/RID-202605022113-changes_under_review.diff`
**Date:** 2026-05-02
**Reviewer:** Performance Analyst (Pass A)
**Scope:** PeerDAS FK20 multiproof performance optimization — ToeplitzAccumulator redesign, batchAffine_vartime, in-place FFTs, polyphase spectrum bank format change
**Focus:** Algorithmic complexity, allocations, sync I/O, caching, data structures, hot paths
---

# Performance Review (Pass A)

## Summary

| ID | Severity | Confidence | File | Issue |
|----|----------|------------|------|-------|
| PERF-A-001 | Medium | 0.8 | `constantine/math/matrix/toeplitz.nim:263-265` | Strided writes in `ToeplitzAccumulator.accumulate` hot loop |
| PERF-A-002 | Medium | 0.7 | `constantine/math/polynomials/fft_common.nim:307-322` | New `bit_reversal_permutation` aliasing path adds alloc+copy on in-place FFT |
| PERF-A-003 | Low | 0.7 | `constantine/math/matrix/toeplitz.nim:308-378` | `toeplitzMatVecMul` standalone path adds batchAffine + extra allocations |
| PERF-A-004 | Informational | 0.9 | `constantine/math/matrix/toeplitz.nim:188-196` | `ToeplitzAccumulator` peak memory ~135KB vs old ~20KB per FK20 call |

**Key takeaways:**
1. The overall FK20 prove path is substantially improved (MSM batching, 1× IFFT vs 64×, polyphase in affine form, single batch conversion at setup).
2. The `ToeplitzAccumulator.accumulate` hot loop has a strided-write pattern that could benefit from local buffering for L1 cache efficiency.
3. The new aliasing-aware `bit_reversal_permutation` adds a temporary alloc+copy on in-place FFT calls, but the net effect is positive overall since the number of IFFTs dropped from 64 to 1.
4. The standalone `toeplitzMatVecMul` (non-FK20 usage) regresses in allocations and adds a batchAffine step.

## Findings

### [PERF] PERF-A-001: Strided writes in `ToeplitzAccumulator.accumulate` hot loop — toeplitz.nim:263-265

**Location:** `constantine/math/matrix/toeplitz.nim:263-265`
**Severity:** Medium
**Confidence:** 0.8

**Diff Under Review:**
```diff
+proc accumulate*[EC, ECaff, F](
+  ctx: var ToeplitzAccumulator[EC, ECaff, F],
+  circulant: openArray[F],
+  vFft: openArray[ECaff]
+): ToeplitzStatus {.raises: [], meter.} =
+  ## Accumulate FFT(circulant) and vFft for position ctx.offset
+  let n = ctx.size
+  ...
+    # Store transposed: coeffs[i*L + offset] and points[i*L + offset]
+    for i in 0 ..< n:
+      ctx.coeffs[i * ctx.L + ctx.offset] = ctx.scratchScalars[i]
+      ctx.points[i * ctx.L + ctx.offset] = vFft[i]
```

**Issue:** **Strided writes in FK20 hot loop cause cache line thrashing**

The `accumulate` method writes to `ctx.coeffs[i * ctx.L + ctx.offset]` and `ctx.points[i * ctx.L + ctx.offset]` with stride `ctx.L`. For PeerDAS production parameters (CDS=128, L=64), this means:
- The `coeffs` buffer is 128 × 64 = 8,192 field elements (256 KB)
- The `points` buffer is 128 × 64 = 8,192 affine EC points (~3 MB)

Each write has stride `L` (64 elements). For the coeffs buffer: consecutive writes are 64 × 32 = 2,048 bytes apart — crossing 32 cache lines between writes. For the points buffer: consecutive writes are 64 × 48 = 3,072 bytes apart — crossing 48 cache lines.

This function runs in a tight loop of L=64 iterations per `kzg_coset_prove` call. The strided access pattern causes repeated cache line fills and evictions, defeating L1/L2 cache utilization.

**Impact:** At realistic PeerDAS workload (1 blob = 1 kzg_coset_prove call), each `accumulate` call does 128 strided writes to a 3MB buffer. With 64 iterations, this touches ~8,192 distinct cache lines per call. The strided pattern could add 10-30% overhead vs sequential writes on the accumulate phase.

**Suggested Change:** Buffer the transposed writes in local arrays, then copy sequentially:
```nim
# In accumulate():
var localCoeffs {.noInit.}: array[CDS, F]  # or size-based
var localPoints {.noInit.}: array[CDS, ECaff]
for i in 0 ..< n:
  localCoeffs[i] = ctx.scratchScalars[i]
  localPoints[i] = vFft[i]

# Sequential copy to transposed layout (better cache behavior)
for i in 0 ..< n:
  ctx.coeffs[i * ctx.L + ctx.offset] = localCoeffs[i]
  ctx.points[i * ctx.L + ctx.offset] = localPoints[i]
```
Or use the new `transpose.nim` module for the bulk transpose at a higher level.

---

### [PERF] PERF-A-002: `bit_reversal_permutation` aliasing path adds alloc+copy on in-place FFT — fft_common.nim:307-322

**Location:** `constantine/math/polynomials/fft_common.nim:307-322`
**Severity:** Medium
**Confidence:** 0.7

**Diff Under Review:**
```diff
-func bit_reversal_permutation*[T](dst{.noalias.}: var openArray[T], src{.noalias.}: openArray[T]) {.inline.} =
-  ## Out-of-place bit reversal permutation.
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

**Issue:** **Aliasing detection adds heap allocation + copy on in-place FFT calls**

The new `bit_reversal_permutation(dst, src)` function detects when `dst` and `src` alias, then allocates a temporary buffer, performs the permutation, and copies back. This is triggered whenever `ec_fft_nn` or `ec_ifft_nn` is called in-place (same buffer for input and output).

Call sites that trigger the aliasing path in this diff:
1. `ToeplitzAccumulator.finish()` → `ec_ifft_nn(ctx.ecFftDesc, output, output)` — CDS=128 EC points (8 KB alloc + copy)
2. `kzg_coset_prove()` → `ec_fft_nn(u, u)` — CDS=128 EC points (8 KB alloc + copy)
3. `computePolyphaseDecompositionFourierOffset()` → `ec_fft_nn(polyphaseSpectrum, polyphaseSpectrum)` — CDS=128 EC points per offset (8 KB × 64 offsets = 512 KB total alloc, but freed each iteration)
4. `toeplitzMatVecMul()` → `ec_fft_nn(ecFftDesc, vExt, vExt)` — 2×CDS=256 EC points (16 KB alloc + copy)

**Impact:** The aliasing overhead is per-FFT, but the total number of FFTs has dropped dramatically:
- **Old FK20 path:** 64× `ec_ifft_nn` per prove → 64× alloc+copy
- **New FK20 path:** 1× `ec_ifft_nn` per prove → 1× alloc+copy (net win: 63× fewer allocs)
- **Polyphase setup:** 64× `ec_fft_nn` per setup → 64× alloc+copy (neutral, same as before since it was always in-place for the Jacobian FFT)

Net impact on the FK20 prove hot path: **positive** (63 fewer allocations). The individual cost per call is negligible (~8KB copy = ~1μs on DDR4-3200).

**Suggested Change:** No change needed — the overall trade-off is beneficial. However, for the polyphase setup path (computePolyphaseDecompositionFourierOffset), consider keeping the pre-allocated `polyphaseComponent` buffer to avoid the temporary allocation in the aliasing path, since this runs 64 times during trusted setup.

---

### [PERF] PERF-A-003: `toeplitzMatVecMul` standalone path adds batchAffine + extra allocations — toeplitz.nim:308-378

**Location:** `constantine/math/matrix/toeplitz.nim:308-378`
**Severity:** Low
**Confidence:** 0.7

**Diff Under Review:**
```diff
-  let vExtFft = allocHeapArrayAligned(EC, n2, 64)
-  let status1 = ecFftDesc.ec_fft_nn(vExtFft.toOpenArray(n2), vExt.toOpenArray(n2))
+  # ec_fft_nn supports in-place operation — reuse vExt buffer
+  var vExtFftAff: ptr UncheckedArray[ECaff] = nil
+  var ifftResult: ptr UncheckedArray[EC] = nil
+  var acc: ToeplitzAccumulator[EC, ECaff, F]
+
+  block HappyPath:
+    check HappyPath, ec_fft_nn(ecFftDesc, vExt.toOpenArray(n2), vExt.toOpenArray(n2))
+
+    vExtFftAff = allocHeapArrayAligned(ECaff, n2, 64)
+    batchAffine_vartime(vExtFftAff, vExt, n2)
+
+    check HappyPath, acc.init(frFftDesc, ecFftDesc, n2, L = 1)
+    check HappyPath, acc.accumulate(circulant, vExtFftAff.toOpenArray(n2))
+
+    ifftResult = allocHeapArrayAligned(EC, n2, 64)
+    check HappyPath, acc.finish(ifftResult.toOpenArray(n2))
```

**Issue:** **Standalone `toeplitzMatVecMul` now adds a batchAffine conversion step and more heap allocations**

The old `toeplitzMatVecMul` delegated to `toeplitzMatVecMulPreFFT` with a pre-FFT'd vector. The new implementation uses `ToeplitzAccumulator`, which requires affine points. This adds:
1. **`vExtFftAff` allocation:** n2 affine EC points (256 × 48 = 12 KB for CDS=128)
2. **`batchAffine_vartime` call:** Converting 256 Jacobian points to affine (1 batch inversion + 256 field multiplications)
3. **`ifftResult` allocation:** n2 Jacobian EC points (256 × 64 = 16 KB for CDS=128)

**Impact:** This is a regression for the standalone `toeplitzMatVecMul` path (used in non-FK20 tests). The batchAffine_vartime on 256 points costs roughly 0.5-1ms. The extra allocations add ~28 KB of heap traffic per call. However, the FK20 path (`kzg_coset_prove`) uses `ToeplitzAccumulator` directly and does NOT go through `toeplitzMatVecMul`, so the production FK20 code path is unaffected by this regression.

**Suggested Change:** If standalone `toeplitzMatVecMul` is used in performance-sensitive code, add a code path that bypasses the accumulator for L=1 cases, or keep a separate `toeplitzMatVecMulPreFFT` for the non-accumulator path.

---

### [PERF] PERF-A-004: `ToeplitzAccumulator` peak memory ~135KB vs old ~20KB per FK20 call — toeplitz.nim:188-196, kzg_multiproofs.nim:426-427

**Location:** `constantine/math/matrix/toeplitz.nim:188-196`, `constantine/commitments/kzg_multiproofs.nim:426-427`
**Severity:** Informational
**Confidence:** 0.9

**Diff Under Review:**
```diff
+type
+  ToeplitzAccumulator*[EC, ECaff, F] = object
+    frFftDesc: FrFFT_Descriptor[F]
+    ecFftDesc: ECFFT_Descriptor[EC]
+    coeffs: ptr UncheckedArray[F]           # [size*L] transposed coeffs
+    points: ptr UncheckedArray[ECaff]       # [size*L] points for each position
+    scratchScalars: ptr UncheckedArray[F]   # [max(size,L)] union buffer
+    size: int
+    L: int
+    offset: int
```

**Issue:** **Peak per-call memory increased, but total allocation throughput decreased**

For PeerDAS parameters (CDS=128, L=64):

| Allocation | Old (per iteration, freed each) | New (upfront, freed once) |
|---|---|---|
| circulant | 128 × 32 B = 4 KB | 128 × 32 B = 4 KB |
| coeffs | N/A | 8192 × 32 B = 256 KB |
| points | N/A | 8192 × 48 B = 384 KB |
| scratchScalars | N/A | 128 × 32 B = 4 KB |
| per-iter FFT buffers | 3 × 4 KB = 12 KB | 0 (reuses scratch) |
| per-iter IFFT buffer | 4 KB | 0 |
| **Peak (simultaneous)** | ~20 KB | ~652 KB |
| **Total allocated over call** | ~256 KB | ~652 KB |

Wait — let me recalculate. The new buffers are allocated once:
- `coeffs`: 8192 × 32 = 256 KB
- `points`: 8192 × 48 = 384 KB  
- `scratchScalars`: 128 × 32 = 4 KB
- `circulant`: 4 KB
- `u` (Jacobian output): 128 × 64 = 8 KB
Total: ~656 KB allocated once per `kzg_coset_prove` call.

Old code allocated ~20 KB per iteration × 64 iterations = ~1.28 MB total allocated (but freed each iteration, so peak was ~20 KB).

**Impact:** Peak memory per call increased from ~20 KB to ~656 KB. For a single concurrent `kzg_coset_prove` call, this is negligible. With parallel proving (e.g., proving multiple blobs simultaneously), the increased per-call footprint matters. However, total heap allocator pressure dropped significantly (fewer alloc/dealloc pairs).

**Suggested Change:** No change needed. The trade-off (higher peak, lower allocator pressure) is generally beneficial. If memory becomes a concern with many concurrent proofs, consider making `ToeplitzAccumulator` a reusable/pooled object.

## Positive Changes

1. **MSM batching in `finish()`** — Replaces 64 × (128 individual scalar muls) with 128 × MSM-of-64. Windowed MSM on 64 points is roughly 10-50× faster per point than individual scalar multiplication. This is the dominant performance improvement for the FK20 prove path.

2. **Single EC IFFT instead of 64** — Old path did IFFT after each of 64 toeplitzMatVecMulPreFFT calls. New path does one IFFT at `finish()`. Eliminates 63× the IFFT work per proof.

3. **Polyphase spectrum bank in affine form** — Stores 8192 affine points instead of Jacobian points, saving 8192 Z-coordinates (~256 KB). The single `batchAffine_vartime(L*CDS)` at setup time is faster than the old per-offset implicit conversions during each prove call.

4. **In-place FFT in `computePolyphaseDecompositionFourierOffset`** — Writes directly to the output buffer instead of using a temporary `polyphaseComponent` buffer, saving 1 allocation per offset (64 total during setup).

5. **In-place IFFT in `computeAggRandScaledInterpoly`** — Reuses `agg_cols[c]` buffer instead of allocating `col_interpoly`, saving 64 allocations per verify_batch call.

6. **`batchAffine_vartime` across the board** — Switching from constant-time Montgomery ladder batch inversion to variable-time batch inversion with infinity-point skipping. For batches with many neutral points (like the polyphase spectrum where half the points are at infinity), this saves significant compute. Even for full batches, `inv_vartime` vs Montgomery ladder is measurably faster.

7. **`bit_reversal_permutation` aliasing support** — Enables in-place FFT operations without requiring separate output buffers, enabling several memory optimizations throughout the codebase.

8. **`Alloca` tag removal from EC FFT** — The iterative implementations no longer use stack-allocated arrays (StridedView avoids alloca), eliminating potential stack overflow concerns for large FFTs.
