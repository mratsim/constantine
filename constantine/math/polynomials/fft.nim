# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  ../config/curves,
  ../arithmetic,
  ../ec_shortweierstrass,
  ../elliptic/ec_scalar_mul_vartime,
  ../../platforms/[abstractions, allocs, views]

# ############################################################
#
#               Fast Fourier Transform
#
# ############################################################

# Elliptic curve Fast Fourier Transform
# ----------------------------------------------------------------

type
  FFTStatus = enum
    FFTS_Success
    FFTS_TooManyValues = "Input length greater than the field 2-adicity (number of roots of unity)"
    FFTS_SizeNotPowerOfTwo = "Input must be of a power of 2 length"

  ECFFT_Descriptor*[EC] = object
    ## Metadata for FFT on Elliptic Curve
    order*: int
    rootsOfUnity*: ptr UncheckedArray[matchingOrderBigInt(EC.F.C)]
      ## domain, starting and ending with 1, length cardinality+1
      ## This allows FFT and inverse FFT to use the same buffer for roots.

func computeRootsOfUnity[EC](ctx: var ECFFT_Descriptor[EC], generatorRootOfUnity: auto) =
  static: doAssert typeof(generatorRootOfUnity) is Fr[EC.F.C]

  ctx.rootsOfUnity[0].setOne()

  var cur = generatorRootOfUnity
  for i in 1 .. ctx.order:
    ctx.rootsOfUnity[i].fromField(cur)
    cur *= generatorRootOfUnity

  doAssert ctx.rootsOfUnity[ctx.order].isOne().bool()

func new*(T: type ECFFT_Descriptor, order: int, generatorRootOfUnity: auto): T =
  result.order = order
  result.rootsOfUnity = allocHeapArrayAligned(matchingOrderBigInt(T.EC.F.C), order+1, alignment = 64)

  result.computeRootsOfUnity(generatorRootOfUnity)

func simpleFT[EC; bits: static int](
       output: var StridedView[EC],
       vals: StridedView[EC],
       rootsOfUnity: StridedView[BigInt[bits]]) =
  # FFT is a recursive algorithm
  # This is the base-case using a O(n²) algorithm

  # TODO: endomorphism acceleration for windowed-NAF

  let L = output.len
  var last {.noInit.}, v {.noInit.}: EC

  for i in 0 ..< L:
    last = vals[0]
    last.scalarMul_minHammingWeight_windowed_vartime(rootsOfUnity[0], window = 5)
    for j in 1 ..< L:
      v = vals[j]
      v.scalarMul_minHammingWeight_windowed_vartime(rootsOfUnity[(i*j) mod L], window = 5)
      last += v
    output[i] = last

func fft_internal[EC; bits: static int](
       output: var StridedView[EC],
       vals: StridedView[EC],
       rootsOfUnity: StridedView[BigInt[bits]]
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
    y_times_root   .scalarMul_minHammingWeight_windowed_vartime(rootsOfUnity[i], window = 5)
    output[i+half] .diff(output[i], y_times_root)
    output[i]      += y_times_root

func fft*[EC](
       desc: ECFFT_Descriptor[EC],
       output: var openarray[EC],
       vals: openarray[EC]): FFT_Status =
  if vals.len > desc.order:
    return FFTS_TooManyValues
  if not vals.len.uint64.isPowerOf2_vartime():
    return FFTS_SizeNotPowerOfTwo

  let rootz = desc.rootsOfUnity
                  .toStridedView(desc.order)
                  .slice(0, desc.order-1, desc.order div vals.len)

  var voutput = output.toStridedView()
  fft_internal(voutput, vals.toStridedView(), rootz)
  return FFTS_Success

func ifft*[EC](
       desc: ECFFT_Descriptor[EC],
       output: var openarray[EC],
       vals: openarray[EC]): FFT_Status =
  ## Inverse FFT
  if vals.len > desc.order:
    return FFTS_TooManyValues
  if not vals.len.uint64.isPowerOf2_vartime():
    return FFTS_SizeNotPowerOfTwo

  let rootz = desc.rootsOfUnity
                  .toStridedView(desc.order+1) # Extra 1 at the end so that when reversed the buffer starts with 1
                  .reversed()
                  .slice(0, desc.order-1, desc.order div vals.len)

  var voutput = output.toStridedView()
  fft_internal(voutput, vals.toStridedView(), rootz)

  var invLen {.noInit.}: Fr[EC.F.C]
  invLen.fromUint(vals.len.uint64)
  invLen.inv_vartime()
  let inv = invLen.toBig()

  for i in 0 ..< output.len:
    output[i].scalarMul_minHammingWeight_windowed_vartime(inv, window = 5)

  return FFTS_Success

# ############################################################
#
#                   Bit reversal permutations
#
# ############################################################
# - Towards an Optimal Bit-Reversal Permutation Program
#   Larry Carter and Kang Su Gatlin, 1998
#   https://csaws.cs.technion.ac.il/~itai/Courses/Cache/bit.pdf
#
# - Practically efficient methods for performing bit-reversed
#   permutation in C++11 on the x86-64 architecture
#   Knauth, Adas, Whitfield, Wang, Ickler, Conrad, Serang, 2017
#   https://arxiv.org/pdf/1708.01873.pdf

func deriveLogTileSize(T: typedesc): int =
  ## Returns the log of the tile size
  # `lscpu` can return correct values.
  # We underestimate modern cache sizes so that performance is good even on older architectures.
  const cacheLine = 64     # Size of a cache line
  const l1Size = 32 * 1024 # Size of L1 cache
  const elems_per_cacheline = max(1, cacheLine div sizeof(T))

  var q = l1Size div sizeof(T)
  q = q div 2 # use only half of the cache, this limits cache eviction, especially with hyperthreading.
  q = q.uint32.nextPowerOfTwo_vartime().log2_vartime().int
  q = q div 2 # 2²𐞥 should be smaller than the cache

  # If the cache line can accomodate spare elements
  #
  while 1 shl q < elems_per_cacheline:
    q += 1

  return

func bit_reversal_permutation[N: static int, T](buf: array[N, T]) =
  ## Bit reversal permutation using a cache-blocking algorithm

# ############################################################
#
#                    Sanity checks
#
# ############################################################

when isMainModule:

  import
    std/[times, monotimes, strformat],
    ../../../helpers/prng_unsafe,
    ../constants/zoo_generators,
    ../io/[io_fields, io_ec]

  const ctt_eth_kzg_fr_pow2_roots_of_unity = [
    # primitive_root⁽ᵐᵒᵈᵘˡᵘˢ⁻¹⁾/⁽²^ⁱ⁾ for i in [0, 32)
    # The primitive root chosen is 7
    Fr[BLS12_381].fromHex"0x1",
    Fr[BLS12_381].fromHex"0x73eda753299d7d483339d80809a1d80553bda402fffe5bfeffffffff00000000",
    Fr[BLS12_381].fromHex"0x8d51ccce760304d0ec030002760300000001000000000000",
    Fr[BLS12_381].fromHex"0x345766f603fa66e78c0625cd70d77ce2b38b21c28713b7007228fd3397743f7a",
    Fr[BLS12_381].fromHex"0x20b1ce9140267af9dd1c0af834cec32c17beb312f20b6f7653ea61d87742bcce",
    Fr[BLS12_381].fromHex"0x50e0903a157988bab4bcd40e22f55448bf6e88fb4c38fb8a360c60997369df4e",
    Fr[BLS12_381].fromHex"0x45af6345ec055e4d14a1e27164d8fdbd2d967f4be2f951558140d032f0a9ee53",
    Fr[BLS12_381].fromHex"0x6898111413588742b7c68b4d7fdd60d098d0caac87f5713c5130c2c1660125be",
    Fr[BLS12_381].fromHex"0x4f9b4098e2e9f12e6b368121ac0cf4ad0a0865a899e8deff4935bd2f817f694b",
    Fr[BLS12_381].fromHex"0x95166525526a65439feec240d80689fd697168a3a6000fe4541b8ff2ee0434e",
    Fr[BLS12_381].fromHex"0x325db5c3debf77a18f4de02c0f776af3ea437f9626fc085e3c28d666a5c2d854",
    Fr[BLS12_381].fromHex"0x6d031f1b5c49c83409f1ca610a08f16655ea6811be9c622d4a838b5d59cd79e5",
    Fr[BLS12_381].fromHex"0x564c0a11a0f704f4fc3e8acfe0f8245f0ad1347b378fbf96e206da11a5d36306",
    Fr[BLS12_381].fromHex"0x485d512737b1da3d2ccddea2972e89ed146b58bc434906ac6fdd00bfc78c8967",
    Fr[BLS12_381].fromHex"0x56624634b500a166dc86b01c0d477fa6ae4622f6a9152435034d2ff22a5ad9e1",
    Fr[BLS12_381].fromHex"0x3291357ee558b50d483405417a0cbe39c8d5f51db3f32699fbd047e11279bb6e",
    Fr[BLS12_381].fromHex"0x2155379d12180caa88f39a78f1aeb57867a665ae1fcadc91d7118f85cd96b8ad",
    Fr[BLS12_381].fromHex"0x224262332d8acbf4473a2eef772c33d6cd7f2bd6d0711b7d08692405f3b70f10",
    Fr[BLS12_381].fromHex"0x2d3056a530794f01652f717ae1c34bb0bb97a3bf30ce40fd6f421a7d8ef674fb",
    Fr[BLS12_381].fromHex"0x520e587a724a6955df625e80d0adef90ad8e16e84419c750194e8c62ecb38d9d",
    Fr[BLS12_381].fromHex"0x3e1c54bcb947035a57a6e07cb98de4a2f69e02d265e09d9fece7e0e39898d4b",
    Fr[BLS12_381].fromHex"0x47c8b5817018af4fc70d0874b0691d4e46b3105f04db5844cd3979122d3ea03a",
    Fr[BLS12_381].fromHex"0xabe6a5e5abcaa32f2d38f10fbb8d1bbe08fec7c86389beec6e7a6ffb08e3363",
    Fr[BLS12_381].fromHex"0x73560252aa0655b25121af06a3b51e3cc631ffb2585a72db5616c57de0ec9eae",
    Fr[BLS12_381].fromHex"0x291cf6d68823e6876e0bcd91ee76273072cf6a8029b7d7bc92cf4deb77bd779c",
    Fr[BLS12_381].fromHex"0x19fe632fd3287390454dc1edc61a1a3c0ba12bb3da64ca5ce32ef844e11a51e",
    Fr[BLS12_381].fromHex"0xa0a77a3b1980c0d116168bffbedc11d02c8118402867ddc531a11a0d2d75182",
    Fr[BLS12_381].fromHex"0x23397a9300f8f98bece8ea224f31d25db94f1101b1d7a628e2d0a7869f0319ed",
    Fr[BLS12_381].fromHex"0x52dd465e2f09425699e276b571905a7d6558e9e3f6ac7b41d7b688830a4f2089",
    Fr[BLS12_381].fromHex"0xc83ea7744bf1bee8da40c1ef2bb459884d37b826214abc6474650359d8e211b",
    Fr[BLS12_381].fromHex"0x2c6d4e4511657e1e1339a815da8b398fed3a181fabb30adc694341f608c9dd56",
    Fr[BLS12_381].fromHex"0x4b5371495990693fad1715b02e5713b5f070bb00e28a193d63e7cb4906ffc93f"
  ]

  type EC_G1 = ECP_ShortW_Prj[Fp[BLS12_381], G1]

  proc roundtrip() =
    let fftDesc = ECFFT_Descriptor[EC_G1].new(order = 1 shl 4, ctt_eth_kzg_fr_pow2_roots_of_unity[4])
    var data = newSeq[EC_G1](fftDesc.order)
    data[0].fromAffine(BLS12_381.getGenerator("G1"))
    for i in 1 ..< fftDesc.order:
      data[i].madd(data[i-1], BLS12_381.getGenerator("G1"))

    var coefs = newSeq[EC_G1](data.len)
    let fftOk = fft(fftDesc, coefs, data)
    doAssert fftOk == FFTS_Success
    # display("coefs", 0, coefs)

    var res = newSeq[EC_G1](data.len)
    let ifftOk = ifft(fftDesc, res, coefs)
    doAssert ifftOk == FFTS_Success
    # display("res", 0, res)

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

      let fftDesc = ECFFTDescriptor[EC_G1].new(order = 1 shl scale, ctt_eth_kzg_fr_pow2_roots_of_unity[scale])
      var data = newSeq[EC_G1](fftDesc.order)
      data[0].fromAffine(BLS12_381.getGenerator("G1"))
      for i in 1 ..< fftDesc.order:
        data[i].madd(data[i-1], BLS12_381.getGenerator("G1"))

      var coefsOut = newSeq[EC_G1](data.len)

      # Bench
      let start = getMonotime()
      for i in 0 ..< NumIters:
        let status = fftDesc.fft(coefsOut, data)
        doAssert status == FFTS_Success
      let stop = getMonotime()

      let ns = inNanoseconds((stop-start) div NumIters)
      echo &"FFT scale {scale:>2}     {ns:>8} ns/op"

  roundtrip()
  warmup()
  bench()
