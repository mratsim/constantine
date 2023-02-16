# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  # Internals
  ../constantine/math/config/curves,
  ../constantine/math/arithmetic,
  ../constantine/math/elliptic/[
    ec_shortweierstrass_affine,
    ec_shortweierstrass_projective,
    ec_shortweierstrass_jacobian,
    ec_scalar_mul,
    ec_multi_scalar_mul],
  ../constantine/math/constants/zoo_subgroups,
  # Helpers
  ../helpers/prng_unsafe,
  ./bench_elliptic_template,
  ./bench_blueprint

# ############################################################
#
#             Parallel Benchmark definitions
#
# ############################################################

proc evaluateBucketSizeBench*(iters: int) =
  bench("bestBucketBitSize", ECP_ShortW_Aff[Fp[BLS12_381], G1], iters):
    discard bestBucketBitSize(inputSize = 1000000, scalarBitwidth = 255, useSignedBuckets = true, useManualTuning = true)

proc msmBench*(EC: typedesc, numPoints: int, iters: int) =
  const bits = EC.F.C.getCurveOrderBitwidth()
  var points = newSeq[ECP_ShortW_Aff[EC.F, EC.G]](numPoints)
  var scalars = newSeq[BigInt[bits]](numPoints)

  for i in 0 ..< numPoints:
    var tmp = rng.random_unsafe(EC)
    tmp.clearCofactor()
    points[i].affine(tmp)
    scalars[i] = rng.random_unsafe(BigInt[bits])

  var r{.noInit.}: EC
  var startNaive, stopNaive, startMSMbaseline, stopMSMbaseline, startMSMopt, stopMSMopt: MonoTime

  if numPoints <= 100000:
    bench("EC scalar muls                " & align($numPoints, 7) & " (scalars " & $bits & "-bit, points) pairs ", EC, iters):
      startNaive = getMonotime()
      var tmp: EC
      r.setInf()
      for i in 0 ..< points.len:
        tmp.fromAffine(points[i])
        tmp.scalarMul(scalars[i])
        r += tmp
      stopNaive = getMonotime()

  block:
    bench("EC multi-scalar-mul baseline  " & align($numPoints, 7) & " (scalars " & $bits & "-bit, points) pairs ", EC, iters):
      startMSMbaseline = getMonotime()
      r.multiScalarMul_reference_vartime(scalars, points)
      stopMSMbaseline = getMonotime()

  block:
    bench("EC multi-scalar-mul optimized " & align($numPoints, 7) & " (scalars " & $bits & "-bit, points) pairs ", EC, iters):
      startMSMopt = getMonotime()
      r.multiScalarMul_vartime(scalars, points)
      stopMSMopt = getMonotime()

  let perfNaive = inNanoseconds((stopNaive-startNaive) div iters)
  let perfMSMbaseline = inNanoseconds((stopMSMbaseline-startMSMbaseline) div iters)
  let perfMSMopt = inNanoseconds((stopMSMopt-startMSMopt) div iters)

  if numPoints <= 100000:
    let speedupBaseline = float(perfNaive) / float(perfMSMbaseline)
    echo &"Speedup ratio baseline over naive linear combination: {speedupBaseline:>6.3f}x"

    let speedupOpt = float(perfNaive) / float(perfMSMopt)
    echo &"Speedup ratio optimized over naive linear combination: {speedupOpt:>6.3f}x"

  let speedupOptBaseline = float(perfMSMbaseline) / float(perfMSMopt)
  echo &"Speedup ratio optimized over baseline linear combination: {speedupOptBaseline:>6.3f}x"

# ############################################################
#
#               Benchmark of the G1 group of
#            Short Weierstrass elliptic curves
#          in (homogeneous) projective coordinates
#
# ############################################################


const Iters = 10_000
const AvailableCurves = [
  BLS12_381,
]

# const testNumPoints = [10, 100, 1000, 10000, 100000]
const testNumPoints = [8, 16, 32, 64, 128, 256, 512, 1024, 2048, 4096, 8192,
                       16384, 32768, 65536, 131072, 262144]

proc main() =
  separator()
  evaluateBucketSizeBench(Iters)

  staticFor i, 0, AvailableCurves.len:
    const curve = AvailableCurves[i]
    separator()
    # for numPoints in testNumPoints:
    #   let batchIters = max(1, Iters div numPoints)
    #   msmBench(ECP_ShortW_Prj[Fp[curve], G1], numPoints, batchIters)
    #   separator()
    # separator()
    for numPoints in testNumPoints:
      let batchIters = max(1, Iters div numPoints)
      msmBench(ECP_ShortW_Jac[Fp[curve], G1], numPoints, batchIters)
      separator()
    separator()

main()
notes()
