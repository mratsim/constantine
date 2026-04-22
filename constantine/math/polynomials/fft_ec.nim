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
#                   Elliptic Curve FFT
#
# ############################################################

type
  ECFFT_Descriptor*[EC] = object
    ## Metadata for FFT on Elliptic Curve
    order*: int
    rootsOfUnity*: ptr UncheckedArray[getBigInt(EC.getName(), kScalarField)]
      ## domain, starting and ending with 1, length is cardinality+1
      ## This allows FFT and inverse FFT to use the same buffer for roots.

proc `=destroy`*[EC](ctx: ECFFT_Descriptor[EC]) =
  if not ctx.rootsOfUnity.isNil():
    ctx.rootsOfUnity.freeHeapAligned()

func computeRootsOfUnity[EC](ctx: var ECFFT_Descriptor[EC], generatorRootOfUnity: auto) =
  static: doAssert typeof(generatorRootOfUnity) is Fr[EC.getName()]

  ctx.rootsOfUnity[0].setOne()

  var cur = generatorRootOfUnity
  for i in 1 .. ctx.order:
    ctx.rootsOfUnity[i].fromField(cur)
    cur *= generatorRootOfUnity

  doAssert ctx.rootsOfUnity[ctx.order].isOne().bool()

func new*(T: type ECFFT_Descriptor, order: int, generatorRootOfUnity: auto): T =
  result.order = order
  result.rootsOfUnity = allocHeapArrayAligned(T.EC.getScalarField().getBigInt(), order+1, alignment = 64)

  result.computeRootsOfUnity(generatorRootOfUnity)

# Implementation via Recursive Divide & Conquer
# ------------------------------------------------------------------------------

func ec_fft_nn_impl_recursive[EC; bits: static int](
       output: var StridedView[EC],
       vals: StridedView[EC],
       rootsOfUnity: StridedView[BigInt[bits]]) {.tags: [VarTime, Alloca].} =
  ## Recursive Cooley-Tukey EC FFT (natural to natural)
  if output.len == 1:
    output[0] = vals[0]
    return

  # Recursive Divide-and-Conquer
  let (evenVals, oddVals) = vals.splitAlternate()
  var (outLeft, outRight) = output.splitHalf()
  let halfROI = rootsOfUnity.skipHalf()

  ec_fft_nn_impl_recursive(outLeft, evenVals, halfROI)
  ec_fft_nn_impl_recursive(outRight, oddVals, halfROI)

  let half = outLeft.len
  var y_times_root{.noinit.}: EC

  for i in 0 ..< half:
    # FFT Butterfly
    y_times_root   .scalarMul_vartime(rootsOfUnity[i], output[i+half])
    output[i+half] .diff_vartime(output[i], y_times_root)
    output[i]      .sum_vartime(output[i], y_times_root)

func ec_fft_nn_recursive[EC](
       desc: ECFFT_Descriptor[EC],
       output: var openarray[EC],
       vals: openarray[EC]): FFTStatus {.tags: [VarTime, Alloca], meter.} =
  ## EC FFT from natural order to natural order (Recursive Cooley-Tukey).
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
  ec_fft_nn_impl_recursive(voutput, vals.toStridedView(), rootz)
  return FFT_Success

func ec_ifft_nn_recursive[EC](
       desc: ECFFT_Descriptor[EC],
       output: var openarray[EC],
       vals: openarray[EC]): FFTStatus {.tags: [VarTime, Alloca], meter.} =
  ## Inverse FFT from natural order to natural order
  if vals.len > desc.order:
    return FFT_TooManyValues
  if output.len != vals.len:
    return FFT_InconsistentInputOutputLengths
  if not vals.len.uint64.isPowerOf2_vartime():
    return FFT_SizeNotPowerOfTwo

  let rootz = desc.rootsOfUnity
                  .toStridedView(desc.order+1) # Extra 1 at the end so that when reversed the buffer starts with 1
                  .reversed()
                  .slice(0, desc.order-1, desc.order shr log2_vartime(uint vals.len))

  var voutput = output.toStridedView()
  ec_fft_nn_impl_recursive(voutput, vals.toStridedView(), rootz)

  var invLen {.noInit.}: Fr[EC.getName()]
  invLen.fromUint(vals.len.uint64)
  invLen.inv_vartime()

  for i in 0 ..< output.len:
    output[i].scalarMul_vartime(invLen.toBig())

  return FFT_Success

# Implementation via iterative Cooley Tukey
# ------------------------------------------------------------------------------

func ec_fft_nr_impl_iterative[EC; bits: static int](
       output: var StridedView[EC],
       rootsOfUnity: StridedView[BigInt[bits]]) {.tags: [VarTime, Alloca].} =
  ## In-place iterative EC FFT (Cooley-Tukey DIF - Decimation-In-Frequency)
  ## Input: natural order values
  ## Output: bit-reversed order values in Fourier domain
  ##
  ## DIF: Natural input → Bit-reversed output
  let n = output.len

  var length = n
  while length >= 2:
    let half = length shr 1
    let step = n div length

    var i = 0
    while i < n:
      var k = 0
      for j in 0 ..< half:
        let idx1 = i + j
        let idx2 = i + j + half

        let u = output[idx1]
        let v = output[idx2]

        output[idx1].sum_vartime(u, v)
        var t {.noInit.}: EC
        t.scalarMul_vartime(rootsOfUnity[k], u - v)
        output[idx2] = t

        k += step
      i += length

    length = length shr 1

func ec_fft_nr_iterative[EC](
       desc: ECFFT_Descriptor[EC],
       output: var openarray[EC],
       vals: openarray[EC]): FFTStatus {.tags: [VarTime, Alloca], meter.} =
  ## EC FFT from natural order to bit-reversed order using iterative Cooley-Tukey algorithm.
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
  ec_fft_nr_impl_iterative(voutput, rootz)

  return FFT_Success


# ############################################################
#
#              High-Level FFT API (Auto-dispatch)
#
# ############################################################
# These functions automatically dispatch to the fastest implementation.
# Use the specific implementations (fft_nr_recursive, fft_nr_iterative, etc.)
# if you need to test or benchmark individual algorithms.

func ec_fft_nr[EC](
       desc: ECFFT_Descriptor[EC],
       output: var openarray[EC],
       vals: openarray[EC]): FFTStatus {.tags: [VarTime, HeapAlloc, Alloca], meter.} =
  ## EC FFT from natural order to bit-reversed order (Recursive Cooley-Tukey + bit-reversal).
  let status = ec_fft_nn_recursive(desc, output, vals)
  if status != FFT_Success:
    return status

  bit_reversal_permutation(output)
  return status

func ec_fft_nn*[EC](
       desc: ECFFT_Descriptor[EC],
       output: var openarray[EC],
       vals: openarray[EC]): FFTStatus {.inline, tags: [VarTime, Alloca], meter.} =
  ## EC FFT from natural order to natural order.
  ## Automatically dispatches to the fastest implementation.
  ec_fft_nn_recursive(desc, output, vals)

func ec_ifft_nn[EC](
       desc: ECFFT_Descriptor[EC],
       output: var openarray[EC],
       vals: openarray[EC]): FFTStatus {.inline, tags: [VarTime, Alloca], meter.} =
  ec_ifft_nn_recursive(desc, output, vals)

func ec_ifft_rn*[EC](
       desc: ECFFT_Descriptor[EC],
       output: var openarray[EC],
       vals: openarray[EC]): FFTStatus {.tags: [VarTime, HeapAlloc, Alloca], meter.} =
  ## Inverse FFT from bit-reversed order to natural order
  ## Algorithm: Bit-reverse permutation + IFFT (natural to natural)
  if vals.len > desc.order:
    return FFT_TooManyValues
  if output.len != vals.len:
    return FFT_InconsistentInputOutputLengths
  if not vals.len.uint64.isPowerOf2_vartime():
    return FFT_SizeNotPowerOfTwo

  var temp_buf = allocHeapArrayAligned(EC, vals.len, alignment = 64)
  bit_reversal_permutation(temp_buf.toOpenArray(0, vals.len-1), vals)

  let status = ec_ifft_nn(desc, output, temp_buf.toOpenArray(0, vals.len-1))
  freeHeapAligned(temp_buf)
  return status
