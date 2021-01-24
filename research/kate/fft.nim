# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  ../../constantine/config/curves,
  ../../constantine/[arithmetic, primitives],
  ../../constantine/io/io_fields,
  # Research
  ./strided_views,
  ./fft_lut

# See: https://github.com/ethereum/research/blob/master/kzg_data_availability/fft.py
# Quirks of the Python impl:
# - no tests of FFT alone?
# - a lot of "if type(x) == tuple else"
#
# See: https://github.com/protolambda/go-kate/blob/7bb4684/fft_fr.go#L19-L21
# The go port uses stride+offset to deal with skip iterator.
#
# Other readable FFT includes:
# - https://github.com/kwantam/fffft
# - https://github.com/ConsenSys/gnark/blob/master/internal/backend/bls381/fft/fft.go

# ############################################################
#
#            Finite-Field Fast Fourier Transform
#
# ############################################################
#
# This is a research, unoptimized implementation of
# Finite Field Fast Fourier Transform

# In research phase we tolerate using
# - garbage collected types
# - and exceptions for fast prototyping
#
# In particular, in production all signed integers
# must be verified not to overflow
# and should not throw (or use unsigned)

# FFT Context
# ----------------------------------------------------------------

type
  FFTStatus = enum
    FFTS_Success
    FFTS_TooManyValues = "Input length greater than the field 2-adicity (number of roots of unity)"
    FFTS_SizeNotPowerOfTwo = "Input must be of a power of 2 length"

  FFTDescriptor[F] = object
    ## Metadata for FFT on field F
    maxWidth: int
    rootOfUnity: F
      ## The root of unity that generates all roots
    expandedRootsOfUnity: seq[F]
      ## domain, starting and ending with 1

func isPowerOf2(n: SomeUnsignedInt): bool =
  (n and (n - 1)) == 0

func nextPowerOf2(n: uint64): uint64 =
  ## Returns x if x is a power of 2
  ## or the next biggest power of 2
  1'u64 shl (log2(n-1) + 1)

func expandRootOfUnity[F](rootOfUnity: F): seq[F] =
  ## From a generator root of unity
  ## expand to width + 1 values.
  ## (Last value is 1 for the reverse array)
  # For a field of order q, there are gcd(n, q−1)
  # nth roots of unity, a.k.a. solutions to xⁿ ≡ 1 (mod q)
  # but it's likely too long to compute bigint GCD
  # so embrace heap (re-)allocations.
  # Figuring out how to do to right size the buffers
  # in production will be fun.
  result.setLen(2)
  result[0].setOne()
  result[1] = rootOfUnity
  while not result[^1].isOne().bool:
    result.setLen(result.len + 1)
    result[^1].prod(result[^2], rootOfUnity)

# FFT Algorithm
# ----------------------------------------------------------------

# TODO: research Decimation in Time and Decimation in Frequency
#       and FFT butterflies

func simpleFT[F](
       output: var View[F],
       vals: View[F],
       rootsOfUnity: View[F]
     ) =
  # FFT is a recursive algorithm
  # This is the base-case using a O(n²) algorithm

  var L = output.len

  var last {.noInit.}: F

  for i in 0 ..< L:
    last.prod(vals[0], rootsOfUnity[0])
    for j in 1 ..< L:
      var v {.noInit.}: F
      v.prod(vals[j], rootsOfUnity[(i*j) mod L])
      last += v
    output[i] = last

func fft_internal[F](
       output: var View[F],
       vals: View[F],
       rootsOfUnity: View[F]
     ) =
  if output.len <= 4:
    simpleFT(output, vals, rootsOfUnity)
    return

  # Recursive Divide-and-Conquer
  let (evenVals, oddVals) = vals.splitAlternate()
  var (outLeft, outRight) = output.splitMiddle()
  let halfROI = rootsOfUnity.skipHalf()

  fft_internal(outLeft, evenVals, halfROI)
  fft_internal(outRight, oddVals, halfROI)

  let half = outLeft.len
  for i in 0 ..< half:
    # FFT Butterfly (is that right?)
    var y_times_root{.noinit.}: F
    y_times_root.prod(output[half], rootsOfUnity[i])
    output[i]      += y_times_root
    output[i+half] -= y_times_root

func fft*[F](
       desc: FFTDescriptor[F],
       output: var openarray[F],
       vals: openarray[F]): FFT_Status =
  if vals.len > desc.maxWidth:
    return FFTS_TooManyValues
  if not vals.len.uint64.isPowerOf2():
    return FFTS_SizeNotPowerOfTwo

  let rootz = desc.expandedRootsOfUnity
                  .toView()
                  .slice(0, desc.maxWidth-1, desc.maxWidth div vals.len)

  var voutput = output.toView()
  fft_internal(voutput, vals.toView(), rootz)
  return FFTS_Success

func ifft*[F](
       desc: FFTDescriptor[F],
       output: var openarray[F],
       vals: openarray[F]): FFT_Status =
  ## Inverse FFT
  if vals.len > desc.maxWidth:
    return FFTS_TooManyValues
  if not vals.len.uint64.isPowerOf2():
    return FFTS_SizeNotPowerOfTwo

  let rootz = desc.expandedRootsOfUnity
                  .toView()
                  .reversed()
                  .slice(0, desc.maxWidth-1, desc.maxWidth div vals.len)

  var voutput = output.toView()
  fft_internal(voutput, vals.toView(), rootz)

  var invLen {.noInit.}: F
  invLen.fromUint(vals.len.uint64)
  invLen.inv()

  for i in 0..< output.len:
    output[i] *= invLen

  return FFTS_Success

# FFT Descriptor
# ----------------------------------------------------------------

proc init*(T: type FFTDescriptor, maxScale: uint8): T =
  result.maxWidth = 1 shl maxScale
  result.rootOfUnity = scaleToRootOfUnity(T.F.C)[maxScale]
  result.expandedRootsOfUnity =
    result.rootOfUnity.expandRootOfUnity()
    # Aren't you tired of reading about unity?

# ############################################################
#
#                    Sanity checks
#
# ############################################################

{.experimental: "views".}

when isMainModule:
  proc roundtrip() =
    let fftDesc = FFTDescriptor[Fr[BLS12_381]].init(maxScale = 4)
    var data = newSeq[Fr[BLS12_381]](fftDesc.maxWidth)
    for i in 0 ..< fftDesc.maxWidth:
      data[i].fromUint i.uint64

    var coefs = newSeq[Fr[BLS12_381]](data.len)
    let fftOk = fft(fftDesc, coefs, data)
    doAssert fftOk == FFTS_Success

    var res = newSeq[Fr[BLS12_381]](data.len)
    let ifftOk = ifft(fftDesc, res, coefs)
    doAssert ifftOk == FFTS_Success

    for i in 0 ..< res.len:
      if bool(res[i] != data[i]):
        echo "Error: expected ", data[i].toHex(), " but got ", res[i].toHex()

  roundtrip()
