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

  # Check zero padding (indices 1 to r)
  # Note: Fixed from `1 .. r + 1` to avoid OOB when r=1
  for i in 1 .. r:
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

template checkReturn*(evalExpr: untyped): untyped {.dirty.} =
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
    ## Accumulator for Toeplitz matrix-vector multiplication with MSM
    ## Following c-kzg-4844 fk20.c algorithm
    frFftDesc: FrFFT_Descriptor[F]          # FFT descriptor for field element transforms (user-owned, not freed by =destroy)
    ecFftDesc: ECFFT_Descriptor[EC]         # FFT descriptor for EC point transforms (user-owned, not freed by =destroy)
    coeffs: ptr UncheckedArray[F]           # [size*L] transposed coeffs
    points: ptr UncheckedArray[ECaff]       # [size*L] points for each position
    size: int
    L: int
    offset: int

proc `=destroy`*[EC, ECaff, F](ctx: var ToeplitzAccumulator[EC, ECaff, F]) {.raises: [].} =
  if not ctx.coeffs.isNil():
    freeHeapAligned(ctx.coeffs)
  if not ctx.points.isNil():
    freeHeapAligned(ctx.points)
  ctx.coeffs = nil
  ctx.points = nil

proc `=copy`*[EC, ECaff, F](dst: var ToeplitzAccumulator[EC, ECaff, F], src: ToeplitzAccumulator[EC, ECaff, F]) {.error: "ToeplitzAccumulator cannot be copied".}

proc init*[EC, ECaff, F](
  ctx: var ToeplitzAccumulator[EC, ECaff, F],
  frFftDesc: FrFFT_Descriptor[F],
  ecFftDesc: ECFFT_Descriptor[EC],
  size: int,
  L: int
): ToeplitzStatus {.raises: [], meter.} =
  # Free existing allocations (defensive: handles accidental double-init)
  if not ctx.coeffs.isNil():
    freeHeapAligned(ctx.coeffs)
  if not ctx.points.isNil():
    freeHeapAligned(ctx.points)

  ctx.size = 0
  ctx.offset = 0
  ctx.L = 0
  ctx.coeffs = nil
  ctx.points = nil
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
  block HappyPath:
    check HappyPath, fft_nn(ctx.frFftDesc, coeffsFft.toOpenArray(n), circulant)

    # Store transposed: coeffs[i*L + offset] and points[i*L + offset]
    for i in 0 ..< n:
      ctx.coeffs[i * ctx.L + ctx.offset] = coeffsFft[i]
      ctx.points[i * ctx.L + ctx.offset] = vFft[i]

    ctx.offset += 1
    result = Toeplitz_Success

  freeHeapAligned(coeffsFft)
  return result

proc finish*[EC, ECaff, F](
  ctx: var ToeplitzAccumulator[EC, ECaff, F],
  output: var openArray[EC]
): ToeplitzStatus {.raises: [], meter.} =
  ## MSM per position, then IFFT
  let n = ctx.size
  if n == 0 or output.len != n or ctx.offset != ctx.L:
    return Toeplitz_MismatchedSizes

  let scalars = allocHeapArrayAligned(F.getBigInt(), ctx.L, alignment = 64)

  for i in 0 ..< n:
    # Load L scalars for position i
    for offset in 0 ..< ctx.L:
      scalars[offset].fromField(ctx.coeffs[i * ctx.L + offset])

    # MSM: output[i] = Σ scalars[offset] * points[offset]
    let pointsPtr = cast[ptr UncheckedArray[ECaff]](addr ctx.points[i * ctx.L])
    # SAFE: all inputs are public data per FK20 construction — no secret-dependent branching risk
    output[i].multiScalarMul_vartime(scalars, pointsPtr, ctx.L)

  freeHeapAligned(scalars)

  let ifftInput = allocHeapArrayAligned(EC, n, 64)
  block HappyPath:
    for i in 0 ..< n:
      ifftInput[i] = output[i]

    check HappyPath, ec_ifft_nn(ctx.ecFftDesc, output, ifftInput.toOpenArray(0, n - 1))
    result = Toeplitz_Success

  freeHeapAligned(ifftInput)
  return result

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
  ## 3. Accumulate into ToeplitzAccumulator (stores FFT results transposed)
  ## 4. MSM per output position, then IFFT
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

  # ec_fft_nn supports in-place operation — reuse vExt buffer
  var vExtFftAff: ptr UncheckedArray[ECaff] = nil
  var ifftResult: ptr UncheckedArray[EC] = nil
  # Default-init is safe: =destroy nil-checks all ptr fields and type is not large
  var acc: ToeplitzAccumulator[EC, ECaff, F]

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

  if vExtFftAff != nil:
    freeHeapAligned(vExtFftAff)
  if ifftResult != nil:
    freeHeapAligned(ifftResult)
  freeHeapAligned(vExt)

  return result