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
  ../constantine/math/elliptic/ec_shortweierstrass_jacobian,
  # Helpers
  ./bench_elliptic_template

# ############################################################
#
#                   EIP-2537 benchmarks for
#                 subgroup checks discussion
#
# ############################################################


const Iters = 10_000
const MulIters = 100
const AvailableCurves = [
  BLS12_381,
]

proc main() =
  separator()
  staticFor i, 0, AvailableCurves.len:
    const curve = AvailableCurves[i]
    const bits = curve.getCurveOrderBitwidth()

    # G1
    separator()
    scalarMulVartimeDoubleAddBench(ECP_ShortW_Jac[Fp[curve], G1], bits, MulIters)
    separator()
    scalarMulVartimeWNAFBench(ECP_ShortW_Jac[Fp[curve], G1], bits, window = 3, MulIters)
    scalarMulVartimeWNAFBench(ECP_ShortW_Jac[Fp[curve], G1], bits, window = 4, MulIters)
    scalarMulVartimeWNAFBench(ECP_ShortW_Jac[Fp[curve], G1], bits, window = 5, MulIters)
    separator()
    scalarMulVartimeEndoWNAFBench(ECP_ShortW_Jac[Fp[curve], G1], bits, window = 3, MulIters)
    scalarMulVartimeEndoWNAFBench(ECP_ShortW_Jac[Fp[curve], G1], bits, window = 4, MulIters)
    scalarMulVartimeEndoWNAFBench(ECP_ShortW_Jac[Fp[curve], G1], bits, window = 5, MulIters)
    separator()
    scalarMulEndo(      ECP_ShortW_Jac[Fp[curve], G1], bits, MulIters)
    scalarMulEndoWindow(ECP_ShortW_Jac[Fp[curve], G1], bits, MulIters)
    separator()
    subgroupCheckBench(ECP_ShortW_Jac[Fp[curve], G1], MulIters)
    subgroupCheckScalarMulVartimeEndoWNAFBench(ECP_ShortW_Jac[Fp[curve], G1], bits, window = 3, MulIters)
    subgroupCheckScalarMulVartimeEndoWNAFBench(ECP_ShortW_Jac[Fp[curve], G1], bits, window = 4, MulIters)
    subgroupCheckScalarMulVartimeEndoWNAFBench(ECP_ShortW_Jac[Fp[curve], G1], bits, window = 5, MulIters)
    separator()

    # G2
    separator()
    scalarMulVartimeDoubleAddBench(ECP_ShortW_Jac[Fp2[curve], G2], bits, MulIters)
    separator()
    scalarMulVartimeWNAFBench(ECP_ShortW_Jac[Fp2[curve], G2], bits, window = 3, MulIters)
    scalarMulVartimeWNAFBench(ECP_ShortW_Jac[Fp2[curve], G2], bits, window = 4, MulIters)
    separator()
    scalarMulVartimeEndoWNAFBench(ECP_ShortW_Jac[Fp2[curve], G2], bits, window = 3, MulIters)
    scalarMulVartimeEndoWNAFBench(ECP_ShortW_Jac[Fp2[curve], G2], bits, window = 4, MulIters)
    separator()
    scalarMulEndo(ECP_ShortW_Jac[Fp2[curve], G2], bits, MulIters)
    separator()
    subgroupCheckBench(ECP_ShortW_Jac[Fp2[curve], G2], MulIters)
    subgroupCheckScalarMulVartimeEndoWNAFBench(ECP_ShortW_Jac[Fp2[curve], G2], bits, window = 3, MulIters)
    subgroupCheckScalarMulVartimeEndoWNAFBench(ECP_ShortW_Jac[Fp2[curve], G2], bits, window = 4, MulIters)
    separator()

main()
notes()
