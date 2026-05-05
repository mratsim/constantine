# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  constantine/math/[arithmetic, ec_shortweierstrass],
  constantine/math/elliptic/[ec_multi_scalar_mul, ec_multi_scalar_mul_precomp],
  constantine/math/polynomials/[fft_fields, fft_ec],
  constantine/platforms/[allocs, views, abstractions]

export FFT_Status

# ############################################################
#
#           Toeplitz Matrix-Vector Multiplication
#
# ############################################################
#
# Algorithm from: https://alinush.github.io/2023/04/10/multiplying-a-vector-by-a-toeplitz-matrix.html
# Based on FK20 paper (Feist-Khovratovich 2023): https://eprint.iacr.org/2023/033
#
# For FK20, the Toeplitz matrix has a SPECIAL SPARSE structure:
# The circulant coefficients are:
#   c[0] = poly[r-1]
#   c[1..r+1] = 0
#   c[r+2..2r-1] = poly[1..r-2]
#
# General algorithm for O(n log n) Toeplitz matrix-vector multiplication:
# 1. Build circulant vector a_2n from Toeplitz entries
# 2. Compute y = DFT([x, 0]) (extend input vector x with n zeros)
# 3. Compute v = DFT(a_2n)
# 4. Compute u = v ∘ y (Hadamard/pointwise product)
# 5. Compute result = DFT^{-1}(u)
# 6. Return first n entries

func checkCirculant*[F](
  circulant: openArray[F],
  poly: openArray[F],
  offset: int,
  stride: int
): bool =
  ## Validate that circulant matrix was correctly built from polynomial.
  ## Returns true if circulant structure is valid.
  ##
  ## Checks:
  ## - circulant[0] == poly[n-1-offset]
  ## - circulant[1..r] are all zero
  ## - circulant[r+1] is zero when r+1 < 2*r (bounds-checked for r >= 2)
  ## - circulant[r+2..2r-1] match poly values at stride intervals
  ##
  ## @param circulant: circulant matrix to validate (length 2*r)
  ## @param poly: polynomial coefficients (length n)
  ## @param offset: stride offset used (0..stride-1)
  ## @param stride: stride length
  ## @return: true if valid circulant structure

  let n = poly.len
  let r = circulant.len div 2
  let k2 = 2 * r
  let d = n - 1

  if circulant.len != k2:
    return false

  # Check first element
  if not (circulant[0] == poly[d - offset]).bool:
    return false

  # Check zero padding (indices 1 to r+1)
  for i in 1 .. r:
    if not circulant[i].isZero().bool:
      return false
  # Also check index r+1 when it is in bounds (r >= 2)
  if r + 1 < k2 and not circulant[r + 1].isZero().bool:
    return false

  # Check strided elements: output[2r-j] = poly[d-offset-j*stride] for j=1..r-2
  for j in 1 ..< r - 1:
    let outIdx = 2 * r - j
    let polyIdx = d - offset - j * stride
    if polyIdx < 0 or polyIdx >= n:
      return false
    if not (circulant[outIdx] == poly[polyIdx]).bool:
      return false

  return true

proc makeCirculantMatrix*[F](
  output: var openArray[F],
  poly: openArray[F],
  offset: int,
  stride: int
) {.raises: [], meter.} =
  ## Build circulant matrix embedding for Toeplitz multiplication.
  ##
  ## This builds the circulant vector from polynomial coefficients
  ## with a given stride and offset. Matches c-kzg-4844.
  ##
  ## For EIP-7594:
  ##   n = FIELD_ELEMENTS_PER_BLOB = 4096
  ##   r = CELLS_PER_BLOB = 64
  ##   l = stride = FIELD_ELEMENTS_PER_CELL = 64
  ##   offset ∈ [0, l)
  ##
  ## Output structure (length 2r = 128) - c-kzg convention:
  ##   output[0]      = poly[n - 1 - offset]
  ##   output[1..r]   = 0 (zero padding)
  ##   output[r+1]    = 0 (from zero-init)
  ##   output[r+2..2r-1] = poly values at stride intervals
  ##
  ## @param output: output array of length 2*r
  ## @param poly: polynomial coefficients of length n
  ## @param offset: stride offset (0..stride-1)
  ## @param stride: stride length

  let n = poly.len
  let r = output.len div 2
  let k2 = 2 * r
  let d = n - 1

  debug:
    doAssert output.len == k2, "Output length must be 2*r"
    doAssert poly.len == n, "Poly length mismatch"
    doAssert offset >= 0 and offset < stride, "Offset out of range"

  for i in 0 ..< k2:
    output[i].setZero()

  output[0] = poly[d - offset]

  # Fill non-zero elements:
  #   output[2r-j] = poly[d - offset - j*stride] for j = 1..r-2
  # This puts non-zero values at indices 2r-1 down to r+2
  # Total: r-2 non-zero elements
  for j in 1 ..< r - 1:
    output[2 * r - j] = poly[d - offset - j * stride]

  debug: doAssert checkCirculant(output, poly, offset, stride)


type
  ToeplitzStatus* = enum
    Toeplitz_Success
    Toeplitz_SizeNotPowerOfTwo
    Toeplitz_TooManyValues
    Toeplitz_MismatchedSizes

# Error handling templates
# ------------------------------------------------------------

template checkReturn(evalExpr: untyped): untyped {.dirty.} =
  ## Check ToeplitzStatus or FFTStatus and return early on failure
  ## Use in functions that return ToeplitzStatus directly
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
  ## Use when cleanup/resource deallocation is needed
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

type
  ToeplitzAccumulator*[EC, ECaff, F] = object
    ## Accumulator for Toeplitz matrix-vector multiplication with MSM.
    ## Following c-kzg-4844 fk20.c algorithm.
    frFftDesc: FrFFT_Descriptor[F]          # Field FFT descriptor (user-owned, not freed by =destroy)
    ecFftDesc: ECFFT_Descriptor[EC]         # Elliptic Curve FFT descriptor (user-owned, not freed by =destroy)
    coeffs: ptr UncheckedArray[F]           # [size*L] transposed circulant FFT coefficients
    # Pre-allocated scratch buffer — avoids heap alloc in accumulate/finish hot paths
    scratchScalars: ptr UncheckedArray[F]   # [max(size,L)] scratch buffer (sizeof(F) == sizeof(F.getBigInt()))
    size: int
    L: int
    offset: int

proc `=destroy`*[EC, ECaff, F](ctx: var ToeplitzAccumulator[EC, ECaff, F]) {.raises: [].} =
  if not ctx.coeffs.isNil():
    freeHeapAligned(ctx.coeffs)
  if not ctx.scratchScalars.isNil():
    freeHeapAligned(ctx.scratchScalars)
  ctx.coeffs = nil
  ctx.scratchScalars = nil
proc `=copy`*[EC, ECaff, F](dst: var ToeplitzAccumulator[EC, ECaff, F], src: ToeplitzAccumulator[EC, ECaff, F]) {.error.}

proc init*[EC, ECaff, F](
  ctx: var ToeplitzAccumulator[EC, ECaff, F],
  frFftDesc: FrFFT_Descriptor[F],
  ecFftDesc: ECFFT_Descriptor[EC],
  size: int,
  L: int
): ToeplitzStatus {.raises: [], meter.} =
  ## Initialize a ToeplitzAccumulator for matrix-vector multiplication.
  ##
  ## The accumulator stores coefficients in position-major layout:
  ## `coeffs[i * L + offset]`
  ## and assumes that polyphase decomposed SRS points are
  ## also in position major layout `points[i * L + offset]`,
  ## so that all `L` layers
  ## for a given output position `i` are contiguous in memory. This layout is
  ## optimized for the per-position MSM in `finish`.
  ##
  ## Allocates two 64-byte-aligned heap buffers:
  ##   - `coeffs`:      `[size * L]` field elements  (~32 bytes each)
  ##   - `scratchScalars`: `[max(size, L)]` field elements (reusable scratch buffer)
  ##
  ## For EIP-7594 the buffer is (size=128, L=64).
  ## The scratch buffer is typed as `F` but re-interpreted as `F.getBigInt()`
  ## in `finish` via type-punning (requires `sizeof(F) == sizeof(F.getBigInt())`).
  ##
  ## The `frFftDesc` and `ecFftDesc` descriptors are stored by value and are
  ## user-owned; they are NOT freed by `=destroy`.
  ##
  ## Calling `init` on an already-initialized context frees existing allocations
  ## first (defensive against accidental double-init).
  ##
  ## @param ctx: accumulator to initialize
  ## @param frFftDesc: FFT descriptor for field-element transforms (stored, not freed)
  ## @param ecFftDesc: FFT descriptor for EC-point transforms (stored, not freed)
  ## @param size: transform size (must be a power of two and > 0)
  ## @param L: number of layers/strides (must be > 0)
  if not ctx.coeffs.isNil():
    freeHeapAligned(ctx.coeffs)
  if not ctx.scratchScalars.isNil():
    freeHeapAligned(ctx.scratchScalars)
  ctx.size = 0
  ctx.offset = 0
  ctx.L = 0
  ctx.coeffs = nil
  ctx.scratchScalars = nil
  ctx.frFftDesc = frFftDesc
  ctx.ecFftDesc = ecFftDesc

  if size <= 0 or L <= 0 or not size.isPowerOf2_vartime():
    return Toeplitz_SizeNotPowerOfTwo

  ctx.size = size
  ctx.L = L
  ctx.offset = 0
  ctx.coeffs = allocHeapArrayAligned(F, size * L, alignment = 64)
  ctx.scratchScalars = allocHeapArrayAligned(F, max(size, L), alignment = 64)

  return Toeplitz_Success

proc accumulate*[EC, ECaff, F](
  ctx: var ToeplitzAccumulator[EC, ECaff, F],
  circulant: openArray[F]
): ToeplitzStatus {.raises: [], meter.} =
  ## Accumulate FFT of circulant coefficients for position ctx.offset.
  let n = ctx.size
  if n == 0 or circulant.len != n or ctx.offset >= ctx.L:
    return Toeplitz_MismatchedSizes

  block HappyPath:
    check HappyPath, fft_nn(ctx.frFftDesc, ctx.scratchScalars.toOpenArray(n), circulant)
    for i in 0 ..< n:
      ctx.coeffs[i * ctx.L + ctx.offset] = ctx.scratchScalars[i]
    ctx.offset += 1
    result = Toeplitz_Success
  return result


proc finish*[EC, ECaff, F; L: static int](
  ctx: var ToeplitzAccumulator[EC, ECaff, F],
  output: var openArray[EC],
  polyphaseSpectrumBank: openArray[array[L, ECaff]]
): ToeplitzStatus {.raises: [], meter.} =
  ## Finalize the accumulator: perform per-position MSM followed by in-place IFFT.
  ##
  ## For each output position `i` in `0..n-1`, this extracts the `L` scalars
  ## from `coeffs` (converting via `fromField`), gathers the `L` affine points
  ## from `polyphaseSpectrumBank`, and computes
  ##   `output[i] = Σ_j scalars[j] * points[j]`
  ## using `multiScalarMul_vartime`.
  ##
  ## After all `n` MSMs, an in-place EC IFFT is applied to `output` via
  ## `ec_ifft_nn`. The `bit_reversal_permutation` inside IFFT handles the
  ## aliasing (same buffer for input and output) internally.
  ##
  ## Data is stored in position-major layout: `coeffs[i * L + offset]` and
  ## `polyphaseSpectrumBank[i * L + offset]`. For each position `i`, both `fromField` reads
  ## and the `pointsPtr` slice are contiguous, so no temporary buffer is needed.
  ##
  ## Preconditions:
  ##   - offset == L (all L accumulate calls must have been made)
  ##   - output.len == size (the transform dimension)
  ##   - polyphaseSpectrumBank.len == size (one array[L, ECaff] per output position)
  ##
  ## The `scratchScalars` buffer is reused during this proc: it is type-punned
  ## via `cast` to `ptr UncheckedArray[F.getBigInt()]` to feed `multiScalarMul`. This
  ## requires `sizeof(F) == sizeof(F.getBigInt())`, which is verified at compile time.
  ##
  ## `finish` should be called exactly once after the `L` `accumulate` calls.
  ##
  ## @param ctx: fully-accumulated ToeplitzAccumulator (`offset` must equal `L`)
  ## @param output: result buffer of length `size` (EC points, overwritten)
  ## @return: Toeplitz_Success on success
  ##          Toeplitz_MismatchedSizes if `offset != L`, `size == 0`, or `output.len != size`
  static: doAssert ECaff is affine(EC)
  let n = ctx.size
  if n == 0 or
      output.len != n or
      ctx.offset != ctx.L or
      polyphaseSpectrumBank.len != n or
      L != ctx.L:
    return Toeplitz_MismatchedSizes

  # Invariant: scratchScalars is typed as F but re-interpreted as F.getBigInt() below.
  # This requires sizeof(F) == sizeof(F.getBigInt()), which holds for all production
  # field types (e.g. Fr[BLS12_381] is 32 bytes in both representations).
  static: doAssert sizeof(F) == sizeof(F.getBigInt()), "scratchScalars cast requires sizeof(F) == sizeof(F.getBigInt())"

  let scalars = cast[ptr UncheckedArray[F.getBigInt()]](ctx.scratchScalars)
  for i in 0 ..< n:
    for offset in 0 ..< ctx.L:
      scalars[offset].fromField(ctx.coeffs[i * ctx.L + offset])
    output[i].multiScalarMul_vartime(scalars, polyphaseSpectrumBank[i].asUnchecked(), ctx.L)
  checkReturn ec_ifft_nn(ctx.ecFftDesc, output, output)
  return Toeplitz_Success

proc finish*[EC, ECaff, F; N: static int](
  ctx: var ToeplitzAccumulator[EC, ECaff, F],
  output: var openArray[EC],
  polyphaseSpectrumBank: openArray[PrecomputedMSM[EC, N]]
): ToeplitzStatus {.raises: [], meter.} =
  ## Finalize using precomputed MSM tables (one per output position).
  ## For each output position `i`, extracts the `L` scalars from `coeffs`
  ## and computes `output[i]` using `polyphaseSpectrumBank[i].msm_vartime`.
  ## After all MSMs, an in-place EC IFFT is applied to `output`.
  let n = ctx.size
  if n == 0 or output.len != n or ctx.offset != ctx.L or polyphaseSpectrumBank.len != n or N != ctx.L:
    return Toeplitz_MismatchedSizes
  let scalars = cast[ptr UncheckedArray[F.getBigInt()]](ctx.scratchScalars)
  for i in 0 ..< n:
    for offset in 0 ..< ctx.L:
      scalars[offset].fromField(ctx.coeffs[i * ctx.L + offset])
    polyphaseSpectrumBank[i].msm_vartime(output[i], scalars.toOpenArray(ctx.L))
  checkReturn ec_ifft_nn(ctx.ecFftDesc, output, output)
  return Toeplitz_Success

# ############################################################
#
#           High-level Toeplitz API (for tests)
#
# ############################################################

proc toeplitzMatVecMul*[EC, F](
  output: var openArray[EC],
  circulant: openArray[F],
  v: openArray[EC],
  frFftDesc: FrFFT_Descriptor[F],
  ecFftDesc: ECFFT_Descriptor[EC]
): ToeplitzStatus {.meter.} =
  ## Multiply a Toeplitz matrix by a vector using FFT-based O(n log n) algorithm.
  ##
  ## This implements the circulant embedding method using the ToeplitzAccumulator API:
  ## 1. FFT of zero-extended vector (EC points)
  ## 2. FFT of circulant coefficients (field elements)
  ## 3. Accumulate circulant FFT into ToeplitzAccumulator
  ## 4. MSM per output position with basis points, then IFFT
  ##
  ## @param output: result vector of length n (EC points)
  ## @param circulant: Circulant coefficients of length 2n
  ## @param v: vector of length n (EC points)
  ## @param frFftDesc: Field element FFT descriptor with order >= 2*n
  ## @param ecFftDesc: EC FFT descriptor with order >= 2*n
  ## @return: ToeplitzStatus indicating success or failure
  type ECaff = EC.affine

  let n = v.len
  let n2 = 2 * n

  if output.len != n:
    return Toeplitz_MismatchedSizes
  if circulant.len != n2:
    return Toeplitz_MismatchedSizes
  if n2 > frFftDesc.order:
    return Toeplitz_TooManyValues
  if n2 > ecFftDesc.order:
    return Toeplitz_TooManyValues

  let vExt = allocHeapArrayAligned(EC, n2, 64)
  for i in 0 ..< n:
    vExt[i] = v[i]
  for i in n ..< n2:
    vExt[i].setNeutral()

  # No coset: L = 1
  var vExtFftAff: ptr UncheckedArray[array[1, ECaff]] = nil
  var ifftResult: ptr UncheckedArray[EC] = nil
  # Default-init is safe: =destroy nil-checks all ptr fields and type is not large
  var acc: ToeplitzAccumulator[EC, ECaff, F]

  block HappyPath:
    check HappyPath, ec_fft_nn(ecFftDesc, vExt.toOpenArray(n2), vExt.toOpenArray(n2))

    vExtFftAff = allocHeapArrayAligned(array[1, ECaff], n2, 64)
    batchAffine_vartime(vExtFftAff[0].asUnchecked(), vExt, n2)

    check HappyPath, acc.init(frFftDesc, ecFftDesc, n2, L = 1)
    check HappyPath, acc.accumulate(circulant)

    ifftResult = allocHeapArrayAligned(EC, n2, 64)
    check HappyPath, acc.finish(ifftResult.toOpenArray(n2), vExtFftAff.toOpenArray(n2))

    for i in 0 ..< n:
      output[i] = ifftResult[i]

    result = Toeplitz_Success

  if vExtFftAff != nil:
    freeHeapAligned(vExtFftAff)
  if ifftResult != nil:
    freeHeapAligned(ifftResult)
  freeHeapAligned(vExt)

  return result