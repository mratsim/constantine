---
**Branch:** `master` → `peerdas-perf-fix-rebased2` (commit `74d1839c`)
**Diff file:** `.REVIEWS/RID-202605022039-peerdas-perf-fix-rebased2-74d1839c/RID-202605022039-changes_under_review.diff`
**Date:** 2026-05-02
**Reviewer:** Performance Analyst (Pass B)
**Scope:** PeerDAS FK20 KZG multiproof optimization — ToeplitzAccumulator rewrite, batchAffine_vartime, polyphase spectrum bank layout change, FFT tag cleanup, matrix transpose
**Focus:** Worst-case scenarios, scaling behavior, thread contention, false sharing, memory allocation patterns under load
---

# Performance Review (Pass B)

## Summary

| ID | Severity | Confidence | File | Issue |
|----|----------|------------|------|-------|
| PERF-B-001 | High | 0.9 | `constantine/math/matrix/toeplitz.nim:308-378` | `toeplitzMatVecMul` with L=1: per-output MSM overhead replaces direct scalarMul |
| PERF-B-002 | Medium | 0.8 | `constantine/math/matrix/toeplitz.nim:288-299` | `ToeplitzAccumulator.finish()` strided memory access in `fromField` inner loop |
| PERF-B-003 | Medium | 0.8 | `constantine/commitments/kzg_multiproofs.nim:355-370` | `computePolyphaseDecompositionFourier` allocates ~2.4 MB temporary buffer |
| PERF-B-004 | Low | 0.7 | `constantine/math/polynomials/fft_common.nim:1920-1936` | `bit_reversal_permutation` aliasing path adds one extra heap allocation |
| PERF-B-005 | Informational | 0.9 | `constantine/math/matrix/toeplitz.nim:187-199` | `ToeplitzAccumulator` memory layout: `offset` field co-located with pointers (false sharing risk under parallelization) |

**Key takeaways:**

1. **`toeplitzMatVecMul` regression (L=1 path):** The standalone `toeplitzMatVecMul` proc now uses `ToeplitzAccumulator` with L=1, causing n2 separate `multiScalarMul_vartime(N=1)` calls in `finish()` instead of n2 direct `scalarMul_vartime` calls. Each N=1 MSM triggers full Pippenger pipeline overhead (heap allocation for buckets, dispatch). This is a measurable regression for benchmark/test code but does NOT affect the production FK20 path (`kzg_coset_prove` uses L=64).

2. **Strided access in `finish()`:** The transposed storage layout (`coeffs[i*L+offset]`) causes stride-L cache misses during the `fromField` conversion loop. For L=64 and 32-byte Fr, the stride is 2 KB — every element access is a cache miss. Total: 8192 cache misses for PeerDAS.

3. **Temporary buffer allocation during setup:** `computePolyphaseDecompositionFourier` now allocates a 2.4 MB intermediate buffer (`polyphaseSpectrumBankJac`) before the batch affine conversion. This is a one-time cost during trusted setup but increases peak memory usage by ~2.4 MB.

4. **Overall the changes are positive for the FK20 hot path:** Reducing per-offset heap allocations from ~192 to ~3, and replacing n2 scalar multiplications with n2 Pippenger MSMs (L=64) should be a net win. Pass A likely covered this analysis in more detail.

## Findings

### [PERF] PERF-B-001: `toeplitzMatVecMul` with L=1 uses Pippenger MSM for single-scalar multiplications — `constantine/math/matrix/toeplitz.nim:308-378`

**Location:** `constantine/math/matrix/toeplitz.nim:308-378`
**Severity:** High
**Confidence:** 0.9

**Diff Under Review:**
```diff
+proc toeplitzMatVecMul*[EC, F](
+   output: var openArray[EC],
+   circulant: openArray[F],
+   v: openArray[EC],
+   frFftDesc: FrFFT_Descriptor[F],
+   ecFftDesc: ECFFT_Descriptor[EC]
+): ToeplitzStatus {.meter.} =
+  type ECaff = EC.affine
+  let n = v.len
+  let n2 = 2 * n
+  let vExt = allocHeapArrayAligned(EC, n2, 64)
+  # ... setup ...
+  # ec_fft_nn supports in-place operation — reuse vExt buffer
+  var acc: ToeplitzAccumulator[EC, ECaff, F]
+  block HappyPath:
+    check HappyPath, ec_fft_nn(ecFftDesc, vExt.toOpenArray(n2), vExt.toOpenArray(n2))
+    vExtFftAff = allocHeapArrayAligned(ECaff, n2, 64)
+    batchAffine_vartime(vExtFftAff, vExt, n2)
+    check HappyPath, acc.init(frFftDesc, ecFftDesc, n2, L = 1)
+    check HappyPath, acc.accumulate(circulant, vExtFftAff.toOpenArray(n2))
+    ifftResult = allocHeapArrayAligned(EC, n2, 64)
+    check HappyPath, acc.finish(ifftResult.toOpenArray(n2))
+    for i in 0 ..< n:
+      output[i] = ifftResult[i]
```

**Issue:** **MSM pipeline overhead for single-scalar multiplications**

The new `toeplitzMatVecMul` uses `ToeplitzAccumulator` initialized with `L=1`. In the `finish()` method, this means:

```nim
for i in 0 ..< n:  # n = CDS = 128 for PeerDAS (or n2 = 256 for toeplitzMatVecMul)
    scalars[offset].fromField(ctx.coeffs[i * 1 + 0])  # Load 1 scalar
    output[i].multiScalarMul_vartime(scalars, pointsPtr, 1)  # MSM with N=1
```

Each `multiScalarMul_vartime(scalars, pointsPtr, 1)` call:
- Enters `msm_dispatch_vartime`, which computes `bestBucketBitSize(1, 254, true, true)` → c=2
- Calls `msmImpl_vartime` with c=2, which:
  - Allocates a bucket array of size `2^(c-1) = 2` EC points on the heap
  - Runs the full mini-MSM pipeline (bucket accumulate → bucket reduce → final reduction)
  - Frees the bucket array
- **For N=1, all the Pippenger machinery is pure overhead** — it's just one scalar multiplication

The old code path used `scalarMul_vartime` directly:
```nim
product[i].scalarMul_vartime(coeffsFftBig[i], vFft[i])  # Direct wNAF, no bucket overhead
```

**Impact:** For `toeplitzMatVecMul` with n=128 (n2=256):
- Old: 256 direct `scalarMul_vartime` calls (~3 µs each) = ~768 µs
- New: 256 `multiScalarMul_vartime(N=1)` calls (~5-10 µs each due to bucket alloc/dispatch) = ~1.3-2.6 ms
- **Expected regression: 2-3× slower** for the Hadamard product phase

This affects benchmark code (`bench_matrix_toeplitz.nim`) and test code (`t_toeplitz.nim`). It does NOT affect the production `kzg_coset_prove` path (which uses `ToeplitzAccumulator` with L=64 directly).

**Suggested Change:** Add a fast path in `ToeplitzAccumulator.finish()` or `toeplitzMatVecMul` for L=1:

```nim
# In toeplitzMatVecMul, after ec_fft_nn:
var ifftResult = allocHeapArrayAligned(EC, n2, 64)
for i in 0 ..< n2:
    # Convert scalar from field to BigInt for scalarMul
    let bigScalar {.noInit.}: F.getBigInt()
    bigScalar.fromField(ctx.coeffs[i])  # or use pre-converted buffer
    ifftResult[i].scalarMul_vartime(bigScalar, vExtFftAff[i])
# IFFT
checkReturn ec_ifft_nn(ctx.ecFftDesc, ifftResult, ifftResult)
```

Alternatively, add an N=1 fast path in `multiScalarMul_vartime`:
```nim
func multiScalarMul_vartime*(...):
    if len == 1:
        r.scalarMul_vartime(coefs[0])  # Direct call, no bucket machinery
        return
    # ... existing Pippenger pipeline ...
```

---

### [PERF] PERF-B-002: `ToeplitzAccumulator.finish()` strided memory access pattern — `constantine/math/matrix/toeplitz.nim:288-299`

**Location:** `constantine/math/matrix/toeplitz.nim:288-299`
**Severity:** Medium
**Confidence:** 0.8

**Diff Under Review:**
```diff
+proc finish*[EC, ECaff, F](
+  ctx: var ToeplitzAccumulator[EC, ECaff, F],
+  output: var openArray[EC]
+): ToeplitzStatus {.raises: [], meter.} =
+  let n = ctx.size
+  # ...
+  let scalars = cast[ptr UncheckedArray[F.getBigInt()]](ctx.scratchScalars)
+
+  for i in 0 ..< n:
+    # Load L scalars for position i
+    for offset in 0 ..< ctx.L:
+      scalars[offset].fromField(ctx.coeffs[i * ctx.L + offset])
+
+    # MSM: output[i] = Σ scalars[offset] * points[offset]
+    let pointsPtr = cast[ptr UncheckedArray[ECaff]](addr ctx.points[i * ctx.L])
+    output[i].multiScalarMul_vartime(scalars, pointsPtr, ctx.L)
```

**Issue:** **Strided access pattern causes cache misses in `fromField` conversion loop**

The `coeffs` array is stored in transposed layout: `coeffs[i * L + offset]`. When `finish()` iterates over `offset` for a given `i`, it accesses elements at stride `L = 64`.

For `Fr[BLS12_381]` (32 bytes per element), the stride is 64 × 32 = **2,048 bytes** (2 KB). This means:
- Each of the 64 `fromField` calls reads from a different cache line
- For 128 output positions: 128 × 64 = **8,192 cache misses** in the scalar loading phase
- Similarly for `points` array: stride of 64 × 96 bytes = 6,144 bytes per access

The same strided pattern exists in `accumulate()`, but there the data is written (prefetch-friendly) and the L=64 stride is amortized across the 64 accumulate calls (each write is at a different offset column). In `finish()`, all 64 scalars for a position must be read before the MSM can proceed, so the cache misses are sequential and cannot be overlapped.

**Impact:**
- With ~50 ns per L3 cache miss: 8,192 × 50 ns ≈ **410 µs** of pure cache miss latency
- This is a one-time cost in `finish()` but adds to the already-heavy MSM phase
- For comparison, the old `toeplitzMatVecMulPreFFT` stored coeffsFftBig contiguously, avoiding this strided access

**Suggested Change:** Consider storing scalars in a non-transposed layout for the `finish()` phase, or pre-convert `fromField` results during `accumulate()` to avoid the conversion entirely:

```nim
# Option: Store BigInt scalars directly in accumulate()
type ToeplitzAccumulator = object
    # ...
    coeffsBig: ptr UncheckedArray[F.getBigInt]  # [size * L] in BigInt form
    # Remove coeffs, or keep only one

proc accumulate*:
    # After FFT, convert to BigInt and store transposed
    for i in 0 ..< n:
        let big = F.getBigInt()
        big.fromField(ctx.scratchScalars[i])
        ctx.coeffsBig[i * ctx.L + ctx.offset] = big

proc finish*:
    # No fromField needed — scalars are already BigInt
    for i in 0 ..< n:
        let scalarsPtr = addr ctx.coeffsBig[i * ctx.L]
        output[i].multiScalarMul_vartime(scalarsPtr, pointsPtr, ctx.L)
```

This trades one conversion loop (during accumulate) for avoiding strided conversions in finish, but keeps total work the same. The real win would come from pre-converting to BigInt during accumulate so finish() is just pointer arithmetic + MSM calls.

---

### [PERF] PERF-B-003: `computePolyphaseDecompositionFourier` allocates ~2.4 MB temporary buffer — `constantine/commitments/kzg_multiproofs.nim:355-370`

**Location:** `constantine/commitments/kzg_multiproofs.nim:355-370`
**Severity:** Medium
**Confidence:** 0.8

**Diff Under Review:**
```diff
+  # Compute all phases in Jacobian form first
+  let polyphaseSpectrumBankJac = allocHeapArrayAligned(array[CDS, EC_ShortW_Jac[Fp[Name], G1]], L, alignment = 64)
+
+  for offset in 0 ..< L:
+    let status = computePolyphaseDecompositionFourierOffset(polyphaseSpectrumBankJac[offset], powers_of_tau, ecfft_desc, offset)
+    doAssert status == FFT_Success, "Internal error: Polyphase decomposition FFT failed at offset " & $offset
+
+  # Half the points are points at infinity. A vartime batch inversion
+  # saves a lot of compute, 3*L*CDS
+  batchAffine_vartime(
+    polyphaseSpectrumBank[0].asUnchecked(),
+    polyphaseSpectrumBankJac[0].asUnchecked(),
+    L * CDS
+  )
+
+  freeHeapAligned(polyphaseSpectrumBankJac)
```

**Issue:** **Large temporary allocation during trusted setup**

The new approach allocates `L × CDS = 64 × 128 = 8,192` Jacobian EC points as an intermediate buffer. Each `EC_ShortW_Jac[Fp[BLS12_381], G1]` is 3 × 96 = 288 bytes. Total: **8,192 × 288 = 2.35 MB**.

This allocation:
- Is freed before the function returns (not leaked)
- Is done once during trusted setup initialization
- Increases peak memory usage by ~2.4 MB temporarily

The trade-off is justified:
- Old: `polyphaseSpectrumBank` stored Jac (2.4 MB), then callers had to convert to Aff per-use
- New: `polyphaseSpectrumBank` stores Aff directly (1.4 MB), saving ~1 MB in the context struct permanently
- The vartime batch conversion is faster since ~half the points are infinity (skips inversions)

**Impact:**
- Memory: +2.4 MB peak during setup, -1 MB permanently (context struct is smaller)
- Setup time: Likely faster due to vartime batch affine (skips inversions for 50% of points)
- **For memory-constrained environments (embedded, mobile):** The 2.4 MB spike could be problematic if setup memory budget is tight

**Suggested Change:** Document the peak memory requirement. If memory is a concern, consider processing in chunks:

```nim
# Process in batches of B offsets at a time
const B = 16  # Process 16 offsets at a time
for batch in 0 ..< L div B - 1:
    let partialJac = allocHeapArrayAligned(array[CDS, EC_ShortW_Jac[...]], B, 64)
    for offset in batch*B ..< (batch+1)*B:
        computePolyphaseDecompositionFourierOffset(partialJac[offset - batch*B], ...)
    batchAffine_vartime(polyphaseSpectrumBank[batch*B], partialJac, B * CDS)
    freeHeapAligned(partialJac)
```

This reduces peak temporary memory from 2.4 MB to 0.6 MB (B=16).

---

### [PERF] PERF-B-004: `bit_reversal_permutation` aliasing path adds heap allocation — `constantine/math/polynomials/fft_common.nim:1920-1936`

**Location:** `constantine/math/polynomials/fft_common.nim:1920-1936`
**Severity:** Low
**Confidence:** 0.7

**Diff Under Review:**
```diff
+func bit_reversal_permutation*[T](dst: var openArray[T], src: openArray[T]) {.inline.} =
+  if dst[0].addr == src[0].addr:
+    # Alias: allocate temp, permute to temp, copy back
+    var tmp = allocHeapArrayAligned(T, src.len, alignment = 64)
+    bit_reversal_permutation_noalias(tmp.toOpenArray(0, src.len-1), src)
+    copyMem(dst[0].addr, tmp[0].addr, src.len * sizeof(T))
+    freeHeapAligned(tmp)
+  else:
+    bit_reversal_permutation_noalias(dst, src)
```

**Issue:** **Extra heap allocation when dst == src**

The new `bit_reversal_permutation` with aliasing detection allocates a temporary buffer when `dst` and `src` are the same array. This path is taken in `ec_ifft_nn` when called with aliased buffers (e.g., `ec_fft_nn(u, u)` in `kzg_coset_prove`).

For PeerDAS (`CDS = 128`), the temporary buffer is 128 EC points = 128 × 288 = 36 KB for Jacobian or 128 × 96 = 12 KB for Affine.

**Impact:**
- One extra heap allocation + free per in-place EC FFT
- ~36 KB allocation for Jacobian, ~12 KB for Affine
- At PeerDAS scale: called once per `kzg_coset_prove` in the final `ec_fft_nn(u, u)` call
- **Negligible in absolute terms** — dominated by the MSM cost
- However, in a tight loop (e.g., many concurrent proofs), this adds allocator pressure

**Suggested Change:** No change needed. The correctness benefit (supporting aliased in-place FFT) outweighs the minimal allocation cost. If this becomes a bottleneck, consider a stack-allocated buffer for small sizes:

```nim
const STACK_THRESHOLD = 64  # elements
if dst[0].addr == src[0].addr:
    if src.len <= STACK_THRESHOLD:
        var tmp {.align: 64.}: array[STACK_THRESHOLD, T]
        # ... use tmp directly
    else:
        var tmp = allocHeapArrayAligned(T, src.len, 64)
        # ... heap path
```

---

### [PERF] PERF-B-005: `ToeplitzAccumulator` memory layout — false sharing risk under parallelization — `constantine/math/matrix/toeplitz.nim:187-199`

**Location:** `constantine/math/matrix/toeplitz.nim:187-199`
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

**Issue:** **`offset` field shares cache line with heap pointers**

The `size`, `L`, and `offset` fields are all `int` (8 bytes on 64-bit), totaling 24 bytes. They share a cache line with `scratchScalars` (8-byte pointer). During `accumulate()`, `ctx.offset` is read (to compute the write position) and written (`ctx.offset += 1`) on every call.

If `ToeplitzAccumulator` were ever used from multiple threads (e.g., parallel accumulation for different polyphase components), the shared cache line would cause false sharing between the pointer fields (read-only) and the `offset` field (write-hot).

**Impact:**
- Currently NOT a problem — `kzg_coset_prove` uses a single `ToeplitzAccumulator` from a single thread
- Would become a problem if `kzg_coset_prove` were parallelized across L offsets using shared accumulators
- Low risk since the accumulator pattern doesn't naturally parallelize across offsets (sequential accumulation into shared state)

**Suggested Change:** No immediate action needed. If parallelization is considered in the future, pad the `offset` field to its own cache line:

```nim
type ToeplitzAccumulator* = object
    frFftDesc: FrFFT_Descriptor[F]
    ecFftDesc: ECFFT_Descriptor[EC]
    coeffs: ptr UncheckedArray[F]
    points: ptr UncheckedArray[ECaff]
    scratchScalars: ptr UncheckedArray[F]
    size: int
    L: int
    _pad: array[24, byte]  # Cache line padding
    offset: int
```

Or use `ThreadVar` / per-thread accumulators if parallelizing across offsets.

---

## Positive Changes

The following optimizations in this diff are **genuine performance improvements** for the FK20 hot path:

1. **Eliminated per-offset heap allocations in `kzg_coset_prove`:** The old `toeplitzMatVecMulPreFFT` allocated 3 heap buffers per call (coeffsFft, coeffsFftBig, product), called 64 times = **192 heap allocations**. The new `ToeplitzAccumulator` allocates 3 buffers once in `init()` = **3 heap allocations**. At ~300 ns per alloc, this saves ~57 µs of allocator overhead per proof.

2. **Pippenger MSM replaces per-element scalarMul:** The old `toeplitzMatVecMulPreFFT` did n2 individual `scalarMul_vartime` calls (each using wNAF with ~256 bit operations). The new `finish()` does n2 `multiScalarMul_vartime(L=64)` calls, each leveraging Pippenger's algorithm with c=10 buckets. The bucket-based MSM amortizes additions across all L points, reducing total EC operations from ~n2 × 256 ≈ 32,768 doublings+additions to ~n2 × (256/10 × 64 + 2^10 × 2) ≈ significantly fewer group operations.

3. **In-place FFT reuse in `kzg_coset_prove`:** The new code does `ec_fft_nn(u, u)` instead of allocating `proofsJac` and doing `ec_fft_nn(proofsJac, u)`. This saves one 36 KB heap allocation and one `batchAffine` call (replaced by `batchAffine_vartime` in the final conversion).

4. **`computePolyphaseDecompositionFourier` vartime batch affine:** The comment "Half the points are points at infinity. A vartime batch inversion saves a lot of compute, 3×L×CDS" is accurate. For 8,192 points with ~50% being infinity, `batchAffine_vartime` skips inversions for those points entirely, saving ~3,000+ inversion-equivalent operations.

5. **`computePolyphaseDecompositionFourierOffset` writes directly to output buffer:** Eliminates the temporary `polyphaseComponent` allocation per offset. The polyphase extraction now writes directly into the output `polyphaseSpectrum` buffer, then does in-place FFT.

6. **Removal of `Alloca` tags from FFT functions:** Removing `.tags:[Alloca]` from EC FFT functions is correct — the iterative implementations no longer use stack-allocated arrays (they use StridedViews). This improves Nim's compile-time flow analysis accuracy.

## Constraints

- **Output path:** `.REVIEWS/RID-202605022039-peerdas-perf-fix-rebased2-74d1839c/RID-202605022039-performance-B.md`
- **Read-only review:** No source code modifications made.
- **Focus:** Worst-case scenarios, scaling behavior, thread contention, false sharing, memory allocation patterns.
- **PeerDAS parameters assumed:** N=4096, L=64, CDS=128, Fr[BLS12_381] = 32 bytes, EC_ShortW_Jac = 288 bytes, EC_ShortW_Aff = 96 bytes.
