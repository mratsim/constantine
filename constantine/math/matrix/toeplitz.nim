# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  constantine/math/[arithmetic, ec_shortweierstrass],
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

  # Fill non-zero elements matching c-kzg and rust-kzg:
  #   output[2r-j] = poly[d - offset - j*stride] for j = 1..r-2
  # This puts non-zero values at indices 2r-1 down to r+2
  # Total: r-2 non-zero elements (matches rust's loop: i from k+2 to k2-1)
  for j in 1 ..< r - 1:
    output[2 * r - j] = poly[d - offset - j * stride]

  debug: doAssert checkCirculant(output, poly, offset, stride), "Invalid circulant matrix"

# Note: deriveCirculant was removed - use computeFK20TauExt in kzg_multiprove.nim instead

proc toeplitzHadamardProductPreFFT*[EC, F](
  output: var openArray[EC],
  circulant: openArray[F],
  vFft: openArray[EC],
  frFftDesc: FrFFT_Descriptor[F],
  accumulate: bool = false
): FFTStatus {.meter.} =

  ## Compute Hadamard product for FK20 Toeplitz multiplication (Fourier domain only).
  ##
  ## This is the core FK20 multiplication routine where the setup FFT is already precomputed.
  ## Unlike toeplitzMatVecMulPreFFT, this does NOT do the inverse FFT, allowing accumulation
  ## in Fourier domain for better performance (matching Python/C-kzg/Go-kzg implementations).
  ##
  ## Algorithm:
  ## 1. FFT of circulant coefficients (field elements)
  ## 2. Hadamard product: output[i] += vFft[i] * circulantFft[i]
  ##
  ## Call ec_ifft_rn ONCE after accumulating all L iterations.
  ##
  ## @param output: result vector in Fourier domain (EC points), accumulated if accumulate=true
  ## @param circulant: Circulant matrix coefficients
  ## @param vFft: Precomputed vector FFT (EC points)
  ## @param frFftDesc: Field element FFT descriptor
  ## @param accumulate: If true, accumulate into output; otherwise overwrite
  ## @return: FFTStatus indicating success or failure

  let n = circulant.len

  if vFft.len != n:
    return FFT_SizeNotPowerOfTwo
  if n > frFftDesc.order + 1:
    return FFT_TooManyValues

  let coeffsFft = allocHeapArrayAligned(F, n, 64)
  let coeffsFftBig = allocHeapArrayAligned(F.getBigInt(), n, 64)

  let status1 = fft_nr(frFftDesc, coeffsFft.toOpenArray(n), circulant)
  if status1 != FFT_Success:
    freeHeapAligned(coeffsFft)
    freeHeapAligned(coeffsFftBig)
    return status1

  coeffsFftBig.batchFromField(coeffsFft, n)

  # Hadamard product: output[i] += vFft[i] * circulantFft[i]
  for i in 0 ..< n:
    var product: EC
    product.scalarMul_vartime(coeffsFftBig[i], vFft[i])
    if accumulate:
      output[i].sum_vartime(output[i], product)
    else:
      output[i] = product

  freeHeapAligned(coeffsFft)
  freeHeapAligned(coeffsFftBig)

  return FFT_Success

proc toeplitzMatVecMulPreFFT*[EC, F](
  output: var openArray[EC],
  circulant: openArray[F],
  vFft: openArray[EC],
  frFftDesc: FrFFT_Descriptor[F],
  ecFftDesc: ECFFT_Descriptor[EC],
  accumulate: bool = false
): FFTStatus {.meter.} =

  ## Multiply Toeplitz matrix (via circulant coefficients) by pre-FFT'd vector for FK20.
  ##
  ## This is the core FK20 multiplication routine where the setup FFT is already precomputed.
  ##
  ## Algorithm:
  ## 1. FFT of circulant coefficients (field elements)
  ## 2. Hadamard product: vFft[i] * circulantFft[i]
  ## 3. Inverse FFT (EC points)
  ## 4. Optionally accumulate into output
  ##
  ## For general Toeplitz multiplication:
  ##   - circulant has length 2n (zero-padded embedding)
  ##   - vFft has length 2n (zero-extended vector FFT)
  ##   - output has length n (first n elements of IFFT result)
  ##
  ## For FK20 (same-size multiplication):
  ##   - circulant has length K2
  ##   - vFft has length K2 (precomputed setup FFT)
  ##   - output has length K2
  ##
  ## @param output: result vector (EC points)
  ## @param circulant: Circulant matrix coefficients
  ## @param vFft: Precomputed vector FFT (EC points)
  ## @param frFftDesc: Field element FFT descriptor
  ## @param ecFftDesc: EC FFT descriptor
  ## @param accumulate: If true, accumulate into output; otherwise overwrite
  ## @return: FFTStatus indicating success or failure

  let n = circulant.len
  let outputSize = if output.len < n: output.len else: n

  if vFft.len != n:
    return FFT_SizeNotPowerOfTwo
  if n > frFftDesc.order + 1:
    return FFT_TooManyValues
  if n > ecFftDesc.order + 1:
    return FFT_TooManyValues

  # Compute Hadamard product in Fourier domain (reuses toeplitzHadamardProductPreFFT)
  let product = allocHeapArrayAligned(EC, n, 64)
  let status1 = toeplitzHadamardProductPreFFT(
    product.toOpenArray(n),
    circulant,
    vFft,
    frFftDesc,
    accumulate = false
  )
  if status1 != FFT_Success:
    freeHeapAligned(product)
    return status1

  # Inverse FFT
  let ifftResultSeq = allocHeapArrayAligned(EC, n, 64)
  let status2 = ec_ifft_rn(ecFftDesc, ifftResultSeq.toOpenArray(n), product.toOpenArray(n))
  freeHeapAligned(product)
  if status2 != FFT_Success:
    freeHeapAligned(ifftResultSeq)
    return status2

  # Copy first outputSize elements to output
  if accumulate:
    for i in 0 ..< outputSize:
      output[i].sum_vartime(output[i], ifftResultSeq[i])
  else:
    for i in 0 ..< outputSize:
      output[i] = ifftResultSeq[i]

  freeHeapAligned(ifftResultSeq)

  return FFT_Success

proc toeplitzMatVecMul*[EC, F](
  output: var openArray[EC],
  circulant: openArray[F],
  v: openArray[EC],
  frFftDesc: FrFFT_Descriptor[F],
  ecFftDesc: ECFFT_Descriptor[EC]
): FFTStatus {.meter.} =

  ## Multiply a Toeplitz matrix by a vector using FFT-based O(n log n) algorithm.
  ##
  ## This implements the circulant embedding method:
  ## 1. FFT of zero-extended vector (EC points)
  ## 2. FFT of circulant coefficients (field elements)
  ## 3. Hadamard product: EC_point[i] * Fr_scalar[i]
  ## 4. Inverse FFT (EC) and truncate to first n entries
  ##
  ## This calls toeplitzMatVecMulPreFFT after FFT'ing the vector.
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

  let vExtFftSeq = allocHeapArrayAligned(EC, n2, 64)
  let status1 = ec_fft_nr(ecFftDesc, vExtFftSeq.toOpenArray(n2), vExt.toOpenArray(n2))
  if status1 != FFT_Success:
    freeHeapAligned(vExtFftSeq)
    freeHeapAligned(vExt)
    return status1

  # Call PreFFT version
  let status2 = toeplitzMatVecMulPreFFT(
    output,
    circulant,
    vExtFftSeq.toOpenArray(n2),
    frFftDesc,
    ecFftDesc,
    accumulate = false
  )

  freeHeapAligned(vExtFftSeq)
  freeHeapAligned(vExt)

  return status2