# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

# ############################################################
#
#             Summary of the performance of a curve
#
# ############################################################

import
  # Standard library
  std/[monotimes, times],
  # Internals
  constantine/platforms/abstractions,
  constantine/named/algebras,
  constantine/math/[arithmetic, extension_fields],
  constantine/math/pairings/[
    pairings_generic,
    gt_exponentiations,
    gt_exponentiations_vartime,
    gt_multiexp, gt_multiexp_parallel,
  ],
  constantine/threadpool,
  # Helpers
  helpers/prng_unsafe,
  ./bench_blueprint

export times, monotimes
export notes
export abstractions
proc separator*() = separator(168)

proc report(op, domain: string, start, stop: MonoTime, startClk, stopClk: int64, iters: int) =
  let ns = inNanoseconds((stop-start) div iters)
  let throughput = 1e9 / float64(ns)
  when SupportsGetTicks:
    echo &"{op:<65} {domain:<20} {throughput:>15.3f} ops/s     {ns:>9} ns/op     {(stopClk - startClk) div iters:>9} CPU cycles (approx)"
  else:
    echo &"{op:<65} {domain:<20} {throughput:>15.3f} ops/s     {ns:>9} ns/op"

macro fixFieldDisplay(T: typedesc): untyped =
  # At compile-time, enums are integers and their display is buggy
  # we get the Curve ID instead of the curve name.
  let instantiated = T.getTypeInst()
  var name = $instantiated[1][0] # Fp
  name.add "[" & $Algebra(instantiated[1][1].intVal) & "]"
  result = newLit name

func fixDisplay(T: typedesc): string =
  when T is (Fp or ExtensionField):
    fixFieldDisplay(T)
  else:
    $T

func fixDisplay(T: Algebra): string =
  $T

template bench(op: string, T: typed, iters: int, body: untyped): untyped =
  measure(iters, startTime, stopTime, startClk, stopClk, body)
  report(op, fixDisplay(T), startTime, stopTime, startClk, stopClk, iters)

func random_gt*(rng: var RngState, F: typedesc): F {.inline, noInit.} =
  result = rng.random_unsafe(F)
  result.finalExp()

# multi-exp
# ---------------------------------------------------------------------------

type BenchMultiexpContext*[GT] = object
  tp: Threadpool
  numInputs: int
  exponents: seq[getBigInt(GT.Name(), kScalarField)]
  elems: seq[GT]

proc createBenchMultiExpContext*(GT: typedesc, inputSizes: openArray[int]): BenchMultiexpContext[GT] =
  result.tp = Threadpool.new()
  let maxNumInputs = inputSizes.max()

  const bits = Fr[GT.Name].bits()

  result.numInputs = maxNumInputs
  result.elems = newSeq[GT](maxNumInputs)
  result.exponents = newSeq[BigInt[bits]](maxNumInputs)

  proc genElemExponentPairsChunk[GT](rngSeed: uint64, start, len: int, elems: ptr GT, exponents: ptr BigInt[bits]) {.nimcall.} =
    let elems = cast[ptr UncheckedArray[GT]](elems)
    let exponents = cast[ptr UncheckedArray[BigInt[bits]]](exponents)

    # RNGs are not threadsafe, create a threadlocal one seeded from the global RNG
    var threadRng: RngState
    threadRng.seed(rngSeed)

    for i in start ..< start + len:
      elems[i] = threadRng.random_gt(GT)
      exponents[i] = threadRng.random_unsafe(BigInt[bits])

  let chunks = balancedChunksPrioNumber(0, maxNumInputs, result.tp.numThreads)

  stdout.write &"Generating {maxNumInputs} (elems, exponents) pairs ... "
  stdout.flushFile()

  let start = getMonotime()

  syncScope:
    for (id, start, size) in items(chunks):
      result.tp.spawn genElemExponentPairsChunk(rng.next(), start, size, result.elems[0].addr, result.exponents[0].addr)

  # Even if child threads are sleeping, it seems like perf is lower when there are threads around
  # maybe because the kernel has more overhead or time quantum to keep track off so shut them down.
  result.tp.shutdown()

  let stop = getMonotime()
  stdout.write &"in {float64(inNanoSeconds(stop-start)) / 1e6:6.3f} ms\n"

proc multiExpParallelBench*[GT](ctx: var BenchMultiExpContext[GT], numInputs: int, iters: int) =
  const bits = Fr[GT.Name].bits()

  template elems: untyped = ctx.elems.toOpenArray(0, numInputs-1)
  template exponents: untyped = ctx.exponents.toOpenArray(0, numInputs-1)


  var r{.noInit.}: GT
  var startNaive, stopNaive, startMultiExpBaseline, stopMultiExpBaseline: MonoTime
  var startMultiExpOpt, stopMultiExpOpt: MonoTime
  var startMultiExpPara, stopMultiExpPara: MonoTime
  var startMultiExpParaTorus, stopMultiExpParaTorus: MonoTime

  when GT is QuadraticExt:
    var startMultiExpBaselineTorus: MonoTime
    var stopMultiExpBaselineTorus: MonoTime
    var startMultiExpOptTorus: MonoTime
    var stopMultiExpOptTorus: Monotime

  if numInputs <= 100000:
    # startNaive = getMonotime()
    bench("𝔾ₜ exponentiations           " & align($numInputs, 10) & " (" & $bits & "-bit exponents)", GT, iters):
      var tmp: GT
      r.setOne()
      for i in 0 ..< elems.len:
        tmp.gtExp(elems[i], exponents[i])
        r *= tmp
    # stopNaive = getMonotime()

  if numInputs <= 100000:
    startNaive = getMonotime()
    bench("𝔾ₜ exponentiations vartime   " & align($numInputs, 10) & " (" & $bits & "-bit exponents)", GT, iters):
      var tmp: GT
      r.setOne()
      for i in 0 ..< elems.len:
        tmp.gtExp_vartime(elems[i], exponents[i])
        r *= tmp
    stopNaive = getMonotime()

  if numInputs <= 100000:
    startMultiExpBaseline = getMonotime()
    bench("𝔾ₜ multi-exp baseline        " & align($numInputs, 10) & " (" & $bits & "-bit exponents)", GT, iters):
      r.multiExp_reference_vartime(elems, exponents, useTorus = false)
    stopMultiExpBaseline = getMonotime()

  if numInputs <= 100000:
    when GT is QuadraticExt:
      startMultiExpBaselineTorus = getMonotime()
      bench("𝔾ₜ multi-exp baseline + torus" & align($numInputs, 10) & " (" & $bits & "-bit exponents)", GT, iters):
        r.multiExp_reference_vartime(elems, exponents, useTorus = true)
      stopMultiExpBaselineTorus = getMonotime()

  block:
    startMultiExpOpt = getMonotime()
    bench("𝔾ₜ multi-exp opt             " & align($numInputs, 10) & " (" & $bits & "-bit exponents)", GT, iters):
      r.multiExp_vartime(elems, exponents, useTorus = false)
    stopMultiExpOpt = getMonotime()

  when GT is QuadraticExt:
    block:
      startMultiExpOptTorus = getMonotime()
      bench("𝔾ₜ multi-exp opt + torus     " & align($numInputs, 10) & " (" & $bits & "-bit exponents)", GT, iters):
        r.multiExp_vartime(elems, exponents, useTorus = true)
      stopMultiExpOptTorus = getMonotime()

  block:
    ctx.tp = Threadpool.new()

    startMultiExpPara = getMonotime()
    bench("𝔾ₜ multi-exp      " & align($ctx.tp.numThreads & " threads", 11) & align($numInputs, 10) & " (" & $bits & "-bit exponents)", GT, iters):
      ctx.tp.multiExp_vartime_parallel(r, elems, exponents, useTorus = false)
    stopMultiExpPara = getMonotime()

    ctx.tp.shutdown()

  when GT is QuadraticExt:
    block:
      ctx.tp = Threadpool.new()

      startMultiExpParaTorus = getMonotime()
      bench("𝔾ₜ multi-exp torus" & align($ctx.tp.numThreads & " threads", 11) & align($numInputs, 10) & " (" & $bits & "-bit exponents)", GT, iters):
        ctx.tp.multiExp_vartime_parallel(r, elems, exponents, useTorus = true)
      stopMultiExpParaTorus = getMonotime()

      ctx.tp.shutdown()

  let perfNaive = inNanoseconds((stopNaive-startNaive) div iters)
  let perfMultiExpBaseline = inNanoseconds((stopMultiExpBaseline-startMultiExpBaseline) div iters)
  let perfMultiExpOpt = inNanoseconds((stopMultiExpOpt-startMultiExpOpt) div iters)
  let perfMultiExpPara = inNanoseconds((stopMultiExpPara-startMultiExpPara) div iters)
  when GT is QuadraticExt:
    let perfMultiExpBaselineTorus = inNanoseconds((stopMultiExpBaselineTorus-startMultiExpBaselineTorus) div iters)
    let perfMultiExpOptTorus = inNanoseconds((stopMultiExpOptTorus-startMultiExpOptTorus) div iters)
    let perfMultiExpParaTorus = inNanoSeconds((stopMultiExpParaTorus-startMultiExpParaTorus) div iters)

  if numInputs <= 100000:
    let speedupBaseline = float(perfNaive) / float(perfMultiExpBaseline)
    echo &"Speedup ratio baseline over naive linear combination: {speedupBaseline:>6.3f}x"

    let speedupOpt = float(perfNaive) / float(perfMultiExpOpt)
    echo &"Speedup ratio optimized over naive linear combination: {speedupOpt:>6.3f}x"

    when GT is QuadraticExt:
      let speedupTorusOverBaseline = float(perfMultiExpBaseline) / float(perfMultiExpBaselineTorus)
      echo &"Speedup ratio baseline + Torus over baseline linear combination: {speedupTorusOverBaseline:>6.3f}x"

      let speedupTorusOverOpt = float(perfMultiExpOpt) / float(perfMultiExpOptTorus)
      echo &"Speedup ratio optimized + Torus over optimized: {speedupTorusOverOpt:>6.3f}x"

  let speedupParaOpt = float(perfMultiExpOpt) / float(perfMultiExpPara)
  echo &"Speedup ratio parallel over serial optimized linear combination: {speedupParaOpt:>6.3f}x"

  when GT is QuadraticExt:
    let speedupParaTorus = float(perfMultiExpOptTorus) / float(perfMultiExpParaTorus)
    echo &"Speedup ratio parallel over serial for Torus-based multiexp: {speedupParaTorus:>6.3f}x"

    let speedupParaTorusOpt = float(perfMultiExpPara) / float(perfMultiExpParaTorus)
    echo &"Speedup ratio parallel over parallel Torus-based multiexp: {speedupParaTorusOpt:>6.3f}x"