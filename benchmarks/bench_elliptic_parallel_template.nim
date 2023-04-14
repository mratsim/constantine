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
    ec_shortweierstrass_jacobian_extended,
    ec_shortweierstrass_batch_ops_parallel,
    ec_multi_scalar_mul,
    ec_scalar_mul,
    ec_multi_scalar_mul_parallel],
  ../constantine/math/constants/zoo_subgroups,
  # Threadpool
  ../constantine/platforms/threadpool/threadpool,
  # Helpers
  ../helpers/prng_unsafe,
  ./bench_elliptic_template,
  ./bench_blueprint

export bench_elliptic_template

# ############################################################
#
#             Parallel Benchmark definitions
#
# ############################################################

proc multiAddParallelBench*(EC: typedesc, numPoints: int, iters: int) =
  var points = newSeq[ECP_ShortW_Aff[EC.F, EC.G]](numPoints)

  for i in 0 ..< numPoints:
    points[i] = rng.random_unsafe(ECP_ShortW_Aff[EC.F, EC.G])

  var r{.noInit.}: EC

  var tp = Threadpool.new()

  bench("EC parallel batch add  (" & align($tp.numThreads, 2) & " threads)   " & $EC.G & " (" & $numPoints & " points)", EC, iters):
    tp.sum_reduce_vartime_parallel(r, points)

  tp.shutdown()

proc msmParallelBench*(EC: typedesc, numPoints: int, iters: int) =
  const bits = EC.F.C.getCurveOrderBitwidth()
  var points = newSeq[ECP_ShortW_Aff[EC.F, EC.G]](numPoints)
  var scalars = newSeq[BigInt[bits]](numPoints)

  for i in 0 ..< numPoints:
    var tmp = rng.random_unsafe(EC)
    tmp.clearCofactor()
    points[i].affine(tmp)
    scalars[i] = rng.random_unsafe(BigInt[bits])

  var r{.noInit.}: EC
  var startNaive, stopNaive, startMSMbaseline, stopMSMbaseline, startMSMopt, stopMSMopt, startMSMpara, stopMSMpara: MonoTime

  if numPoints <= 100000:
    startNaive = getMonotime()
    bench("EC scalar muls                " & align($numPoints, 10) & " (" & $bits & "-bit coefs, points)", EC, iters):
      var tmp: EC
      r.setInf()
      for i in 0 ..< points.len:
        tmp.fromAffine(points[i])
        tmp.scalarMul(scalars[i])
        r += tmp
    stopNaive = getMonotime()

  if numPoints <= 100000:
    startMSMbaseline = getMonotime()
    bench("EC multi-scalar-mul baseline  " & align($numPoints, 10) & " (" & $bits & "-bit coefs, points)", EC, iters):
      r.multiScalarMul_reference_vartime(scalars, points)
    stopMSMbaseline = getMonotime()

  block:
    startMSMopt = getMonotime()
    bench("EC multi-scalar-mul optimized " & align($numPoints, 10) & " (" & $bits & "-bit coefs, points)", EC, iters):
      r.multiScalarMul_vartime(scalars, points)
    stopMSMopt = getMonotime()

  block:
    var tp = Threadpool.new()

    startMSMpara = getMonotime()
    bench("EC multi-scalar-mul" & align($tp.numThreads & " threads", 11) & align($numPoints, 10) & " (" & $bits & "-bit coefs, points)", EC, iters):
      tp.multiScalarMul_vartime_parallel(r, scalars, points)
    stopMSMpara = getMonotime()

    tp.shutdown()

  let perfNaive = inNanoseconds((stopNaive-startNaive) div iters)
  let perfMSMbaseline = inNanoseconds((stopMSMbaseline-startMSMbaseline) div iters)
  let perfMSMopt = inNanoseconds((stopMSMopt-startMSMopt) div iters)
  let perfMSMpara = inNanoseconds((stopMSMpara-startMSMpara) div iters)

  if numPoints <= 100000:
    let speedupBaseline = float(perfNaive) / float(perfMSMbaseline)
    echo &"Speedup ratio baseline over naive linear combination: {speedupBaseline:>6.3f}x"

    let speedupOpt = float(perfNaive) / float(perfMSMopt)
    echo &"Speedup ratio optimized over naive linear combination: {speedupOpt:>6.3f}x"

    let speedupOptBaseline = float(perfMSMbaseline) / float(perfMSMopt)
    echo &"Speedup ratio optimized over baseline linear combination: {speedupOptBaseline:>6.3f}x"

  let speedupParaOpt = float(perfMSMopt) / float(perfMSMpara)
  echo &"Speedup ratio parallel over optimized linear combination: {speedupParaOpt:>6.3f}x"
