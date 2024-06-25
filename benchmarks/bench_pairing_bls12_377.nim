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
  constantine/math/extension_fields,
  # Helpers
  ./bench_pairing_template

# ############################################################
#
#               Benchmark of pairings
#                   for BLS12-381
#
# ############################################################


const Iters = 1000
const AvailableCurves = [
  BLS12_377,
]

proc main() =
  separator()
  staticFor i, 0, AvailableCurves.len:
    const curve = AvailableCurves[i]
    lineDoubleBench(curve, Iters)
    lineAddBench(curve, Iters)
    mulFp12byLine_Bench(curve, Iters)
    mulLinebyLine_Bench(curve, Iters)
    mulFp12by_prod2lines_Bench(curve, Iters)
    mulFp12_by_2lines_v1_Bench(curve, Iters)
    mulFp12_by_2lines_v2_Bench(curve, Iters)
    separator()
    mulBench(curve, Iters)
    sqrBench(curve, Iters)
    separator()
    cyclotomicSquare_Bench(curve, Iters)
    cyclotomicSquareCompressed_Bench(curve, Iters)
    cyclotomicDecompression_Bench(curve, Iters)
    expCurveParamBench(curve, Iters)
    separator()
    finalExpEasyBench(curve, Iters)
    finalExpHardBLS12Bench(curve, Iters)
    separator()
    millerLoopBLS12Bench(curve, Iters)
    finalExpBLS12Bench(curve, Iters)
    separator()
    pairingBLS12Bench(curve, Iters)
    pairing_multipairing_BLS12Bench(curve, 1, Iters)
    separator()
    staticFor j, 2, 4:
      pairing_multisingle_BLS12Bench(curve, j, Iters div j)
      pairing_multipairing_BLS12Bench(curve, j, Iters div j)
    separator()
    staticFor j, 4, 9:
      pairing_multipairing_BLS12Bench(curve, j, Iters div j)

main()
notes()
