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
  ./bench_fields_template

# ############################################################
#
#                   Benchmark of 𝔽p12
#
# ############################################################


const Iters = 10_000
const InvIters = 1000
const AvailableCurves = [
  # Pairing-Friendly curves
  BN254_Nogami,
  BN254_Snarks,
  BLS12_377,
  BLS12_381
]

proc main() =
  separator()
  staticFor i, 0, AvailableCurves.len:
    const curve = AvailableCurves[i]
    addBench(Fp12[curve], Iters)
    subBench(Fp12[curve], Iters)
    negBench(Fp12[curve], Iters)
    mulBench(Fp12[curve], Iters)
    sqrBench(Fp12[curve], Iters)
    invBench(Fp12[curve], InvIters)
    invVartimeBench(Fp12[curve], InvIters)
    separator()

main()
notes()
