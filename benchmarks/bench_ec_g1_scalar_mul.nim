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
  ../constantine/math/elliptic/[
    ec_shortweierstrass_projective,
    ec_shortweierstrass_jacobian],
  # Helpers
  ./bench_elliptic_template

# ############################################################
#
#               Benchmark of the G1 group of
#            Short Weierstrass elliptic curves
#          in (homogeneous) projective coordinates
#
# ############################################################


const Iters = 10_000
const MulIters = 100
const AvailableCurves = [
  # P224,
  BN254_Nogami,
  BN254_Snarks,
  # Edwards25519,
  # P256,
  # Secp256k1,
  Pallas,
  Vesta,
  BLS12_377,
  BLS12_381,
]

proc main() =
  separator()
  staticFor i, 0, AvailableCurves.len:
    const curve = AvailableCurves[i]
    const bits = curve.getCurveOrderBitwidth()
    scalarMulVartimeDoubleAddBench(ECP_ShortW_Prj[Fp[curve], G1], bits, MulIters)
    scalarMulVartimeDoubleAddBench(ECP_ShortW_Jac[Fp[curve], G1], bits, MulIters)
    separator()
    scalarMulVartimeMinHammingWeightRecodingBench(ECP_ShortW_Prj[Fp[curve], G1], bits, MulIters)
    scalarMulVartimeMinHammingWeightRecodingBench(ECP_ShortW_Jac[Fp[curve], G1], bits, MulIters)
    separator()
    scalarMulGenericBench(ECP_ShortW_Prj[Fp[curve], G1], bits, window = 2, MulIters)
    scalarMulGenericBench(ECP_ShortW_Prj[Fp[curve], G1], bits, window = 3, MulIters)
    scalarMulGenericBench(ECP_ShortW_Prj[Fp[curve], G1], bits, window = 4, MulIters)
    scalarMulGenericBench(ECP_ShortW_Prj[Fp[curve], G1], bits, window = 5, MulIters)
    scalarMulGenericBench(ECP_ShortW_Jac[Fp[curve], G1], bits, window = 2, MulIters)
    scalarMulGenericBench(ECP_ShortW_Jac[Fp[curve], G1], bits, window = 3, MulIters)
    scalarMulGenericBench(ECP_ShortW_Jac[Fp[curve], G1], bits, window = 4, MulIters)
    scalarMulGenericBench(ECP_ShortW_Jac[Fp[curve], G1], bits, window = 5, MulIters)
    separator()
    scalarMulVartimeWNAFBench(ECP_ShortW_Prj[Fp[curve], G1], bits, window = 2, MulIters)
    scalarMulVartimeWNAFBench(ECP_ShortW_Prj[Fp[curve], G1], bits, window = 3, MulIters)
    scalarMulVartimeWNAFBench(ECP_ShortW_Prj[Fp[curve], G1], bits, window = 4, MulIters)
    scalarMulVartimeWNAFBench(ECP_ShortW_Prj[Fp[curve], G1], bits, window = 5, MulIters)
    scalarMulVartimeWNAFBench(ECP_ShortW_Jac[Fp[curve], G1], bits, window = 2, MulIters)
    scalarMulVartimeWNAFBench(ECP_ShortW_Jac[Fp[curve], G1], bits, window = 3, MulIters)
    scalarMulVartimeWNAFBench(ECP_ShortW_Jac[Fp[curve], G1], bits, window = 4, MulIters)
    scalarMulVartimeWNAFBench(ECP_ShortW_Jac[Fp[curve], G1], bits, window = 5, MulIters)
    separator()
    when bits >= 196: # All endomorphisms constants are below this threshold
      scalarMulVartimeEndoWNAFBench(ECP_ShortW_Prj[Fp[curve], G1], bits, window = 2, MulIters)
      scalarMulVartimeEndoWNAFBench(ECP_ShortW_Prj[Fp[curve], G1], bits, window = 3, MulIters)
      scalarMulVartimeEndoWNAFBench(ECP_ShortW_Prj[Fp[curve], G1], bits, window = 4, MulIters)
      scalarMulVartimeEndoWNAFBench(ECP_ShortW_Prj[Fp[curve], G1], bits, window = 5, MulIters)
      scalarMulVartimeEndoWNAFBench(ECP_ShortW_Jac[Fp[curve], G1], bits, window = 2, MulIters)
      scalarMulVartimeEndoWNAFBench(ECP_ShortW_Jac[Fp[curve], G1], bits, window = 3, MulIters)
      scalarMulVartimeEndoWNAFBench(ECP_ShortW_Jac[Fp[curve], G1], bits, window = 4, MulIters)
      scalarMulVartimeEndoWNAFBench(ECP_ShortW_Jac[Fp[curve], G1], bits, window = 5, MulIters)
      separator()
      scalarMulEndo(      ECP_ShortW_Prj[Fp[curve], G1], bits, MulIters)
      scalarMulEndoWindow(ECP_ShortW_Prj[Fp[curve], G1], bits, MulIters)
      scalarMulEndo(      ECP_ShortW_Jac[Fp[curve], G1], bits, MulIters)
      scalarMulEndoWindow(ECP_ShortW_Jac[Fp[curve], G1], bits, MulIters)
      separator()
    separator()

main()
notes()
