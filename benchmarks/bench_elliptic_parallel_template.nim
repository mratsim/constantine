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
    ec_shortweierstrass_batch_ops,
    ec_multi_scalar_mul,
    ec_scalar_mul, ec_scalar_mul_vartime,
    ec_multi_scalar_mul_parallel,
    ec_multi_scalar_mul_precomp],
  constantine/named/zoo_subgroups,
  # Threadpool
  constantine/threadpool/[threadpool, partitioners],
  # Helpers
  helpers/prng_unsafe,
  ./bench_elliptic_template,
  ./bench_blueprint

export bench_elliptic_template

# ############################################################
#
#             Parallel Benchmark definitions
#
# ############################################################

proc multiAddParallelBench*(EC: typedesc, numInputs: int, iters: int) {.noinline.} =
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
  numInputs: int
  coefs: seq[getBigInt(EC.getName(), kScalarField)]
  points: seq[affine(EC)]

type MsmParallelBenchResult* = object
  perfNaive*, perfMSMbaseline*, perfMSMopt*, perfMSMpara*: float64

proc createBenchMsmContext*(EC: typedesc, inputSizes: openArray[int]): BenchMsmContext[EC] {.noinline.} =
  result.tp = Threadpool.new()
  let maxNumInputs = inputSizes.max()

  const bits = EC.getScalarField().bits()
  type ECaff = affine(EC)

  result.numInputs = maxNumInputs
  result.points = newSeq[ECaff](maxNumInputs)
  result.coefs = newSeq[BigInt[bits]](maxNumInputs)

  proc genCoefPointPairsChunk[EC, ECaff](rngSeed: uint64, start, len: int, points: ptr ECaff, coefs: ptr BigInt[bits]) {.nimcall.} =
    let points = cast[ptr UncheckedArray[ECaff]](points)
    let coefs = cast[ptr UncheckedArray[BigInt[bits]]](coefs)

    # RNGs are not threadsafe, create a threadlocal one seeded from the global RNG
    var threadRng: RngState
    threadRng.seed(rngSeed)

    for i in start ..< start + len:
      var tmp = threadRng.random_unsafe(EC)
      tmp.clearCofactor()
      points[i].affine(tmp)
      coefs[i] = threadRng.random_unsafe(BigInt[bits])

  let chunks = balancedChunksPrioNumber(0, maxNumInputs, result.tp.numThreads)


  stdout.write &"Generating {maxNumInputs} (coefs, points) pairs ... "
  stdout.flushFile()

  let start = getMonotime()

  syncScope:
    for (id, start, size) in items(chunks):
      result.tp.spawn genCoefPointPairsChunk[EC, ECaff](rng.next(), start, size, result.points[0].addr, result.coefs[0].addr)

  # Even if child threads are sleeping, it seems like perf is lower when there are threads around
  # maybe because the kernel has more overhead or time quantum to keep track off so shut them down.
  result.tp.shutdown()

  let stop = getMonotime()
  stdout.write &"in {float64(inNanoSeconds(stop-start)) / 1e6:6.3f} ms\n"

proc msmParallelBench*[EC](ctx: var BenchMsmContext[EC], numInputs: int, iters: int): MsmParallelBenchResult =
  const bits = EC.getScalarField().bits()


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

  result.perfNaive = float64(inNanoseconds((stopNaive-startNaive) div iters))
  result.perfMSMbaseline = float64(inNanoseconds((stopMSMbaseline-startMSMbaseline) div iters))
  result.perfMSMopt = float64(inNanoseconds((stopMSMopt-startMSMopt) div iters))
  result.perfMSMpara = float64(inNanoseconds((stopMSMpara-startMSMpara) div iters))


proc reportMSMParallel*(perf: MsmParallelBenchResult, numInputs: int) =
  ## Print speedup ratios for MSM benchmarks
  if numInputs <= 100000:
    let speedupBaseline = perf.perfNaive / perf.perfMSMbaseline
    echo &"Speedup ratio baseline  over naive     linear combination: {speedupBaseline:>6.3f}x"

    let speedupOpt = perf.perfNaive / perf.perfMSMopt
    echo &"Speedup ratio optimized over naive     linear combination: {speedupOpt:>6.3f}x"

    let speedupOptBaseline = perf.perfMSMbaseline / perf.perfMSMopt
    echo &"Speedup ratio optimized over baseline  linear combination: {speedupOptBaseline:>6.3f}x"

  let speedupParaOpt = perf.perfMSMopt / perf.perfMSMpara
  echo &"Speedup ratio parallel  over optimized linear combination: {speedupParaOpt:>6.3f}x"


# Precomputed MSM inline benchmark (for small sizes)
# ---------------------------------------------------

type PrecompBenchResult* = object
  nsOp*, throughput*, cycles*: float64

proc benchPrecompMSMInline*[EC; N, t, b: static int](
        ctx: BenchMsmContext[EC], iters: int): PrecompBenchResult {.noinline.} =


  let benchCtx = new(PrecompBenchContext[EC, N], seed = 42'u64, t = t, b = b)

  # Manual timing
  var resultEC: EC
  resultEC.setNeutral()
  let start = getMonotime()
  when SupportsGetTicks:
    let startClk = getTicks()
  for _ in 0 ..< iters:
    discard benchCtx.precomp.msm_vartime(resultEC, benchCtx.scalars)
  let stop = getMonotime()
  when SupportsGetTicks:
    let stopClk = getTicks()

  let ns = inNanoseconds((stop - start) div iters)
  # Print Precomp MSM line (no EC label column)
  let throughput = 1e9 / float64(ns)
  let label = "Precomp MSM"
  let config = fmt"(t={t}, b={b})"
  let setupInfo = fmt"[setup: {benchCtx.precompTimeMs:5.2f}ms, {benchCtx.precompMemMiB:6.2f} MiB]"

  when SupportsGetTicks:
    let cyc = (stopClk - startClk) div iters
    echo fmt"{label:<36}   {config:<30}{setupInfo}        {throughput:>16.3f} ops/s {ns:>16} ns/op{cyc:>14} CPU cycles (approx)"
    result.cycles = float64(cyc)
  else:
    echo fmt"{label:<36}   {config:<30}{setupInfo}        {throughput:>16.3f} ops/s {ns:>16} ns/op"

  result.nsOp = float64(ns)
  result.throughput = throughput

proc reportPrecompSpeedup*(precompNsOp: float64, perfMSMOpt: float64) =
  ## Print speedup ratio of precomp over optimized MSM
  if perfMSMOpt > 0 and precompNsOp > 0:
    let speedupPrecompOpt = perfMSMOpt / precompNsOp
    echo fmt"Speedup ratio precomp   over optimized linear combination: {speedupPrecompOpt:>6.3f}x"
