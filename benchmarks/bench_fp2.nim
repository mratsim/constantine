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
#               Benchmark of 𝔽p2 = 𝔽p[𝑖]
#
# ############################################################


const Iters = 1_000_000
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
    addBench(Fp2[curve], Iters)
    subBench(Fp2[curve], Iters)
    negBench(Fp2[curve], Iters)
    ccopyBench(Fp2[curve], Iters)
    div2Bench(Fp2[curve], Iters)
    smallSeparator()
    mulBench(Fp2[curve], Iters)
    sqrBench(Fp2[curve], Iters)
    smallSeparator()
    mul2xUnrBench(Fp2[curve], Iters)
    sqr2xUnrBench(Fp2[curve], Iters)
    rdc2xBench(Fp2[curve], Iters)
    smallSeparator()
    invBench(Fp2[curve], InvIters)
    invVartimeBench(Fp2[curve], InvIters)
    isSquareBench(Fp2[curve], InvIters)
    sqrtBench(Fp2[curve], InvIters)
    separator()

main()
notes()
