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
    ec_shortweierstrass_batch_ops_parallel],
  ../constantine/platforms/threadpool/threadpool,
  # Helpers
  ../helpers/[static_for, prng_unsafe],
  ./bench_elliptic_template,
  ./bench_blueprint

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
    tp.sum_batch_vartime_parallel(r, points)

  tp.shutdown()

# ############################################################
#
#               Benchmark of the G1 group of
#            Short Weierstrass elliptic curves
#          in (homogeneous) projective coordinates
#
# ############################################################


const Iters = 10_000
const AvailableCurves = [
  # BN254_Snarks,
  BLS12_381,
]

proc main() =
  separator()
  staticFor i, 0, AvailableCurves.len:
    const curve = AvailableCurves[i]
    addBench(ECP_ShortW_Prj[Fp[curve], G1], Iters)
    addBench(ECP_ShortW_Jac[Fp[curve], G1], Iters)
    mixedAddBench(ECP_ShortW_Prj[Fp[curve], G1], Iters)
    mixedAddBench(ECP_ShortW_Jac[Fp[curve], G1], Iters)
    doublingBench(ECP_ShortW_Prj[Fp[curve], G1], Iters)
    doublingBench(ECP_ShortW_Jac[Fp[curve], G1], Iters)
    separator()
    for numPoints in [10, 100, 1000, 10000, 100000, 1000000]:
      let batchIters = max(1, Iters div numPoints)
      multiAddBench(ECP_ShortW_Prj[Fp[curve], G1], numPoints, useBatching = false, batchIters)
    separator()
    for numPoints in [10, 100, 1000, 10000, 100000, 1000000]:
      let batchIters = max(1, Iters div numPoints)
      multiAddBench(ECP_ShortW_Prj[Fp[curve], G1], numPoints, useBatching = true, batchIters)
    separator()
    for numPoints in [10, 100, 1000, 10000, 100000, 1000000]:
      let batchIters = max(1, Iters div numPoints)
      multiAddParallelBench(ECP_ShortW_Prj[Fp[curve], G1], numPoints, batchIters)
    separator()
    for numPoints in [10, 100, 1000, 10000, 100000, 1000000]:
      let batchIters = max(1, Iters div numPoints)
      multiAddBench(ECP_ShortW_Jac[Fp[curve], G1], numPoints, useBatching = false, batchIters)
    separator()
    for numPoints in [10, 100, 1000, 10000, 100000, 1000000]:
      let batchIters = max(1, Iters div numPoints)
      multiAddBench(ECP_ShortW_Jac[Fp[curve], G1], numPoints, useBatching = true, batchIters)
    separator()
    for numPoints in [10, 100, 1000, 10000, 100000, 1000000]:
      let batchIters = max(1, Iters div numPoints)
      multiAddParallelBench(ECP_ShortW_Jac[Fp[curve], G1], numPoints, batchIters)
    separator()
    separator()

main()
notes()
