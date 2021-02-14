# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  # Internals
  ../constantine/config/curves,
  ../constantine/arithmetic,
  ../constantine/towers,
  # Helpers
  ../helpers/static_for,
  ./bench_pairing_template,
  # Standard library
  std/strutils

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
    mulFp12byLine_xyz000_Bench(curve, Iters)
    mulLinebyLine_xyz000_Bench(curve, Iters)
    mulFp12by_abcdefghij00_Bench(curve, Iters)
    mulFp12_by_2lines_v1_xyz000_Bench(curve, Iters)
    mulFp12_by_2lines_v2_xyz000_Bench(curve, Iters)
    separator()
    finalExpEasyBench(curve, Iters)
    finalExpHardBLS12Bench(curve, Iters)
    separator()
    millerLoopBLS12Bench(curve, Iters)
    finalExpBLS12Bench(curve, Iters)
    separator()
    pairingBLS12Bench(curve, Iters)
    separator()

main()
notes()
