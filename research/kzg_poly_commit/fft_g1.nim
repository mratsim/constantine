# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  ../../constantine/backend/config/curves,
  ../../constantine/backend/[arithmetic, primitives],
  ../../constantine/backend/elliptic/[
    ec_scalar_mul,
    ec_shortweierstrass_affine,
    ec_shortweierstrass_projective,
    ec_shortweierstrass_jacobian,
  ],
  ../../constantine/backend/io/[io_fields, io_ec],
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
# Other readable FFTs includes:
# - https://github.com/kwantam/fffft
# - https://github.com/ConsenSys/gnark/blob/master/internal/backend/bls381/fft/fft.go
# - https://github.com/poanetwork/threshold_crypto/blob/8820c11/src/poly_vals.rs#L332-L370
# - https://github.com/zkcrypto/bellman/blob/10c5010/src/domain.rs#L272-L315
# - Modern Computer Arithmetic, Brent and Zimmermann, p53 algorithm 2.2
#   https://members.loria.fr/PZimmermann/mca/mca-cup-0.5.9.pdf

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

  FFTDescriptor*[EC] = object
    ## Metadata for FFT on Elliptic Curve
    maxWidth: int
    rootOfUnity: matchingOrderBigInt(EC.F.C)
      ## The root of unity that generates all roots
    expandedRootsOfUnity: seq[matchingOrderBigInt(EC.F.C)]
      ## domain, starting and ending with 1

func expandRootOfUnity[F](rootOfUnity: F): auto {.noInit.} =
  ## From a generator root of unity
  ## expand to width + 1 values.
  ## (Last value is 1 for the reverse array)
  # For a field of order q, there are gcd(n, q−1)
  # nth roots of unity, a.k.a. solutions to xⁿ ≡ 1 (mod q)
  # but it's likely too long to compute bigint GCD
  # so embrace heap (re-)allocations.
  # Figuring out how to do to right size the buffers
  # in production will be fun.
  var r: seq[matchingOrderBigInt(F.C)]
  r.setLen(2)
  r[0].setOne()
  r[1] = rootOfUnity.toBig()

  var cur = rootOfUnity
  while not r[^1].isOne().bool:
    cur *= rootOfUnity
    r.setLen(r.len + 1)
    r[^1] = cur.toBig()

  return r

# FFT Algorithm
# ----------------------------------------------------------------

func simpleFT[EC; bits: static int](
       output: var View[EC],
       vals: View[EC],
       rootsOfUnity: View[BigInt[bits]]
     ) =
  # FFT is a recursive algorithm
  # This is the base-case using a O(n²) algorithm

  let L = output.len
  var last {.noInit.}, v {.noInit.}: EC

  for i in 0 ..< L:
    last = vals[0]
    last.scalarMul(rootsOfUnity[0])
    for j in 1 ..< L:
      v = vals[j]
      v.scalarMul(rootsOfUnity[(i*j) mod L])
      last += v
    output[i] = last

func fft_internal[EC; bits: static int](
       output: var View[EC],
       vals: View[EC],
       rootsOfUnity: View[BigInt[bits]]
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
  var y_times_root{.noinit.}: EC

  for i in 0 ..< half:
    # FFT Butterfly
    y_times_root = output[i+half]
    y_times_root   .scalarMul(rootsOfUnity[i])
    output[i+half] .diff(output[i], y_times_root)
    output[i]      += y_times_root

func fft*[EC](
       desc: FFTDescriptor[EC],
       output: var openarray[EC],
       vals: openarray[EC]): FFT_Status =
  if vals.len > desc.maxWidth:
    return FFTS_TooManyValues
  if not vals.len.uint64.isPowerOf2_vartime():
    return FFTS_SizeNotPowerOfTwo

  let rootz = desc.expandedRootsOfUnity
                  .toView()
                  .slice(0, desc.maxWidth-1, desc.maxWidth div vals.len)

  var voutput = output.toView()
  fft_internal(voutput, vals.toView(), rootz)
  return FFTS_Success

func ifft*[EC](
       desc: FFTDescriptor[EC],
       output: var openarray[EC],
       vals: openarray[EC]): FFT_Status =
  ## Inverse FFT
  if vals.len > desc.maxWidth:
    return FFTS_TooManyValues
  if not vals.len.uint64.isPowerOf2_vartime():
    return FFTS_SizeNotPowerOfTwo

  let rootz = desc.expandedRootsOfUnity
                  .toView()
                  .reversed()
                  .slice(0, desc.maxWidth-1, desc.maxWidth div vals.len)

  var voutput = output.toView()
  fft_internal(voutput, vals.toView(), rootz)

  var invLen {.noInit.}: Fr[EC.F.C]
  invLen.fromUint(vals.len.uint64)
  invLen.inv()
  let inv = invLen.toBig()

  for i in 0..< output.len:
    output[i].scalarMul(inv)

  return FFTS_Success

# FFT Descriptor
# ----------------------------------------------------------------

proc init*(T: type FFTDescriptor, maxScale: uint8): T =
  result.maxWidth = 1 shl maxScale

  let root = scaleToRootOfUnity(T.EC.F.C)[maxScale]
  result.rootOfUnity = root.toBig()
  result.expandedRootsOfUnity = root.expandRootOfUnity()
    # Aren't you tired of reading about unity?

# ############################################################
#
#                    Sanity checks
#
# ############################################################

{.experimental: "views".}

when isMainModule:
  import
    std/[times, monotimes, strformat],
    ../../helpers/prng_unsafe

  type G1 = ECP_ShortW_Prj[Fp[BLS12_381], G1]
  var Generator1: ECP_ShortW_Aff[Fp[BLS12_381], G1]
  doAssert Generator1.fromHex(
    "0x17f1d3a73197d7942695638c4fa9ac0fc3688c4f9774b905a14e3a3f171bac586c55e83ff97a1aeffb3af00adb22c6bb",
    "0x08b3f481e3aaa0f1a09e30ed741d8ae4fcf5e095d5d00af600db18cb2c04b3edd03cc744a2888ae40caa232946c5e7e1"
  )

  proc roundtrip() =
    let fftDesc = FFTDescriptor[G1].init(maxScale = 4)
    var data = newSeq[G1](fftDesc.maxWidth)
    data[0].fromAffine(Generator1)
    for i in 1 ..< fftDesc.maxWidth:
      data[i].madd(data[i-1], Generator1)

    var coefs = newSeq[G1](data.len)
    let fftOk = fft(fftDesc, coefs, data)
    doAssert fftOk == FFTS_Success
    # display("coefs", 0, coefs)

    var res = newSeq[G1](data.len)
    let ifftOk = ifft(fftDesc, res, coefs)
    doAssert ifftOk == FFTS_Success
    # display("res", 0, coefs)

    for i in 0 ..< res.len:
      if bool(res[i] != data[i]):
        echo "Error: expected ", data[i].toHex(), " but got ", res[i].toHex()
        quit 1

    echo "FFT round-trip check SUCCESS"

  proc warmup() =
    # Warmup - make sure cpu is on max perf
    let start = cpuTime()
    var foo = 123
    for i in 0 ..< 300_000_000:
      foo += i*i mod 456
      foo = foo mod 789

    # Compiler shouldn't optimize away the results as cpuTime rely on sideeffects
    let stop = cpuTime()
    echo &"Warmup: {stop - start:>4.4f} s, result {foo} (displayed to avoid compiler optimizing warmup away)\n"


  proc bench() =
    echo "Starting benchmark ..."
    const NumIters = 3

    var rng: RngState
    rng.seed 0x1234
    # TODO: view types complain about mutable borrow
    # in `random_unsafe` due to pseudo view type LimbsViewMut
    # (which was views before Nim properly supported them)

    warmup()

    for scale in 4 ..< 10:
      # Setup

      let desc = FFTDescriptor[G1].init(uint8 scale)
      var data = newSeq[G1](desc.maxWidth)
      data[0].fromAffine(Generator1)
      for i in 1 ..< desc.maxWidth:
        data[i].madd(data[i-1], Generator1)

      var coefsOut = newSeq[G1](data.len)

      # Bench
      let start = getMonotime()
      for i in 0 ..< NumIters:
        let status = desc.fft(coefsOut, data)
        doAssert status == FFTS_Success
      let stop = getMonotime()

      let ns = inNanoseconds((stop-start) div NumIters)
      echo &"FFT scale {scale:>2}     {ns:>8} ns/op"

  roundtrip()
  warmup()
  bench()
