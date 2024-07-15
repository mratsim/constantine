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
  constantine/math/ec_shortweierstrass,
  # Helpers
  helpers/prng_unsafe,
  ./bench_elliptic_parallel_template

# ############################################################
#
#               Benchmark of the G1 group of
#            Short Weierstrass elliptic curves
#          in (homogeneous) projective coordinates
#
# ############################################################


const Iters = 10_000
const AvailableCurves = [
  Pallas, Vesta
]

# const testNumPoints = [10, 100, 1000, 10000, 100000]
# const testNumPoints = [64, 128, 256, 512, 1024, 2048, 4096, 8192, 16384, 32768, 65536, 131072]
const testNumPoints = [1 shl 10, 1 shl 11, 1 shl 12, 1 shl 13, 1 shl 14, 1 shl 15, 1 shl 16, 1 shl 17, 1 shl 18, 1 shl 19, 1 shl 20, 1 shl 21, 1 shl 22]

proc main() =
  separator()
  staticFor i, 0, AvailableCurves.len:
    const curve = AvailableCurves[i]
    var ctx = createBenchMsmContext(EC_ShortW_Jac[Fp[curve], G1], testNumPoints)
    separator()
    for numPoints in testNumPoints:
      let batchIters = max(1, Iters div numPoints)
      ctx.msmParallelBench(numPoints, batchIters)
      separator()
    separator()

main()
notes()
