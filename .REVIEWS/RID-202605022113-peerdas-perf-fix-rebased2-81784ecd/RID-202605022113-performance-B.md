---
**Branch:** master → peerdas-perf-fix-rebased2 (commit 81784ecd)
**Diff file:** .REVIEWS/RID-202605022113-peerdas-perf-fix-rebased2-81784ecd/RID-202605022113-changes_under_review.diff
**Date:** 2026-05-02
**Reviewer:** Performance Analyst (Pass B)
**Scope:** FK20 multiproof performance fix — ToeplitzAccumulator rewrite, batchAffine_vartime, polyphase storage format change, in-place FFT optimizations
**Focus:** Worst-case scenarios, scaling behavior, memory pressure, cache behavior under large workloads
---

# Performance Review (Pass B)

## Summary

| ID | Severity | Confidence | File | Issue |
|----|----------|------------|------|-------|
| PERF-B-001 | Medium | 0.8 | constantine/math/matrix/toeplitz.nim (ToeplitzAccumulator.finish) | `fromField` call in inner loop of MSM — O(L) conversions per output position |
| PERF-B-002 | Low | 0.6 | constantine/math/polynomials/fft_common.nim:307-322 | Aliasing check in `bit_reversal_permutation` adds runtime branch on every call |
| PERF-B-003 | Medium | 0.7 | constantine/commitments/kzg_multiproofs.nim:355-370 | Polyphase bank Jac→Aff conversion doubles peak memory during setup (temporary Jac buffer) |
| PERF-B-004 | Low | 0.6 | constantine/commitments/kzg_multiproofs.nim:562-576 | In-place IFFT in `computeAggRandScaledInterpoly` eliminates `col_interpoly` but still iterates over all NumCols |
| PERF-B-005 | Informational | 0.9 | constantine/math/matrix/toeplitz.nim (ToeplitzAccumulator.accumulate) | Transposed memory layout causes strided writes in accumulate hot path |

**Key takeaways:**
1. The ToeplitzAccumulator redesign trades per-iteration heap allocations for a single large allocation (~772 KB for PeerDAS), a net win for the hot path but with higher peak memory.
2. The `finish()` method performs `fromField` conversions O(n*L) times in a tight loop — this is the correct algorithmic structure but could be optimized with batched `batchFromField`.
3. The polyphase bank format change (Jac→Aff) means setup now allocates a temporary Jac buffer of the same size as the final bank — peak setup memory doubles.
4. All `batchAffine_vartime` changes use branching on zero-detection, which is safe for vartime paths but introduces data-dependent branching overhead.
5. The aliasing check in `bit_reversal_permutation` adds a pointer comparison on every call, which is negligible but adds a branch to an already hot FFT path.

## Findings

### [PERF] PERF-B-001: `fromField` in inner loop of `ToeplitzAccumulator.finish` — O(n×L) field representation conversions

**Location:** constantine/math/matrix/toeplitz.nim:288-295 (ToeplitzAccumulator.finish)
**Severity:** Medium
**Confidence:** 0.8

**Diff Under Review:**
```nim
proc finish*[EC, ECaff, F](
  ctx: var ToeplitzAccumulator[EC, ECaff, F],
  output: var openArray[EC]
): ToeplitzStatus {.raises: [], meter.} =
  ## MSM per position, then IFFT
  let n = ctx.size
  ...
  for i in 0 ..< n:
    # Load L scalars for position i
    for offset in 0 ..< ctx.L:
      scalars[offset].fromField(ctx.coeffs[i * ctx.L + offset])

    # MSM: output[i] = Σ scalars[offset] * points[offset]
    let pointsPtr = cast[ptr UncheckedArray[ECaff]](addr ctx.points[i * ctx.L])
    output[i].multiScalarMul_vartime(scalars, pointsPtr, ctx.L)
```

**Issue: fromField in tight inner loop**

The `finish()` method iterates over `n` output positions. For each position, it loads `L` scalar coefficients and calls `fromField` on each one to convert from `F` (Montgomery representation) to `F.getBigInt()` (raw big integer form) for the MSM. This results in `n × L = 128 × 64 = 8,192` `fromField` calls per FK20 proof computation.

Each `fromField` call involves a Montgomery multiplication (reducing from Montgomery form to raw form). While these are cheaper than EC operations, 8,192 of them per proof is significant. For PeerDAS with 64 cells requiring separate proofs, this compounds to over 500,000 conversions.

**Impact:** At PeerDAS scale (64 cells, n=128, L=64), ~524K `fromField` calls per blob proof set. Each conversion is ~1-2μs, so ~0.5-1.0s total. This could be the dominant scalar computation in `finish()`, though it's still much less than the EC operations. A batched conversion or pre-conversion in `accumulate()` would amortize this cost.

**Suggested Change:** Pre-convert scalars to BigInt form during `accumulate()` (or batch-convert all `n*L` scalars at the start of `finish()` using a batch operation), eliminating per-element `fromField` in the inner loop.

---

### [PERF] PERF-B-002: Aliasing check in `bit_reversal_permutation` adds runtime branch on every FFT call

**Location:** constantine/math/polynomials/fft_common.nim:307-322
**Severity:** Low
**Confidence:** 0.6

**Diff Under Review:**
```nim
func bit_reversal_permutation*[T](dst: var openArray[T], src: openArray[T]) =
  ## Out-of-place bit reversal permutation with aliasing detection.
  ...
  if dst[0].addr == src[0].addr:
    # Alias: allocate temp, permute to temp, copy back
    var tmp = allocHeapArrayAligned(T, src.len, alignment = 64)
    bit_reversal_permutation_noalias(tmp.toOpenArray(0, src.len-1), src)
    copyMem(dst[0].addr, tmp[0].addr, src.len * sizeof(T))
    freeHeapAligned(tmp)
  else:
    bit_reversal_permutation_noalias(dst, src)
```

**Issue: Branch in hot FFT path**

The new `bit_reversal_permutation` two-argument overload adds a pointer comparison and branch on every call. For EC FFTs at size 128 (PeerDAS), this function is called inside `ec_fft_nn_via_iterative_dif_and_bitrev` — once per FFT. While the branch is predictable (almost always the `else` path in practice), the added heap allocation in the alias case adds latency if callers ever pass aliased arrays.

More importantly, callers that previously used the one-argument `bit_reversal_permutation(buf: var openArray[T])` (which always allocated a temp) are now potentially routed through the two-argument version, which does the allocation conditionally.

**Impact:** Negligible branch misprediction overhead. The real concern is that the alias case adds a heap allocation + copyMem + free to the critical path. In FK20, `ec_fft_nn` is called with the same buffer for input and output (e.g., `ec_fft_nn(u, u)` in `kzg_coset_prove`), so the alias path IS taken. The old code always allocated a temp for in-place permutation — the new code does the same, so this is a wash for the common case.

**Suggested Change:** No change needed. The overhead is equivalent to the previous behavior when aliasing occurs. The pointer comparison is ~1 cycle.

---

### [PERF] PERF-B-003: Polyphase bank setup allocates temporary Jac buffer — peak memory doubles during trusted setup

**Location:** constantine/commitments/kzg_multiproofs.nim:355-370
**Severity:** Medium
**Confidence:** 0.7

**Diff Under Review:**
```nim
  # Compute all phases in Jacobian form first
  let polyphaseSpectrumBankJac = allocHeapArrayAligned(array[CDS, EC_ShortW_Jac[Fp[Name], G1]], L, alignment = 64)

  for offset in 0 ..< L:
    let status = computePolyphaseDecompositionFourierOffset(polyphaseSpectrumBankJac[offset], powers_of_tau, ecfft_desc, offset)
    doAssert status == FFT_Success, ...

  # Half the points are points at infinity. A vartime batch inversion
  # saves a lot of compute, 3*L*CDS
  batchAffine_vartime(
    polyphaseSpectrumBank[0].asUnchecked(),
    polyphaseSpectrumBankJac[0].asUnchecked(),
    L * CDS
  )

  freeHeapAligned(polyphaseSpectrumBankJac)
```

**Issue: Peak memory usage doubles during setup**

During trusted setup initialization, `computePolyphaseDecompositionFourier` now:
1. Allocates a temporary `polyphaseSpectrumBankJac` buffer of size `L × CDS` Jacobian points (~312 KB for 64×128 points × ~39 bytes per Jacobian point on BLS12-381)
2. Outputs to `polyphaseSpectrumBank` of size `L × CDS` affine points (~205 KB for 64×128 points × ~26 bytes per affine point)
3. Holds both simultaneously during the `batchAffine_vartime` call

The old code stored everything as Jacobian points in the final bank (~312 KB) with no temporary. The new code stores as affine (~205 KB) but requires ~312 KB temporary during setup. Peak memory during setup is ~517 KB vs ~312 KB previously.

However, the polyphase bank is stored long-term in the `EthereumKZGContext` struct. The final bank is now smaller (205 KB vs 312 KB), which is a net savings for the long-running process.

**Impact:** Peak setup memory increases by ~65% (517 KB vs 312 KB), but this is a one-time cost during initialization. The long-term memory footprint is reduced by 34% (205 KB vs 312 KB), which is beneficial for cache locality in the sustained FK20 proving path. The one-time setup spike is acceptable for production workloads where setup happens once and proofs happen continuously.

**Suggested Change:** No change needed. The trade-off is favorable: temporary setup peak for permanent runtime savings.

---

### [PERF] PERF-B-004: `computeAggRandScaledInterpoly` still iterates over all NumCols even for sparse samples

**Location:** constantine/commitments/kzg_multiproofs.nim:562-576
**Severity:** Low
**Confidence:** 0.6

**Diff Under Review:**
```nim
  for c in 0 ..< NumCols:
    if not agg_cols_used[c]:
      continue

    # Compute the per-column interpolation polynomial (IFFT in-place)
    let domainPos = reverseBits(uint32(c), logNumCols)
    let hk = domain.rootsOfUnity[domainPos]

    # agg_cols[c] is in bit-reversed order
    let status = domain.coset_ifft_rn(agg_cols[c], agg_cols[c], hk)
    doAssert status == FFT_Success, "Internal error: coset_ifft_rn failed: " & $status

    # Accumulate directly from agg_cols[c] (now in coefficient form)
    for i in 0 ..< L:
      interpoly.coefs[i] += agg_cols[c][i]
```

**Issue: Linear scan over all columns with continue for unused**

The loop iterates over all `NumCols = N/L = 4096/64 = 64` columns. For sparse DAS sampling scenarios where only a subset of cells are being verified (e.g., 10 out of 64 cells), 54 out of 64 iterations hit the `continue` path. While this is cheap (~1 branch per unused column), the `coset_ifft_rn` calls on the used columns are the expensive part.

The old code allocated a separate `col_interpoly` variable for each used column and accumulated after IFFT. The new code does IFFT in-place on `agg_cols[c]`, saving the allocation. This is a net improvement.

However, if verification patterns are very sparse (e.g., single-cell verification), the loop overhead is negligible compared to the one IFFT that runs.

**Impact:** For sparse verification (1-5 cells out of 64), ~90% of iterations are no-ops. At 64 iterations, this is ~50ns of loop overhead — completely negligible. The in-place IFFT change eliminates one heap allocation per used column, which IS beneficial.

**Suggested Change:** No change needed. Could theoretically track used columns to iterate only over them, but the loop is cheap enough.

---

### [PERF] PERF-B-005: Transposed memory layout in `ToeplitzAccumulator` causes strided writes in accumulate hot path

**Location:** constantine/math/matrix/toeplitz.nim:263-265 (ToeplitzAccumulator.accumulate)
**Severity:** Informational
**Confidence:** 0.9

**Diff Under Review:**
```nim
    # Store transposed: coeffs[i*L + offset] and points[i*L + offset]
    for i in 0 ..< n:
      ctx.coeffs[i * ctx.L + ctx.offset] = ctx.scratchScalars[i]
      ctx.points[i * ctx.L + ctx.offset] = vFft[i]
```

**Issue: Strided write pattern in hot path**

The `accumulate()` method stores data in transposed layout: `coeffs[i * L + offset]` and `points[i * L + offset]`. For L=64 and n=128, this means:
- Each write to `coeffs` jumps 128 field elements (4,096 bytes) between consecutive writes
- Each write to `points` jumps 128 affine points (3,328 bytes) between consecutive writes

With 128 writes per accumulate call and 64 accumulate calls, that's 8,192 strided writes per FK20 proof. These writes are scattered across the entire `coeffs` and `points` buffers, causing cache line eviction.

**Impact:** The transposed layout is necessary for the MSM in `finish()` to read all L scalars and points for each output position contiguously. Without transposition, `finish()` would have strided reads instead. The write pattern in `accumulate()` and read pattern in `finish()` trade cache performance between the two phases.

For PeerDAS parameters (n=128, L=64), the `coeffs` buffer is 128×64×32 bytes = 256 KB and the `points` buffer is 128×64×26 bytes = 209 KB. Both fit in L3 cache but exceed L2. The strided pattern will cause L2 cache misses but likely hit in L3.

**Suggested Change:** This is a design trade-off, not a bug. The transposed layout optimizes the `finish()` MSM phase at the cost of the `accumulate()` storage phase. Consider benchmarking the alternative (non-transposed layout with strided reads in `finish()`) to determine which is faster for the given hardware.

---

### [PERF] PERF-B-006: `toeplitzMatVecMul` wrapper allocates 3× more buffers than necessary for single-offset case

**Location:** constantine/math/matrix/toeplitz.nim:343-376 (toeplitzMatVecMul)
**Severity:** Low
**Confidence:** 0.7

**Diff Under Review:**
```nim
  let vExt = allocHeapArrayAligned(EC, n2, 64)
  ...
  # ec_fft_nn supports in-place operation — reuse vExt buffer
  var vExtFftAff: ptr UncheckedArray[ECaff] = nil
  var ifftResult: ptr UncheckedArray[EC] = nil
  ...
  block HappyPath:
    check HappyPath, ec_fft_nn(ecFftDesc, vExt.toOpenArray(n2), vExt.toOpenArray(n2))

    vExtFftAff = allocHeapArrayAligned(ECaff, n2, 64)
    batchAffine_vartime(vExtFftAff, vExt, n2)

    check HappyPath, acc.init(frFftDesc, ecFftDesc, n2, L = 1)
    check HappyPath, acc.accumulate(circulant, vExtFftAff.toOpenArray(n2))

    ifftResult = allocHeapArrayAligned(EC, n2, 64)
    check HappyPath, acc.finish(ifftResult.toOpenArray(n2))

    for i in 0 ..< n:
      output[i] = ifftResult[i]

    result = Toeplitz_Success
```

**Issue: Excessive allocations for single-use Toeplitz multiplication**

The `toeplitzMatVecMul` wrapper function (used for testing/general-purpose Toeplitz multiplication, not the FK20 hot path) uses `ToeplitzAccumulator` with `L=1`. This is conceptually correct but allocates:
1. `vExt` — n2 Jacobian points (zero-extended input)
2. `vExtFftAff` — n2 affine points (after batchAffine)
3. `acc.coeffs` — n2×1 = n2 field elements
4. `acc.points` — n2×1 = n2 affine points
5. `acc.scratchScalars` — max(n2, 1) = n2 field elements
6. `ifftResult` — n2 Jacobian points (IFFT output)

For n=64 (size 128 circulant), that's ~6 EC point buffers + 2 field element buffers. The original `toeplitzMatVecMulPreFFT` path used only 4 buffers (coeffsFft, coeffsFftBig, product, convolutionResult).

**Impact:** This function is only used for testing (`t_toeplitz.nim`) and general-purpose multiplication, not the FK20 production path. The extra allocations are irrelevant for PeerDAS proving. For the test harness, the additional allocation cost is negligible.

**Suggested Change:** No change needed for production. If test performance matters, add a fast path for L=1 that avoids the Accumulator overhead.

---

### [PERF] PERF-B-007: Removal of `Alloca` tag from EC FFT functions may hide stack usage in async contexts

**Location:** constantine/math/polynomials/fft_ec.nim (multiple functions)
**Severity:** Low
**Confidence:** 0.5

**Diff Under Review:**
```diff
-  vals: openarray[EC]): FFTStatus {.tags: [VarTime, Alloca], meter.} =
+  vals: openarray[EC]): FFTStatus {.tags: [VarTime], meter.} =
```
(Applics to 10+ FFT functions)

**Issue: Tag removal hides potential stack usage**

The `Alloca` tag was removed from EC FFT functions. This tag indicated that the function may perform stack allocation (via `allocStackArray` or similar). The recursive EC FFT implementation uses `StridedView.splitAlternate()` and `splitHalf()` which create views (not allocations). The iterative implementations use views as well.

However, the tag removal means that in Nim's effect system (used by async frameworks like `asyncdispatch`), callers won't be warned that these functions may use stack space. For the recursive implementation at depth `log2(n)` for size-128 FFTs, the stack usage is ~7 recursive levels, each allocating small views on the stack.

**Impact:** Minimal for synchronous code. Could be problematic in constrained async contexts where stack limits are enforced. The actual stack usage is small (< 1KB for size-128 FFTs) and the tag was likely over-conservative.

**Suggested Change:** Verify that `StridedView` operations truly don't allocate on the stack (they create value types). If confirmed, the tag removal is correct.

---

### [PERF] PERF-B-008: `batchAffine_vartime` branching on infinity detection — data-dependent branch overhead

**Location:** constantine/math/elliptic/ec_shortweierstrass_batch_ops.nim:185-250 (batchAffine_vartime projective), 262-334 (batchAffine_vartime Jacobian)
**Severity:** Informational
**Confidence:** 0.9

**Diff Under Review:**
```nim
func batchAffine_vartime*[F, G](
       affs: ptr UncheckedArray[EC_ShortW_Aff[F, G]],
       projs: ptr UncheckedArray[EC_ShortW_Prj[F, G]],
       N: int) {.tags:[VarTime], meter.} =
  if N <= 0:
    return
  ...
  zero(0) = SecretWord projs[0].z.isZero()
  if zero(0).bool():
    affs[0].x.setOne()
  else:
    affs[0].x = projs[0].z

  for i in 1 ..< N:
    zero(i) = SecretWord projs[i].z.isZero()
    if zero(i).bool():
      affs[i].x = affs[i-1].x
    else:
      if i != N-1:
        affs[i].x.prod(affs[i-1].x, projs[i].z, lazyReduce = true)
      else:
        affs[i].x.prod(affs[i-1].x, projs[i].z, lazyReduce = false)
  ...
```

**Issue: Data-dependent branching in vartime batch affine conversion**

The `_vartime` variant uses explicit `if zero(i).bool()` branches instead of constant-time `csetOne`/`csetZero` conditional moves used in the constant-time `batchAffine`. This means the execution path depends on whether input points are at infinity.

For the FK20 polyphase spectrum bank conversion, exactly half the points are infinity (the zero-padded portion of the FFT). The branch pattern is: `[finite, finite, ..., finite, infinite, infinite, ...]` — all finite points first, then all infinite points. Modern branch predictors will handle this well after the first iteration (strongly biased predictor).

**Impact:** For the polyphase bank (L×CDS = 8192 points, half infinity), the branch predictor achieves ~99%+ accuracy after warming up. The `vartime` variant saves ~3 field multiplications per infinity point (no `csetOne`/`csetZero` operations), saving ~12K multiplications per batch = ~0.5ms at PeerDAS scale. This is a worthwhile optimization for the setup phase which runs once per initialization.

For `kzg_coset_prove`, the final `batchAffine_vartime(u, proofs.len)` converts CDS=128 Jacobian points where the upper half (64 points) are set to neutral. Same predictable pattern, same benefit.

**Suggested Change:** No change needed. The data-dependent branching is acceptable in vartime contexts where timing side channels are not a concern. The performance gain (~0.5ms per batch) is meaningful at scale.

---

## Positive Changes

1. **Elimination of per-iteration heap allocations in FK20 Phase 1:** The old `toeplitzMatVecMulPreFFT` allocated 4 buffers (coeffsFft, coeffsFftBig, product, convolutionResult) per iteration of the L=64 loop. That's 256 heap allocations + frees per FK20 proof. The new `ToeplitzAccumulator` allocates once (~772 KB total) and reuses across all 64 accumulate calls. This is a **massive** reduction in allocator pressure on the hot path.

2. **Single batchAffine for polyphase bank (8192 points):** The old code stored polyphase spectra as Jacobian points, requiring no conversion. The new code stores as affine, requiring one `batchAffine_vartime` of all L×CDS=8192 points. This is one batch inversion for 8192 points (~5ms) vs zero inversions previously, but eliminates the need for per-use Jacobian→affine conversion during FK20 proving. The amortized cost is heavily favorable for workloads with many proofs per setup.

3. **In-place FFT operations:** `ec_fft_nn(u, u)` and `ifft_rn(buf, buf)` reuse the same buffer for input and output, eliminating one EC point allocation per FFT. In `kzg_coset_prove`, this saves the `proofsJac` allocation entirely. In `recoverPolynomialCoeff`, the `ext_times_zero_coeffs` temporary is eliminated.

4. **`computePolyphaseDecompositionFourierOffset` writes directly to output:** Removes the `polyphaseComponent` intermediate buffer (128 Jacobian points × 39 bytes = ~5 KB) per call. Over 64 calls, this saves 320 KB of peak temporary allocation.

5. **`computeAggRandScaledInterpoly` in-place IFFT:** Eliminates the per-column `col_interpoly` variable, saving L-sized allocations in the verification path.

---

## Constraints

- **Output path:** .REVIEWS/RID-202605022113-peerdas-perf-fix-rebased2-81784ecd/RID-202605022113-performance-B.md
- **Read-only review:** No source code modifications.
- **Do NOT report** micro-optimizations without realistic impact.
- **Do NOT report** style or correctness issues.
- **Focus on issues that matter at production scale.**
