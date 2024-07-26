# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import ./bench_summary_template

# ############################################################
#
#               Benchmark of pairings
#                   for BLS12-381
#
# ############################################################


const Iters = 5000
const AvailableCurves = [
  BLS12_377,
]


proc main() =
  separator()
  staticFor i, 0, AvailableCurves.len:
    const curve = AvailableCurves[i]

    mulBench(Fr[curve], Iters)
    sqrBench(Fr[curve], Iters)
    separator()
    mulBench(Fp[curve], Iters)
    sqrBench(Fp[curve], Iters)
    invBench(Fp[curve], Iters)
    sqrtBench(Fp[curve], Iters)
    separator()
    mulBench(Fp2[curve], Iters)
    sqrBench(Fp2[curve], Iters)
    invBench(Fp2[curve], Iters)
    sqrtBench(Fp2[curve], Iters)
    separator()
    mulBench(Fp12[curve], Iters)
    sqrBench(Fp12[curve], Iters)
    invBench(Fp12[curve], Iters)
    separator()
    addBench(EC_ShortW_Prj[Fp[curve], G1], Iters)
    mixedAddBench(EC_ShortW_Prj[Fp[curve], G1], Iters)
    doublingBench(EC_ShortW_Prj[Fp[curve], G1], Iters)
    separator()
    addBench(EC_ShortW_Jac[Fp[curve], G1], Iters)
    mixedAddBench(EC_ShortW_Jac[Fp[curve], G1], Iters)
    doublingBench(EC_ShortW_Jac[Fp[curve], G1], Iters)
    separator()
    addBench(EC_ShortW_Prj[Fp2[curve], G2], Iters)
    mixedAddBench(EC_ShortW_Prj[Fp2[curve], G2], Iters)
    doublingBench(EC_ShortW_Prj[Fp2[curve], G2], Iters)
    separator()
    addBench(EC_ShortW_Jac[Fp2[curve], G2], Iters)
    mixedAddBench(EC_ShortW_Jac[Fp2[curve], G2], Iters)
    doublingBench(EC_ShortW_Jac[Fp2[curve], G2], Iters)
    separator()
    scalarMulBench(EC_ShortW_Prj[Fp[curve], G1], Iters)
    scalarMulBench(EC_ShortW_Jac[Fp[curve], G1], Iters)
    separator()
    scalarMulBench(EC_ShortW_Prj[Fp2[curve], G2], Iters)
    scalarMulBench(EC_ShortW_Jac[Fp2[curve], G2], Iters)
    separator()
    millerLoopBLS12Bench(curve, Iters)
    finalExpBLS12Bench(curve, Iters)
    pairingBLS12Bench(curve, Iters)
    separator()
    subgroupCheckBench(EC_ShortW_Jac[Fp[curve], G1], Iters)
    subgroupCheckBench(EC_ShortW_Jac[Fp2[curve], G2], Iters)
    separator()

main()
notes()
