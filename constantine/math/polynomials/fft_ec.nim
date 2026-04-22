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

func ec_fft_nr_impl_iterative_dif[EC; bits: static int](
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
        var t {.noInit.}: EC
        t.diff_vartime(output[i + j], output[i + j + half])
        output[i + j].sum_vartime(output[i + j], output[i + j + half])
        output[i + j + half].scalarMul_vartime(rootsOfUnity[k], t)

        k += step
      i += length

    length = length shr 1

func ec_fft_rn_impl_iterative_dit[EC; bits: static int](
       output: var StridedView[EC],
       rootsOfUnity: StridedView[BigInt[bits]]) {.tags: [VarTime, Alloca].} =
  ## In-place iterative EC FFT (Cooley-Tukey DIT - Decimation-In-Time)
  ## Input: bit-reversed order values
  ## Output: natural order values in Fourier domain
  ##
  ## DIT: Bit-reversed input → Natural output
  let n = output.len

  var length = 2
  while length <= n:
    let half = length shr 1
    let step = n div length

    var i = 0
    while i < n:
      var k = 0
      for j in 0 ..< half:
        var t {.noInit.}: EC
        t.scalarMul_vartime(rootsOfUnity[k], output[i + j + half])
        output[i + j + half].diff_vartime(output[i + j], t)
        output[i + j].sum_vartime(output[i + j], t)

        k += step
      i += length

    length = length shl 1

func ec_fft_nr_iterative[EC](
       desc: ECFFT_Descriptor[EC],
       output: var openarray[EC],
       vals: openarray[EC]): FFTStatus {.tags: [VarTime, Alloca], meter.} =
  ## EC FFT from natural order to bit-reversed order using iterative Cooley-Tukey DIF.
  ## Input: natural order values
  ## Output: bit-reversed order values in Fourier domain
  ## Domain: roots of unity (no shift)
  ##
  ## Algorithm: In-place iterative Cooley-Tukey FFT (DIF)
  ##
  ## This is faster than the recursive version for large sizes
  ## because it avoids function call overhead and has better cache patterns.
  ##
  ## **Supports in-place operation**: `output` and `vals` can be the same array.
  ## If they alias, the input copy is skipped for better performance.
  if vals.len > desc.order:
    return FFT_TooManyValues
  if output.len != vals.len:
    return FFT_InconsistentInputOutputLengths
  if not vals.len.uint64.isPowerOf2_vartime():
    return FFT_SizeNotPowerOfTwo

  let n = vals.len

  # Copy input to output (skip if aliasing for in-place operation)
  if output[0].addr != vals[0].addr:
    for i in 0 ..< n:
      output[i] = vals[i]

  # Get roots of unity with appropriate stride
  let rootz = desc.rootsOfUnity
                  .toStridedView(desc.order)
                  .slice(0, desc.order-1, desc.order shr log2_vartime(uint n))

  # In-place iterative DIF FFT
  var voutput = output.toStridedView()
  ec_fft_nr_impl_iterative_dif(voutput, rootz)

  return FFT_Success

func ec_fft_rn_iterative_dit[EC](
       desc: ECFFT_Descriptor[EC],
       output: var openarray[EC],
       vals: openarray[EC]): FFTStatus {.tags: [VarTime, Alloca], meter.} =
  ## EC FFT from bit-reversed order to natural order using iterative Cooley-Tukey DIT.
  ## Input: bit-reversed order values
  ## Output: natural order values in Fourier domain
  ## Domain: roots of unity (no shift)
  ##
  ## **Supports in-place operation**: `output` and `vals` can be the same array.
  ## If they alias, the input copy is skipped for better performance.
  if vals.len > desc.order:
    return FFT_TooManyValues
  if output.len != vals.len:
    return FFT_InconsistentInputOutputLengths
  if not vals.len.uint64.isPowerOf2_vartime():
    return FFT_SizeNotPowerOfTwo

  let n = vals.len

  # Copy input to output (skip if aliasing for in-place operation)
  if output[0].addr != vals[0].addr:
    for i in 0 ..< n:
      output[i] = vals[i]

  # Get roots of unity with appropriate stride
  let rootz = desc.rootsOfUnity
                  .toStridedView(desc.order)
                  .slice(0, desc.order-1, desc.order shr log2_vartime(uint n))

  # In-place iterative DIT FFT (bit-reversed → natural)
  var voutput = output.toStridedView()
  ec_fft_rn_impl_iterative_dit(voutput, rootz)

  return FFT_Success

func ec_ifft_rn_impl_iterative[EC; bits: static int](
       output: var StridedView[EC],
       rootsOfUnity: StridedView[BigInt[bits]]) {.tags: [VarTime, Alloca].} =
  ## In-place iterative EC IFFT (Cooley-Tukey DIT - Decimation-In-Time)
  ## Input: bit-reversed order values in Fourier domain
  ## Output: natural order values
  ##
  ## Uses inverse roots of unity and applies 1/n scaling at the end
  let n = output.len

  var length = 2
  while length <= n:
    let half = length shr 1
    let step = n div length

    var i = 0
    while i < n:
      var k = 0
      for j in 0 ..< half:
        var t {.noInit.}: EC
        t.scalarMul_vartime(rootsOfUnity[k], output[i + j + half])
        output[i + j + half].diff_vartime(output[i + j], t)
        output[i + j].sum_vartime(output[i + j], t)

        k += step
      i += length

    length = length shl 1

  # Apply 1/n scaling
  var invLen {.noInit.}: Fr[EC.getName()]
  invLen.fromUint(n.uint64)
  invLen.inv_vartime()

  for i in 0 ..< n:
    output[i].scalarMul_vartime(invLen.toBig())

func ec_ifft_rn_iterative_dit[EC](
       desc: ECFFT_Descriptor[EC],
       output: var openarray[EC],
       vals: openarray[EC]): FFTStatus {.tags: [VarTime, Alloca], meter.} =
  ## EC IFFT from bit-reversed order to natural order using iterative DIT.
  ## Input: bit-reversed order values in Fourier domain
  ## Output: natural order values
  ## Domain: roots of unity (no shift)
  ##
  ## Algorithm: In-place iterative DIT IFFT with inverse roots of unity
  ##
  ## **Supports in-place operation**: `output` and `vals` can be the same array.
  ## If they alias, the input copy is skipped for better performance.
  if vals.len > desc.order:
    return FFT_TooManyValues
  if output.len != vals.len:
    return FFT_InconsistentInputOutputLengths
  if not vals.len.uint64.isPowerOf2_vartime():
    return FFT_SizeNotPowerOfTwo

  let n = vals.len

  # Copy input to output (skip if aliasing for in-place operation)
  if output[0].addr != vals[0].addr:
    for i in 0 ..< n:
      output[i] = vals[i]

  # Get inverse roots of unity with appropriate stride (reversed order)
  let rootz = desc.rootsOfUnity
                  .toStridedView(desc.order+1)
                  .reversed()
                  .slice(0, desc.order-1, desc.order shr log2_vartime(uint n))

  # In-place iterative DIT IFFT (bit-reversed → natural)
  var voutput = output.toStridedView()
  ec_ifft_rn_impl_iterative(voutput, rootz)

  return FFT_Success

# ############################################################
#
#              FFT/IFFT Combinations
#
# ############################################################
# These combine core algorithms with bit-reversal for testing/benchmarks.
# Only used in tests and benchmarks - not in production dispatch.

proc ec_fft_nn_via_iterative_dif_and_bitrev[EC](
       desc: ECFFT_Descriptor[EC],
       output: var openarray[EC],
       vals: openarray[EC]): FFTStatus {.tags: [VarTime, HeapAlloc, Alloca], meter.} =
  ## Natural → Natural via: Iterative DIF (NR) + BitRev
  let status = ec_fft_nr_iterative(desc, output, vals)
  if status != FFT_Success: return status
  bit_reversal_permutation(output)
  return FFT_Success

proc ec_fft_nn_via_bitrev_and_iterative_dit[EC](
       desc: ECFFT_Descriptor[EC],
       output: var openarray[EC],
       vals: openarray[EC]): FFTStatus {.tags: [VarTime, HeapAlloc, Alloca], meter.} =
  ## Natural → Natural via: BitRev + Iterative DIT (RN)
  var br_vals = newSeq[EC](vals.len)
  bit_reversal_permutation(br_vals, vals)
  let status = ec_fft_rn_iterative_dit(desc, output, br_vals)
  return status

proc ec_ifft_nn_via_bitrev_and_iterative_dit[EC](
       desc: ECFFT_Descriptor[EC],
       output: var openarray[EC],
       vals: openarray[EC]): FFTStatus {.tags: [VarTime, HeapAlloc, Alloca], meter.} =
  ## Natural → Natural via: BitRev + Iterative DIT (RN)
  ## Input: natural order values in Fourier domain
  ## Output: natural order values
  bit_reversal_permutation(output, vals)
  let status = ec_ifft_rn_iterative_dit(desc, output, output)
  return status

# ############################################################
#
#              High-Level FFT API (Auto-dispatch)
#
# ############################################################
# These functions automatically dispatch to the fastest implementation.
# Use the specific implementations (fft_nr_recursive, fft_nr_iterative, etc.)
# if you need to test or benchmark individual algorithms.

func ec_fft_nr*[EC](
       desc: ECFFT_Descriptor[EC],
       output: var openarray[EC],
       vals: openarray[EC]): FFTStatus {.tags: [VarTime, Alloca], meter.} =
  ## EC FFT from natural order to bit-reversed order.
  ## Dispatches to: Iterative DIF directly
  ##
  ## **Supports in-place operation**: `output` and `vals` can be the same array.
  ec_fft_nr_iterative(desc, output, vals)

func ec_fft_nn*[EC](
       desc: ECFFT_Descriptor[EC],
       output: var openarray[EC],
       vals: openarray[EC]): FFTStatus {.inline, tags: [VarTime, HeapAlloc, Alloca], meter.} =
  ## EC FFT from natural order to natural order.
  ## Dispatches to: Iterative DIF (NR) + BitRev
  ##
  ## **Supports in-place operation**: `output` and `vals` can be the same array.
  let status = ec_fft_nr_iterative(desc, output, vals)
  if status != FFT_Success: return status
  bit_reversal_permutation(output)
  return status

func ec_ifft_nn*[EC](
       desc: ECFFT_Descriptor[EC],
       output: var openarray[EC],
       vals: openarray[EC]): FFTStatus {.inline, tags: [VarTime, HeapAlloc, Alloca], meter.} =
  ## EC IFFT from natural order to natural order.
  ## Dispatches to: BitRev + Iterative DIT
  ##
  ## **Supports in-place operation**: `output` and `vals` can be the same array.
  ec_ifft_nn_via_bitrev_and_iterative_dit(desc, output, vals)

func ec_ifft_rn*[EC](
       desc: ECFFT_Descriptor[EC],
       output: var openarray[EC],
       vals: openarray[EC]): FFTStatus {.tags: [VarTime, Alloca], meter.} =
  ## EC IFFT from bit-reversed order to natural order.
  ## Dispatches to: Iterative DIT directly
  ##
  ## **Supports in-place operation**: `output` and `vals` can be the same array.
  ec_ifft_rn_iterative_dit(desc, output, vals)
