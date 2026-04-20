# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  constantine/math/[arithmetic, ec_shortweierstrass],
  constantine/math/elliptic/ec_multi_scalar_mul,
  constantine/math/polynomials/fft,
  constantine/platforms/[allocs, views, abstractions]

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
#   c[0] = poly[n-1]
#   c[1..n+1] = 0
#   c[n+2..2n-1] = poly[1..n-2]
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
  ## - circulant[r+1..2r-1] match poly values at stride intervals
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
  for i in 1 .. r + 1:
    if not circulant[i].isZero().bool:
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
  ##   output[r+1..2r-1] = poly values at stride intervals
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

type
  ToeplitzAccumulator*[EC, ECaff, F] = object
    ## Accumulator for Toeplitz matrix-vector multiplication with MSM
    ## Following c-kzg-4844 fk20.c algorithm
    frFftDesc: FrFFT_Descriptor[F]
    ecFftDesc: ECFFT_Descriptor[EC]
    coeffs: ptr UncheckedArray[F]           # [size*L] transposed coeffs
    points: ptr UncheckedArray[ECaff]       # [size*L] points for each position
    scalarsBig: ptr UncheckedArray[F.getBigInt()]  # [L] temporary scalars for MSM
    size: int
    offset: int
    L: int

proc init*[EC, ECaff, F](
  ctx: var ToeplitzAccumulator[EC, ECaff, F],
  frFftDesc: FrFFT_Descriptor[F],
  ecFftDesc: ECFFT_Descriptor[EC],
  size: int,
  L: int
): ToeplitzStatus {.raises: [], meter.} =
  ctx.size = 0
  ctx.offset = 0
  ctx.L = 0
  ctx.coeffs = nil
  ctx.points = nil
  ctx.scalarsBig = nil
  ctx.frFftDesc = frFftDesc
  ctx.ecFftDesc = ecFftDesc

  if size <= 0 or L <= 0 or not size.isPowerOf2_vartime():
    return Toeplitz_SizeNotPowerOfTwo

  ctx.size = size
  ctx.L = L
  ctx.offset = 0
  # Allocate transposed buffers: [size*L]
  ctx.coeffs = allocHeapArrayAligned(F, size * L, alignment = 64)
  ctx.points = allocHeapArrayAligned(ECaff, size * L, alignment = 64)
  ctx.scalarsBig = allocHeapArrayAligned(F.getBigInt(), L, alignment = 64)

  return Toeplitz_Success

proc accumulate*[EC, ECaff, F](
  ctx: var ToeplitzAccumulator[EC, ECaff, F],
  circulant: openArray[F],
  vFft: openArray[ECaff]
): ToeplitzStatus {.raises: [], meter.} =
  ## Accumulate FFT(circulant) and vFft for position ctx.offset
  let n = ctx.size
  if n == 0 or circulant.len != n or vFft.len != n or ctx.offset >= ctx.L:
    return Toeplitz_MismatchedSizes

  let coeffsFft = allocHeapArrayAligned(F, n, 64)
  let status1 = fft_nr(ctx.frFftDesc, coeffsFft.toOpenArray(n), circulant)
  if status1 != FFT_Success:
    freeHeapAligned(coeffsFft)
    return case status1
      of FFT_SizeNotPowerOfTwo: Toeplitz_SizeNotPowerOfTwo
      of FFT_TooManyValues: Toeplitz_TooManyValues
      else: Toeplitz_MismatchedSizes

  # Store transposed: coeffs[i*L + offset] and points[i*L + offset]
  for i in 0 ..< n:
    ctx.coeffs[i * ctx.L + ctx.offset] = coeffsFft[i]
    ctx.points[i * ctx.L + ctx.offset] = vFft[i]

  freeHeapAligned(coeffsFft)
  ctx.offset += 1
  return Toeplitz_Success

proc finish*[EC, ECaff, F](
  ctx: var ToeplitzAccumulator[EC, ECaff, F],
  output: var openArray[EC]
): ToeplitzStatus {.raises: [], meter.} =
  ## MSM per position, then IFFT
  let n = ctx.size
  if n == 0 or output.len < n or ctx.offset != ctx.L:
    return Toeplitz_MismatchedSizes

  # MSM for each output position i
  for i in 0 ..< n:
    # Load L scalars for position i
    for offset in 0 ..< ctx.L:
      ctx.scalarsBig[offset].fromField(ctx.coeffs[i * ctx.L + offset])

    # Load L points for position i
    let pointsPtr = cast[ptr UncheckedArray[ECaff]](addr ctx.points[i * ctx.L])

    # MSM: fourierResult[i] = Σ scalars[offset] * points[offset]
    output[i].multiScalarMul_vartime(
      ctx.scalarsBig.toOpenArray(ctx.L),
      pointsPtr.toOpenArray(ctx.L)
    )

  # IFFT: output = iDFT(fourierResult)
  let ifftInput = allocHeapArrayAligned(EC, n, 64)
  for i in 0 ..< n:
    ifftInput[i] = output[i]

  let status = ec_ifft_rn(ctx.ecFftDesc, output, ifftInput.toOpenArray(0, n - 1))
  freeHeapAligned(ifftInput)

  if status != FFT_Success:
    return case status
      of FFT_SizeNotPowerOfTwo: Toeplitz_SizeNotPowerOfTwo
      of FFT_TooManyValues: Toeplitz_TooManyValues
      else: Toeplitz_MismatchedSizes

  return Toeplitz_Success

proc `=destroy`*[EC, ECaff, F](
  ctx: var ToeplitzAccumulator[EC, ECaff, F]
) {.raises: [], meter.} =
  if ctx.coeffs == nil:
    return
  freeHeapAligned(ctx.coeffs)
  freeHeapAligned(ctx.points)
  freeHeapAligned(ctx.scalarsBig)
  ctx.coeffs = nil
  ctx.points = nil
  ctx.scalarsBig = nil
  ctx.size = 0
  ctx.offset = 0
  ctx.L = 0

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
): FFTStatus {.meter.} =
  ## Multiply a Toeplitz matrix by a vector using FFT-based O(n log n) algorithm.
  ##
  ## This implements the circulant embedding method using the ToeplitzAccumulator API:
  ## 1. FFT of zero-extended vector (EC points)
  ## 2. FFT of circulant coefficients (field elements)
  ## 3. Accumulate into ToeplitzAccumulator (stores FFT results transposed)
  ## 4. MSM per output position, then IFFT
  ##
  ## @param output: result vector of length n (EC points)
  ## @param circulant: Circulant coefficients of length 2n
  ## @param v: vector of length n (EC points)
  ## @param frFftDesc: Field element FFT descriptor with order >= 2*n
  ## @param ecFftDesc: EC FFT descriptor with order >= 2*n
  ## @return: FFTStatus indicating success or failure

  let n = v.len
  let n2 = 2 * n

  if output.len != n:
    return FFT_SizeNotPowerOfTwo
  if circulant.len != n2:
    return FFT_SizeNotPowerOfTwo
  if n2 > frFftDesc.order + 1:
    return FFT_TooManyValues
  if n2 > ecFftDesc.order + 1:
    return FFT_TooManyValues

  let vExt = allocHeapArrayAligned(EC, n2, 64)
  for i in 0 ..< n:
    vExt[i] = v[i]
  for i in n ..< n2:
    vExt[i].setNeutral()

  let vExtFft = allocHeapArrayAligned(EC, n2, 64)
  let status1 = ec_fft_nr(ecFftDesc, vExtFft.toOpenArray(n2), vExt.toOpenArray(n2))
  if status1 != FFT_Success:
    freeHeapAligned(vExtFft)
    freeHeapAligned(vExt)
    return status1

  # Convert to affine for accumulator
  type ECaff = EC.affine
  let vExtFftAff = allocHeapArrayAligned(ECaff, n2, 64)
  for i in 0 ..< n2:
    vExtFftAff[i].affine(vExtFft[i])

  # Use accumulator API (single iteration for general Toeplitz)
  # accumulate will FFT the circulant coefficients internally
  var acc: ToeplitzAccumulator[EC, ECaff, F]
  let initStatus = acc.init(frFftDesc, ecFftDesc, n2, L = 1)
  if initStatus != Toeplitz_Success:
    freeHeapAligned(vExtFftAff)
    freeHeapAligned(vExtFft)
    freeHeapAligned(vExt)
    return case initStatus
      of Toeplitz_SizeNotPowerOfTwo: FFT_SizeNotPowerOfTwo
      of Toeplitz_TooManyValues: FFT_TooManyValues
      else: FFT_SizeNotPowerOfTwo

  let accumStatus = acc.accumulate(circulant, vExtFftAff.toOpenArray(n2))
  if accumStatus != Toeplitz_Success:
    acc.`=destroy`()
    freeHeapAligned(vExtFftAff)
    freeHeapAligned(vExtFft)
    freeHeapAligned(vExt)
    return case accumStatus
      of Toeplitz_SizeNotPowerOfTwo: FFT_SizeNotPowerOfTwo
      of Toeplitz_TooManyValues: FFT_TooManyValues
      else: FFT_SizeNotPowerOfTwo

  # Allocate temporary buffer for full IFFT result (size n2)
  let ifftResult = allocHeapArrayAligned(EC, n2, 64)
  let finishStatus = acc.finish(ifftResult.toOpenArray(n2))
  acc.`=destroy`()

  # Copy only first n elements (truncate the circulant embedding result)
  for i in 0 ..< n:
    output[i] = ifftResult[i]

  freeHeapAligned(ifftResult)
  freeHeapAligned(vExtFftAff)
  freeHeapAligned(vExtFft)
  freeHeapAligned(vExt)
  if finishStatus != Toeplitz_Success:
    return case finishStatus
      of Toeplitz_SizeNotPowerOfTwo: FFT_SizeNotPowerOfTwo
      of Toeplitz_TooManyValues: FFT_TooManyValues
      else: FFT_SizeNotPowerOfTwo

  return FFT_Success
