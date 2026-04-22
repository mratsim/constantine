# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

# Test with:
#   nim c -r -d:release --hints:off --warnings:off --outdir:build/tmp --nimcache:nimcache/tmp tests/math_polynomials/t_fft.nim
#   nim c -r -d:release --hints:off --warnings:off --outdir:build/tmp --nimcache:nimcache/tmp tests/math_polynomials/t_fft_coset.nim

import
  constantine/named/algebras,
  constantine/math/arithmetic,
  constantine/math/io/[io_bigints, io_fields],
  constantine/math/ec_shortweierstrass,
  constantine/math/elliptic/ec_scalar_mul_vartime,
  constantine/platforms/[abstractions, allocs, views],
  ./fft_common

export
  fft_common.bit_reversal_permutation,
  fft_common.FFTStatus

{.push raises: [], checks: off.} # No exceptions

# ############################################################
#
#                  Finite Fields FFT
#
# ############################################################

type
  FrFFT_Descriptor*[F] = object
    ## Metadata for FFT on field elements
    order*: int
    rootsOfUnity*: ptr UncheckedArray[F]

proc `=destroy`*[F](ctx: FrFFT_Descriptor[F]) =
  if not ctx.rootsOfUnity.isNil():
    ctx.rootsOfUnity.freeHeapAligned()

func computeRootsOfUnity[F](ctx: var FrFFT_Descriptor[F], generatorRootOfUnity: F) =
  ctx.rootsOfUnity[0].setOne()

  var cur = generatorRootOfUnity
  for i in 1 .. ctx.order:
    ctx.rootsOfUnity[i] = cur
    cur *= generatorRootOfUnity

  doAssert ctx.rootsOfUnity[ctx.order].isOne().bool()

func new*(T: type FrFFT_Descriptor, order: int, generatorRootOfUnity: auto): T =
  result.order = order
  result.rootsOfUnity = allocHeapArrayAligned(T.F, order+1, alignment = 64)

  result.computeRootsOfUnity(generatorRootOfUnity)

# Implementation via Recursive Divide & Conquer
# ------------------------------------------------------------------------------

func fft_nn_impl_recursive[F](
       output: var StridedView[F],
       vals: StridedView[F],
       rootsOfUnity: StridedView[F]) {.inline.} =
  ## Recursive Cooley-Tukey FFT (natural to natural)
  if output.len == 1:
    output[0] = vals[0]
    return

  let (evenVals, oddVals) = vals.splitAlternate()
  var (outLeft, outRight) = output.splitHalf()
  let halfROI = rootsOfUnity.skipHalf()

  fft_nn_impl_recursive(outLeft, evenVals, halfROI)
  fft_nn_impl_recursive(outRight, oddVals, halfROI)

  let half = outLeft.len
  var y_times_root{.noinit.}: F

  for i in 0 ..< half:
    y_times_root   .prod(output[i+half], rootsOfUnity[i])
    output[i+half] .diff(output[i], y_times_root)
    output[i]      += y_times_root

func fft_nn_recursive[F](
       desc: FrFFT_Descriptor[F],
       output{.noalias.}: var openarray[F],
       vals{.noalias.}: openarray[F]): FFTStatus {.tags: [VarTime], meter.} =
  ## FFT from natural order to natural order (Recursive Cooley-Tukey).
  ## Input: natural order values
  ## Output: natural order values in Fourier domain
  ## Domain: roots of unity (no shift)
  ##
  ## Algorithm: Recursive Cooley-Tukey FFT
  ##
  ## **IMPORTANT**: `output` and `vals` must NOT alias (be the same array).
  ## The FFT algorithm is NOT in-place safe. Using the same array for both
  ## input and output will produce incorrect results.
  ##
  ## Note: The {.noalias.} annotation documents this requirement but is not
  ## currently enforced by the compiler. It serves as documentation and may
  ## be used by future compiler optimizations or static analysis tools.
  if vals.len > desc.order:
    return FFT_TooManyValues
  if output.len != vals.len:
    return FFT_InconsistentInputOutputLengths
  if not vals.len.uint64.isPowerOf2_vartime():
    return FFT_SizeNotPowerOfTwo

  let rootz = desc.rootsOfUnity
                  .toStridedView(desc.order)
                  .slice(0, desc.order-1, desc.order shr log2_vartime(uint vals.len))

  var voutput = output.toStridedView()
  fft_nn_impl_recursive(voutput, vals.toStridedView(), rootz)
  return FFT_Success

func ifft_nn_recursive[F](
       desc: FrFFT_Descriptor[F],
       output{.noalias.}: var openarray[F],
       vals{.noalias.}: openarray[F]): FFTStatus {.tags: [VarTime], meter.} =
  ## IFFT from natural order to natural order.
  ## Input: natural order values in Fourier domain
  ## Output: natural order values
  ## Domain: roots of unity (no shift)
  ##
  ## **IMPORTANT**: `output` and `vals` must NOT alias (be the same array).
  ## The IFFT algorithm is NOT in-place safe. Using the same array for both
  ## input and output will produce incorrect results.
  ##
  ## Note: The {.noalias.} annotation documents this requirement but is not
  ## currently enforced by the compiler. It serves as documentation and may
  ## be used by future compiler optimizations or static analysis tools.
  if vals.len > desc.order:
    return FFT_TooManyValues
  if output.len != vals.len:
    return FFT_InconsistentInputOutputLengths
  if not vals.len.uint64.isPowerOf2_vartime():
    return FFT_SizeNotPowerOfTwo

  let rootz = desc.rootsOfUnity
                  .toStridedView(desc.order+1)
                  .reversed()
                  .slice(0, desc.order-1, desc.order shr log2_vartime(uint vals.len))

  var voutput = output.toStridedView()
  fft_nn_impl_recursive(voutput, vals.toStridedView(), rootz)

  var invLen {.noInit.}: F
  invLen.fromUint(vals.len.uint64)
  invLen.inv_vartime()

  for i in 0 ..< output.len:
    output[i] *= invLen

  return FFT_Success

# ############################################################
#
#              Iterative FFT (Natural → Bit-Reversed)
#
# ############################################################

func fft_nr_impl_iterative_dif[F](
       output: var StridedView[F],
       rootsOfUnity: StridedView[F]) {.inline.} =
  ## In-place iterative FFT (Cooley-Tukey DIF - Decimation-In-Frequency)
  ## Input: natural order values
  ## Output: bit-reversed order values in Fourier domain
  ##
  ## DIF: Natural input → Bit-reversed output
  ## DIT: Bit-reversed input → Natural output
  let n = output.len

  var length = n
  while length >= 2:
    let half = length shr 1
    let step = n div length

    var i = 0
    while i < n:
      var k = 0
      for j in 0 ..< half:
        var t {.noInit.}: F

        t.diff(output[i + j], output[i + j + half])
        output[i + j] += output[i + j + half]
        output[i + j + half].prod(t, rootsOfUnity[k])

        k += step
      i += length

    length = length shr 1

func fft_nr_iterative_dif[F](
       desc: FrFFT_Descriptor[F],
       output{.noalias.}: var openarray[F],
       vals{.noalias.}: openarray[F]): FFTStatus {.tags: [VarTime], meter.} =
  ## FFT from natural order to bit-reversed order using iterative Cooley-Tukey algorithm.
  ## Input: natural order values
  ## Output: bit-reversed order values in Fourier domain
  ## Domain: roots of unity (no shift)
  ##
  ## Algorithm: In-place iterative Cooley-Tukey FFT
  ##
  ## This is faster than the recursive version for large sizes
  ## because it avoids function call overhead and has better cache patterns.
  ##
  ## **IMPORTANT**: `output` and `vals` must NOT alias (be the same array).
  ##
  ## Note: The {.noalias.} annotation documents this requirement but is not
  ## currently enforced by the compiler. It serves as documentation and may
  ## be used by future compiler optimizations or static analysis tools.
  if vals.len > desc.order:
    return FFT_TooManyValues
  if output.len != vals.len:
    return FFT_InconsistentInputOutputLengths
  if not vals.len.uint64.isPowerOf2_vartime():
    return FFT_SizeNotPowerOfTwo

  let n = vals.len

  # Copy input to output (iterative FFT is in-place)
  for i in 0 ..< n:
    output[i] = vals[i]

  # Get roots of unity with appropriate stride
  let rootz = desc.rootsOfUnity
                  .toStridedView(desc.order)
                  .slice(0, desc.order-1, desc.order shr log2_vartime(uint n))

  # In-place iterative FFT
  var voutput = output.toStridedView()
  fft_nr_impl_iterative_dif(voutput, rootz)

  return FFT_Success

# ############################################################
#
#              Iterative FFT (Bit-Reversed → Natural)
#
# ############################################################

func fft_rn_impl_iterative_dit[F](
       output: var StridedView[F],
       rootsOfUnity: StridedView[F]) {.inline.} =
  ## In-place iterative FFT (Cooley-Tukey DIT - Decimation-In-Time)
  ## Input: bit-reversed order values
  ## Output: natural order values in Fourier domain
  ##
  ## DIT: Bit-reversed input → Natural output
  ## DIF: Natural input → Bit-reversed output
  let n = output.len

  var length = 2
  while length <= n:
    let half = length shr 1
    let step = n div length

    var i = 0
    while i < n:
      var k = 0
      for j in 0 ..< half:
        var t {.noInit.}: F
        t.prod(output[i + j + half], rootsOfUnity[k])

        output[i + j + half] = output[i + j] - t
        output[i + j] += t

        k += step
      i += length

    length = length shl 1

func fft_rn_iterative_dit[F](
       desc: FrFFT_Descriptor[F],
       output{.noalias.}: var openarray[F],
       vals{.noalias.}: openarray[F]): FFTStatus {.tags: [VarTime], meter.} =
  ## FFT from bit-reversed order to natural order using iterative Cooley-Tukey DIT.
  ## Input: bit-reversed order values
  ## Output: natural order values in Fourier domain
  ## Domain: roots of unity (no shift)
  ##
  ## **IMPORTANT**: `output` and `vals` must NOT alias (be the same array).
  ##
  ## Note: The {.noalias.} annotation documents this requirement but is not
  ## currently enforced by the compiler. It serves as documentation and may
  ## be used by future compiler optimizations or static analysis tools.
  if vals.len > desc.order:
    return FFT_TooManyValues
  if output.len != vals.len:
    return FFT_InconsistentInputOutputLengths
  if not vals.len.uint64.isPowerOf2_vartime():
    return FFT_SizeNotPowerOfTwo

  let n = vals.len

  # Copy input to output (iterative FFT is in-place)
  for i in 0 ..< n:
    output[i] = vals[i]

  # Get roots of unity with appropriate stride
  let rootz = desc.rootsOfUnity
                  .toStridedView(desc.order)
                  .slice(0, desc.order-1, desc.order shr log2_vartime(uint n))

  # In-place iterative DIT FFT (bit-reversed → natural)
  var voutput = output.toStridedView()
  fft_rn_impl_iterative_dit(voutput, rootz)

  return FFT_Success

# ############################################################
#
#              Stockham FFT (Natural → Natural)
#
# ############################################################
# The Stockham FFT is a variant of the Cooley-Tukey algorithm that:
# - Uses double-buffering (no in-place computation)
# - Produces natural order output from natural order input
# - Does NOT require bit-reversal permutation
# - Better for vectorization and GPU implementations
#
# References:
# - A Comparison of FFT Algorithms for Graphics Processors, 2008
#   https://www.cs.unc.edu/~dm/UNCCompSci/TECHREPORTS/TR08-027.pdf

func fft_nn_impl_stockham[F](
       output: ptr UncheckedArray[F],
       vals: ptr UncheckedArray[F],
       rootsOfUnity: ptr UncheckedArray[F],
       temp: ptr UncheckedArray[F],
       n: int) =
  ## Stockham FFT algorithm (natural to natural, double-buffered)
  ##
  ## Uses ping-pong buffering between vals and temp to avoid bit-reversal.
  ## Output is in natural order.
  ##
  ## Key insight: Each stage progressively reorders data via strided I/O.
  ## - Input: read strided elements (j and j + n/2)
  ## - Output: write to interleaved positions via (j//Ns)*Ns*2 + (j%Ns) pattern
  ##
  ## This autosort property eliminates the need for bit-reversal permutation.

  # Copy input to output buffer
  for i in 0 ..< n:
    output[i] = vals[i]

  var src = output
  var dst = temp
  var Ns = 1

  while Ns < n:
    let R = 2
    for j in 0 ..< n div R:
      # Input: strided access
      let idxS = j
      
      # Twiddle index
      let wIndex = ((j mod Ns) * n) div (Ns * R)

      # Load and multiply by twiddle
      var t {.noInit.}: F
      t.prod(src[idxS + n div R], rootsOfUnity[wIndex])

      # Radix-2 butterfly
      let sum = src[idxS] + t
      let diff = src[idxS] - t

      # Output: autosort indexing
      # Writes results to interleaved positions across the array
      let idxD = (j div Ns) * Ns * R + (j mod Ns)
      dst[idxD] = sum
      dst[idxD + Ns] = diff

    # Swap buffers
    swap(src, dst)
    Ns = Ns * R

  # If we ended with data in temp (odd number of stages), copy back
  if src != output:
    for i in 0 ..< n:
      output[i] = src[i]

func fft_nn_stockham[F](
       desc: FrFFT_Descriptor[F],
       output{.noalias.}: var openarray[F],
       vals{.noalias.}: openarray[F]): FFTStatus {.tags: [VarTime, HeapAlloc], meter.} =
  ## FFT from natural order to natural order using Stockham algorithm.
  ## Input: natural order values
  ## Output: natural order values in Fourier domain
  ## Domain: roots of unity (no shift)
  ##
  ## Algorithm: Stockham FFT (double-buffered, no bit-reversal needed)
  ##
  ## The Stockham FFT uses ping-pong buffering to avoid the bit-reversal
  ## permutation. This can be faster on some architectures due to better
  ## memory access patterns and vectorization opportunities.
  ##
  ## Trade-offs vs Recursive Cooley-Tukey:
  ## - Pros: No bit-reversal, better memory access patterns
  ## - Cons: Requires 2x memory (temporary buffer)
  ##
  ## **IMPORTANT**: `output` and `vals` must NOT alias (be the same array).
  if vals.len > desc.order:
    return FFT_TooManyValues
  if output.len != vals.len:
    return FFT_InconsistentInputOutputLengths
  if not vals.len.uint64.isPowerOf2_vartime():
    return FFT_SizeNotPowerOfTwo

  let n = vals.len

  # Allocate temporary buffers
  var temp_buf = allocHeapArrayAligned(F, n, alignment = 64)
  var roots_buf = allocHeapArrayAligned(F, n, alignment = 64)

  # Copy strided roots to contiguous buffer for Stockham
  let rootStride = desc.order shr log2_vartime(uint n)
  for i in 0 ..< n:
    roots_buf[i] = desc.rootsOfUnity[i * rootStride]

  # Stockham FFT
  fft_nn_impl_stockham(
    output.asUnchecked(),
    vals.asUnchecked(),
    roots_buf,
    temp_buf,
    n
  )

  freeHeapAligned(temp_buf)
  freeHeapAligned(roots_buf)
  return FFT_Success

# ############################################################
#
#              High-Level FFT API (Auto-dispatch)
#
# ############################################################
# These functions automatically dispatch to the fastest implementation.
# Use the specific implementations (fft_nr_recursive, fft_nr_iterative_dif, etc.)
# if you need to test or benchmark individual algorithms.

func fft_nn*[F](
       desc: FrFFT_Descriptor[F],
       output{.noalias.}: var openarray[F],
       vals{.noalias.}: openarray[F]): FFTStatus {.inline, tags: [VarTime], meter.} =
  ## FFT from natural order to natural order.
  ## Uses recursive Cooley-Tukey algorithm.
  ##
  ## Input: natural order values
  ## Output: natural order values in Fourier domain
  ## Domain: roots of unity (no shift)
  ##
  ## **IMPORTANT**: `output` and `vals` must NOT alias (be the same array).
  fft_nn_recursive(desc, output, vals)

func fft_nr*[F](
       desc: FrFFT_Descriptor[F],
       output{.noalias.}: var openarray[F],
       vals{.noalias.}: openarray[F]): FFTStatus {.inline, tags: [VarTime, HeapAlloc], meter.} =
  ## FFT from natural order to bit-reversed order.
  ## Uses recursive Cooley-Tukey + bit-reversal permutation.
  ##
  ## Input: natural order values
  ## Output: bit-reversed order values in Fourier domain
  ## Domain: roots of unity (no shift)
  ##
  ##
  ## **IMPORTANT**: `output` and `vals` must NOT alias (be the same array).
  ##
  ## Note: The {.noalias.} annotation documents this requirement but is not
  ## currently enforced by the compiler. It serves as documentation and may
  ## be used by future compiler optimizations or static analysis tools.
  let status = fft_nn_recursive(desc, output, vals)
  if status != FFT_Success:
    return status

  bit_reversal_permutation(output)
  return FFT_Success

func ifft_nn*[F](
       desc: FrFFT_Descriptor[F],
       output{.noalias.}: var openarray[F],
       vals{.noalias.}: openarray[F]): FFTStatus {.inline, tags: [VarTime, HeapAlloc], meter.} =
  ifft_nn_recursive(desc, output, vals)

func ifft_rn*[F](
       desc: FrFFT_Descriptor[F],
       output{.noalias.}: var openarray[F],
       vals{.noalias.}: openarray[F]): FFTStatus {.tags: [VarTime, HeapAlloc], meter.} =
  ## IFFT from bit-reversed order to natural order.
  ## Input: bit-reversed order values in Fourier domain
  ## Output: natural order values
  ## Domain: roots of unity (no shift)
  ##
  ## Algorithm: Bit-reverse permutation + IFFT (natural to natural)
  ##
  ## **IMPORTANT**: `output` and `vals` must NOT alias (be the same array).
  ## The IFFT algorithm is NOT in-place safe.
  ##
  ## Note: The {.noalias.} annotation documents this requirement but is not
  ## currently enforced by the compiler. It serves as documentation and may
  ## be used by future compiler optimizations or static analysis tools.
  if vals.len > desc.order:
    return FFT_TooManyValues
  if output.len != vals.len:
    return FFT_InconsistentInputOutputLengths
  if not vals.len.uint64.isPowerOf2_vartime():
    return FFT_SizeNotPowerOfTwo

  # Create temporary buffer and bit-reverse vals into it (bit-reversed → natural)
  var temp_buf = allocHeapArrayAligned(F, vals.len, alignment = 64)
  bit_reversal_permutation(temp_buf.toOpenArray(0, vals.len-1), vals)

  # Call ifft_nn (natural → natural)
  let status = ifft_nn_recursive(desc, output, temp_buf.toOpenArray(0, vals.len-1))
  freeHeapAligned(temp_buf)
  return status

# ############################################################
#
#               Coset FFT (for Reed-Solomon erasure coding)
#
# ############################################################

func shift_vals*[F](
       output: var openarray[F],
       vals: openarray[F],
       shift_factor: F) =
  ## Multiply each entry in vals by succeeding powers of shift_factor
  ## i.e., output[0] = vals[0] * shift_factor^0
  ##       output[1] = vals[1] * shift_factor^1
  ##       ...
  ##       output[n] = vals[n] * shift_factor^n
  ##
  ## This is used in coset FFT to shift the evaluation domain.
  var shift_pow {.noInit.}: F
  shift_pow.setOne()
  for i in 0 ..< vals.len:
    output[i].prod(vals[i], shift_pow)
    shift_pow *= shift_factor

func unshift_vals*[F](
       output: var openarray[F],
       vals: openarray[F],
       inv_shift_factor: F) =
  ## Multiply each entry in vals by succeeding powers of inv_shift_factor
  ## i.e., output[i] = vals[i] * inv_shift_factor^i
  ##
  ## This is the inverse operation of shift_vals
  ## (uses the inverse of the shift factor)
  var inv_shift_pow {.noInit.}: F
  inv_shift_pow.setOne()
  for i in 0 ..< vals.len:
    output[i].prod(vals[i], inv_shift_pow)
    inv_shift_pow *= inv_shift_factor

func coset_fft_nn*[F](
       desc: FrFFT_Descriptor[F],
       output: var openarray[F],
       vals: openarray[F],
       cosetShift: F): FFTStatus {.tags: [VarTime, HeapAlloc], meter.} =
  ## Compute FFT over a coset of the roots of unity (natural to natural order).
  ##
  ## This is used for polynomial operations where we need to avoid
  ## division by zero. By shifting the domain, polynomials that vanish
  ## at certain points won't cause issues during division.
  ##
  ## Algorithm:
  ##   1. Multiply vals[i] by shift_factor^i (shift into coset)
  ##   2. Apply standard FFT (natural to natural order)
  ##
  ## Parameters:
  ##   - desc: FFT descriptor with roots of unity
  ##   - output: output array (must have same length as vals)
  ##   - vals: input values in evaluation form
  ##   - cosetShift, the coset shift
  ##
  ## Returns FFT_Success on success, error code otherwise
  let n = vals.len
  var shifted = allocHeapArrayAligned(F, n, alignment = 64)
  shifted.toOpenArray(n).shift_vals(vals, cosetShift)

  result = desc.fft_nn(output, shifted.toOpenArray(n))
  freeHeapAligned(shifted)

func coset_ifft_nn*[F](
       desc: FrFFT_Descriptor[F],
       output: var openarray[F],
       vals: openarray[F],
       cosetShift: F): FFTStatus {.tags: [VarTime, HeapAlloc], meter.} =
  ## Compute inverse FFT over a coset of the roots of unity (natural to natural order).
  ##
  ## This is used after polynomial division in the coset domain
  ## to get back the polynomial coefficients.
  ##
  ## Algorithm:
  ##   1. Apply standard IFFT (natural to natural)
  ##   2. Multiply result[i] by shift_factor⁻ⁱ (unshift from coset)
  ##
  ## **IMPORTANT**: `output` and `vals` must NOT alias (be the same array).
  ## The coset IFFT algorithm is NOT in-place safe.
  ##
  ## Parameters:
  ##   - desc: FFT descriptor with roots of unity
  ##   - output: output array (must have same length as vals)
  ##   - vals: input values in evaluation form over coset
  ##   - cosetShift, the coset shift (which will be inverted)
  ##
  ## Returns FFT_Success on success, error code otherwise
  let status = desc.ifft_nn(output, vals)
  if status != FFT_Success:
    return status

  var inv_shift_factor {.noInit.}: F
  inv_shift_factor.inv_vartime(cosetShift)
  output.unshift_vals(output, inv_shift_factor)

  return FFT_Success

func coset_ifft_rn*[F](
       desc: FrFFT_Descriptor[F],
       output: var openarray[F],
       vals: openarray[F],
       cosetShift: F): FFTStatus {.tags: [VarTime, HeapAlloc], meter.} =
  ## Compute inverse FFT over a coset of the roots of unity (bit-reversed to natural order).
  ##
  ## Algorithm:
  ##   1. Bit-reverse permutation (bit-reversed → natural)
  ##   2. Apply standard IFFT (natural to natural)
  ##   3. Multiply result[i] by shift_factor⁻ⁱ (unshift from coset)
  ##
  ## **IMPORTANT**: `output` and `vals` must NOT alias (be the same array).
  ## The coset IFFT algorithm is NOT in-place safe.
  ##
  ## Parameters:
  ##   - desc: CosetFFT descriptor with roots of unity and shift factor
  ##   - output: output array (must have same length as vals)
  ##   - vals: input values in evaluation form over coset
  ##   - cosetShift, the coset shift (which will be inverted)
  ##
  ## Returns FFT_Success on success, error code otherwise
  if vals.len > desc.order:
    return FFT_TooManyValues
  if output.len != vals.len:
    return FFT_InconsistentInputOutputLengths
  if not vals.len.uint64.isPowerOf2_vartime():
    return FFT_SizeNotPowerOfTwo

  let n = vals.len
  var temp_buf = allocHeapArrayAligned(F, n, alignment = 64)
  bit_reversal_permutation(temp_buf.toOpenArray(0, n-1), vals)

  let status = desc.coset_ifft_nn(output, temp_buf.toOpenArray(0, n-1), cosetShift)
  freeHeapAligned(temp_buf)
  return status
