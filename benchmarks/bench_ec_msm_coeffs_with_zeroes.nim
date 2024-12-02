# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  # Internals
  constantine/threadpool,
  constantine/named/[algebras, zoo_subgroups],
  constantine/math/arithmetic,
  constantine/math/ec_shortweierstrass,
  # Helpers
  helpers/prng_unsafe,
  ./bench_elliptic_parallel_template
#  ./bench_msm_impl_optional_drop_windows

# ############################################################
#
#               Benchmark of the G1 group of
#            Short Weierstrass elliptic curves
#          in (homogeneous) projective coordinates
#
# ############################################################

type
  BenchTimes = tuple[numInputs: int, bits: int, bAll, bWo, oAll, oWo: float]

proc msmBench*[EC](ctx: var BenchMsmContext[EC], numInputs: int, iters: int, bits: int): BenchTimes =
  const bigIntBits = EC.getScalarField().bits()
  type ECaff = affine(EC)

  template coefs: untyped = ctx.coefs.toOpenArray(0, numInputs-1)
  template points: untyped = ctx.points.toOpenArray(0, numInputs-1)

  template benchIt(body: untyped): untyped =
    block:
      var useZeroWindows {.inject.} = true
      let startAll = getMonotime()
      block:
        body
      let stopAll = getMonoTime()
      useZeroWindows = false
      let startWo = getMonoTime()
      block:
        body
      let stopWo = getMonotime()
      (all: float inNanoseconds(stopAll - startAll),
       wo:  float inNanoseconds(stopWo  - startWo))

  var r{.noInit.}: EC
  var startNaive, stopNaive, startbaseline, stopbaseline, startopt, stopopt, startpara, stoppara: MonoTime

  let (bAll, bWo) = benchIt:
    bench(&"EC multi-scalar-mul baseline  {align($numInputs, 10)} ({bigIntBits}-bit coefs, points), nonZeroBits = {bits}, useZeroWindows = {useZeroWindows}", EC, iters):
      r.multiScalarMul_reference_vartime(coefs, points, useZeroWindows)
  let (oAll, oWo) = benchIt:
    bench(&"EC multi-scalar-mul optimized {align($numInputs, 10)} ({bigIntBits}-bit coefs, points), nonZeroBits = {bits}, useZeroWindows = {useZeroWindows}", EC, iters):
      r.multiScalarMul_vartime(coefs, points, useZeroWindows)

  let pbAll = bAll / iters.float
  let pbWo  = bWo / iters.float
  let poAll = oAll / iters.float
  let poWo  = oWo / iters.float

  echo &"total time baseline  (useZeroWindows = true)  = {bAll / 1e9} s"
  echo &"total time baseline  (useZeroWindows = false) = {bWo  / 1e9} s"
  echo &"total time optimized (useZeroWindows = true)  = {oAll / 1e9} s"
  echo &"total time optimized (useZeroWindows = false) = {oWo  / 1e9} s"

  echo &"Speedup ratio baseline with & without all windows:         {pbAll / pbWo:>6.3f}x"
  echo &"Speedup ratio optimized with & without all windows:        {poAll / poWo:>6.3f}x"
  echo &"Speedup ratio optimized over baseline with all windows:    {pbAll / poAll:>6.3f}x"
  echo &"Speedup ratio optimized over baseline without all windows: {pbWo  / poWo:>6.3f}x"

  result = (numInputs: numInputs, bits: bits, bAll: bAll, bWo: bWo, oAll: oAll, oWo: oWo)

const Iters = 10_000
const AvailableCurves = [
  BLS12_381,
]

const testNumPoints = [2, 8, 64, 1024, 4096, 65536, 1048576] #, 4194304, 8388608, 16777216]

template canImport(x: untyped): bool =
  compiles:
    import x

when canImport(ggplotnim):
  import ggplotnim
else:
  {.error: "This benchmarks requires `ggplotnim` to produce a plot of the benchmark results.".}
proc main() =
  separator()
  staticFor i, 0, AvailableCurves.len:
    const curve = AvailableCurves[i]
    const maxBits = [1, 32, 128, 512] # [1, 8, 16, 32, 64, 128, 256, 512] # how many bits are set in the coefficients
    var df = newDataFrame()
    for bits in maxBits:
      var ctx = createBenchMsmContext(EC_ShortW_Jac[Fp[curve], G1], testNumPoints, bits)
      separator()
      for numPoints in testNumPoints:
        let batchIters = max(1, Iters div numPoints)
        df.add ctx.msmBench(numPoints, batchIters, bits)
        separator()
      separator()
      echo "\n\n\n"
      separator()
    separator()

    df = df.gather(["bAll", "bWo", "oAll", "oWo"], "Bench", "Time")
      .mutate(f{"Time" ~ `Time` * 1e-9})
    df.writeCsv("/tmp/data.csv")
    ggplot(df, aes("numInputs", "Time", shape = "Bench", color = "bits")) +
      geom_point() +
      scale_x_continuous() +
      scale_x_log2(breaks = @testNumPoints) + scale_y_log10() +
      xlab("Number of inputs of the MSM") + ylab("Time [s]") +
      ggtitle("bits = number of bits set in coefficients") +
      margin(right = 4) +
      xMargin(0.05) +
      theme_scale(1.2) +
      ggsave("plots/bench_result.pdf")

main()
notes()
