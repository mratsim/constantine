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
#                 for BN254-Snarks
#
# ############################################################


const Iters = 50
const AvailableCurves = [
  BN254_Snarks,
]

proc main() =
  separator()
  staticFor i, 0, AvailableCurves.len:
    const curve = AvailableCurves[i]
    lineDoubleBench(curve, Iters)
    lineAddBench(curve, Iters)
    mulFp12byLine_xyz000_Bench(curve, Iters)
    separator()
    finalExpEasyBench(curve, Iters)
    finalExpHardBNBench(curve, Iters)
    separator()
    millerLoopBNBench(curve, Iters)
    finalExpBNBench(curve, Iters)
    separator()
    pairingBNBench(curve, Iters)
    separator()

main()
notes()
