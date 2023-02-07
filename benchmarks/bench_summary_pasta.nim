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
  ../constantine/math/extension_fields,
  # Helpers
  ./bench_summary_template

# ############################################################
#
#            Benchmark of Pallas and Vesta curves
#
# ############################################################


const Iters = 5000
const AvailableCurves = [
  Pallas, Vesta
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
    addBench(ECP_ShortW_Prj[Fp[curve], G1], Iters)
    mixedAddBench(ECP_ShortW_Prj[Fp[curve], G1], Iters)
    doublingBench(ECP_ShortW_Prj[Fp[curve], G1], Iters)
    separator()
    addBench(ECP_ShortW_Jac[Fp[curve], G1], Iters)
    mixedAddBench(ECP_ShortW_Jac[Fp[curve], G1], Iters)
    doublingBench(ECP_ShortW_Jac[Fp[curve], G1], Iters)
    separator()
    scalarMulBench(ECP_ShortW_Prj[Fp[curve], G1], Iters)
    scalarMulBench(ECP_ShortW_Jac[Fp[curve], G1], Iters)
    separator()

main()
notes()
