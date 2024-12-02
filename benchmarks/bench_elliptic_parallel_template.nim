# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  # Internals
  constantine/named/algebras,
  constantine/math/arithmetic,
  constantine/math/elliptic/[
    ec_shortweierstrass_affine,
    ec_shortweierstrass_projective,
    ec_shortweierstrass_jacobian,
    ec_shortweierstrass_jacobian_extended,
    ec_shortweierstrass_batch_ops_parallel,
    ec_multi_scalar_mul,
    ec_scalar_mul, ec_scalar_mul_vartime,
    ec_multi_scalar_mul_parallel],
  constantine/named/zoo_subgroups,
  # Threadpool
  constantine/threadpool/[threadpool, partitioners],
  # Helpers
  helpers/prng_unsafe,
  ./bench_elliptic_template,
  ./bench_blueprint

export bench_elliptic_template

from std / math import divmod
proc random_coefficient*[N: static int](rng: var RngState, maxBit: int = 0): BigInt[N] =
  ## Initializes a random BigInt[N] with `maxBit` as the most significant bit
  ## of it.
  ## If `maxBit` is set to zero, the coefficient will utilize all bits.
  const WordSize = 64
  let toShift = result.limbs.len * WordSize - maxBit
  let (d, r) = divmod(toShift, WordSize) # how many limbs to zero & how many bits in next limb
  result = rng.random_unsafe(BigInt[N])
  if maxBit == 0 or maxBit >= N: return # use all bits
  let limbs = result.limbs.len
  for i in countdown(limbs-1, limbs - d):
    result.limbs[i] = SecretWord(0'u64)  # zero most significant limbs
  result.shiftRight(r)                   # shift right by remaining required


# ############################################################
#
#             Parallel Benchmark definitions
#
# ############################################################

proc multiAddParallelBench*(EC: typedesc, numInputs: int, iters: int) =
  var points = newSeq[EC_ShortW_Aff[EC.F, EC.G]](numInputs)

  for i in 0 ..< numInputs:
    points[i] = rng.random_unsafe(EC_ShortW_Aff[EC.F, EC.G])

  var r{.noInit.}: EC

  let tp = Threadpool.new()

  bench("EC parallel batch add  (" & align($tp.numThreads, 2) & " threads)   " & $EC.G & " (" & $numInputs & " points)", EC, iters):
    tp.sum_reduce_vartime_parallel(r, points)

  tp.shutdown()

# Multi-scalar multiplication
# ---------------------------------------------------------------------------

type BenchMsmContext*[EC] = object
  tp: Threadpool
  numInputs*: int
  coefs*: seq[getBigInt(EC.getName(), kScalarField)]
  points*: seq[affine(EC)]

proc createBenchMsmContext*(EC: typedesc, inputSizes: openArray[int],
                            maxBit = 0): BenchMsmContext[EC] =
  ## `maxBit` sets the maximum bit set in the coefficients that are randomly sampled.
  ## Useful to benchmark MSM with many leading zeroes.
  result.tp = Threadpool.new()
  let maxNumInputs = inputSizes.max()

  const bits = EC.getScalarField().bits()
  type ECaff = affine(EC)

  result.numInputs = maxNumInputs
  result.points = newSeq[ECaff](maxNumInputs)
  result.coefs = newSeq[BigInt[bits]](maxNumInputs)

  proc genCoefPointPairsChunk[EC, ECaff](rngSeed: uint64, start, len: int,
                                         points: ptr ECaff,
                                         coefs: ptr BigInt[bits], maxBit: int) {.nimcall.} =
    let points = cast[ptr UncheckedArray[ECaff]](points)
    let coefs = cast[ptr UncheckedArray[BigInt[bits]]](coefs)

    # RNGs are not threadsafe, create a threadlocal one seeded from the global RNG
    var threadRng: RngState
    threadRng.seed(rngSeed)

    for i in start ..< start + len:
      var tmp = threadRng.random_unsafe(EC)
      tmp.clearCofactor()
      points[i].affine(tmp)
      coefs[i] = random_coefficient[bits](threadRng, maxBit)

  let chunks = balancedChunksPrioNumber(0, maxNumInputs, result.tp.numThreads)


  stdout.write &"Generating {maxNumInputs} (coefs, points) pairs ... "
  stdout.flushFile()

  let start = getMonotime()

  syncScope:
    for (id, start, size) in items(chunks):
      result.tp.spawn genCoefPointPairsChunk[EC, ECaff](
        rng.next(), start, size,
        result.points[0].addr, result.coefs[0].addr, maxBit
      )

  # Even if child threads are sleeping, it seems like perf is lower when there are threads around
  # maybe because the kernel has more overhead or time quantum to keep track off so shut them down.
  result.tp.shutdown()

  let stop = getMonotime()
  stdout.write &"in {float64(inNanoSeconds(stop-start)) / 1e6:6.3f} ms\n"

proc msmParallelBench*[EC](ctx: var BenchMsmContext[EC], numInputs: int, iters: int) =
  const bits = EC.getScalarField().bits()
  type ECaff = affine(EC)

  template coefs: untyped = ctx.coefs.toOpenArray(0, numInputs-1)
  template points: untyped = ctx.points.toOpenArray(0, numInputs-1)


  var r{.noInit.}: EC
  var startNaive, stopNaive, startMSMbaseline, stopMSMbaseline, startMSMopt, stopMSMopt, startMSMpara, stopMSMpara: MonoTime

  if numInputs <= 100000:
    # startNaive = getMonotime()
    bench("EC scalar muls                " & align($numInputs, 10) & " (" & $bits & "-bit coefs, points)", EC, iters):
      var tmp: EC
      r.setNeutral()
      for i in 0 ..< points.len:
        tmp.fromAffine(points[i])
        tmp.scalarMul(coefs[i])
        r += tmp
    # stopNaive = getMonotime()

  if numInputs <= 100000:
    startNaive = getMonotime()
    bench("EC scalar muls vartime        " & align($numInputs, 10) & " (" & $bits & "-bit coefs, points)", EC, iters):
      var tmp: EC
      r.setNeutral()
      for i in 0 ..< points.len:
        tmp.fromAffine(points[i])
        tmp.scalarMul_vartime(coefs[i])
        r += tmp
    stopNaive = getMonotime()

  if numInputs <= 100000:
    startMSMbaseline = getMonotime()
    bench("EC multi-scalar-mul baseline  " & align($numInputs, 10) & " (" & $bits & "-bit coefs, points)", EC, iters):
      r.multiScalarMul_reference_vartime(coefs, points)
    stopMSMbaseline = getMonotime()

  block:
    startMSMopt = getMonotime()
    bench("EC multi-scalar-mul optimized " & align($numInputs, 10) & " (" & $bits & "-bit coefs, points)", EC, iters):
      r.multiScalarMul_vartime(coefs, points)
    stopMSMopt = getMonotime()

  block:
    ctx.tp = Threadpool.new()

    startMSMpara = getMonotime()
    bench("EC multi-scalar-mul" & align($ctx.tp.numThreads & " threads", 11) & align($numInputs, 10) & " (" & $bits & "-bit coefs, points)", EC, iters):
      ctx.tp.multiScalarMul_vartime_parallel(r, coefs, points)
    stopMSMpara = getMonotime()

    ctx.tp.shutdown()

  let perfNaive = inNanoseconds((stopNaive-startNaive) div iters)
  let perfMSMbaseline = inNanoseconds((stopMSMbaseline-startMSMbaseline) div iters)
  let perfMSMopt = inNanoseconds((stopMSMopt-startMSMopt) div iters)
  let perfMSMpara = inNanoseconds((stopMSMpara-startMSMpara) div iters)

  if numInputs <= 100000:
    let speedupBaseline = float(perfNaive) / float(perfMSMbaseline)
    echo &"Speedup ratio baseline over naive linear combination: {speedupBaseline:>6.3f}x"

    let speedupOpt = float(perfNaive) / float(perfMSMopt)
    echo &"Speedup ratio optimized over naive linear combination: {speedupOpt:>6.3f}x"

    let speedupOptBaseline = float(perfMSMbaseline) / float(perfMSMopt)
    echo &"Speedup ratio optimized over baseline linear combination: {speedupOptBaseline:>6.3f}x"

  let speedupParaOpt = float(perfMSMopt) / float(perfMSMpara)
  echo &"Speedup ratio parallel over optimized linear combination: {speedupParaOpt:>6.3f}x"
