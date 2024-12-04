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
  constantine/math/extension_fields,
  # Helpers
  ./bench_gt_parallel_template

# ############################################################
#
#               Benchmark of the 𝔾ₜ group of
#                  Pairing Friendly curves
#
# ############################################################

const Iters = 10000
const AvailableCurves = [
  # BN254_Nogami,
  # BN254_Snarks,
  # BLS12_377,
  BLS12_381,
]

# const testNumPoints = [2, 4, 8, 16, 32, 64, 128, 256, 512, 1024]
const testNumPoints = [128, 256]


type Fp12over4[C: static Algebra] = CubicExt[Fp4[C]]
type Fp12over6[C: static Algebra] = QuadraticExt[Fp6[C]]

proc main() =
  separator()
  staticFor i, 0, AvailableCurves.len:
    const curve = AvailableCurves[i]
    var ctx12o4 = createBenchMultiExpContext(Fp12over4[curve], testNumPoints)
    var ctx12o6 = createBenchMultiExpContext(Fp12over6[curve], testNumPoints)
    separator()
    for numPoints in testNumPoints:
      let batchIters = max(1, Iters div numPoints)
      ctx12o4.multiExpParallelBench(numPoints, batchIters)
      echo "----"
      ctx12o6.multiExpParallelBench(numPoints, batchIters)
      separator()
    separator()

main()
notes()
