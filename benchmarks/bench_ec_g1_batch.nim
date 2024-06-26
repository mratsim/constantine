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
    ec_shortweierstrass_projective,
    ec_shortweierstrass_jacobian,
    ec_shortweierstrass_jacobian_extended],
  # Helpers
  ./bench_elliptic_template, ./bench_elliptic_parallel_template


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

# const testNumPoints = [10, 100, 1000, 10000, 100000]
const testNumPoints = [4, 8, 16, 32, 64, 128, 256, 512, 1024, 2048, 4096, 8192, 65536, 131072]

proc main() =
  separator()
  staticFor i, 0, AvailableCurves.len:
    const curve = AvailableCurves[i]
    addBench(EC_ShortW_Prj[Fp[curve], G1], Iters)
    doublingBench(EC_ShortW_Prj[Fp[curve], G1], Iters)
    mixedAddBench(EC_ShortW_Prj[Fp[curve], G1], Iters)
    addBench(EC_ShortW_Jac[Fp[curve], G1], Iters)
    doublingBench(EC_ShortW_Jac[Fp[curve], G1], Iters)
    mixedAddBench(EC_ShortW_Jac[Fp[curve], G1], Iters)
    addBench(EC_ShortW_JacExt[Fp[curve], G1], Iters)
    doublingBench(EC_ShortW_JacExt[Fp[curve], G1], Iters)
    mixedAddBench(EC_ShortW_JacExt[Fp[curve], G1], Iters)
    separator()
    # for numPoints in testNumPoints:
    #   let batchIters = max(1, Iters div numPoints)
    #   multiAddBench(EC_ShortW_Prj[Fp[curve], G1], numPoints, useBatching = false, batchIters)
    # separator()
    # for numPoints in testNumPoints:
    #   let batchIters = max(1, Iters div numPoints)
    #   multiAddBench(EC_ShortW_Prj[Fp[curve], G1], numPoints, useBatching = true, batchIters)
    # separator()
    # for numPoints in testNumPoints:
    #   let batchIters = max(1, Iters div numPoints)
    #   multiAddParallelBench(EC_ShortW_Prj[Fp[curve], G1], numPoints, batchIters)
    # separator()
    for numPoints in testNumPoints:
      let batchIters = max(1, Iters div numPoints)
      multiAddBench(EC_ShortW_Jac[Fp[curve], G1], numPoints, useBatching = false, batchIters)
    separator()
    for numPoints in testNumPoints:
      let batchIters = max(1, Iters div numPoints)
      multiAddBench(EC_ShortW_Jac[Fp[curve], G1], numPoints, useBatching = true, batchIters)
    separator()
    for numPoints in testNumPoints:
      let batchIters = max(1, Iters div numPoints)
      multiAddParallelBench(EC_ShortW_Jac[Fp[curve], G1], numPoints, batchIters)
    # separator()
    # for numPoints in testNumPoints:
    #   let batchIters = max(1, Iters div numPoints)
    #   multiAddBench(EC_ShortW_JacExt[Fp[curve], G1], numPoints, useBatching = false, batchIters)
    # separator()
    # for numPoints in testNumPoints:
    #   let batchIters = max(1, Iters div numPoints)
    #   multiAddBench(EC_ShortW_JacExt[Fp[curve], G1], numPoints, useBatching = true, batchIters)
    separator()
    separator()

main()
notes()
