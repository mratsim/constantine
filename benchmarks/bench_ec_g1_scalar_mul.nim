# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  # Internals
  constantine/named/[algebras, zoo_endomorphisms],
  constantine/math/arithmetic,
  constantine/math/ec_shortweierstrass,
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
  Secp256k1,
  Pallas,
  Vesta,
  BLS12_377,
  BLS12_381,
]

proc main() =
  separator()
  staticFor i, 0, AvailableCurves.len:
    const curve = AvailableCurves[i]
    const bits = Fr[curve].bits()
    scalarMulVartimeDoubleAddBench(EC_ShortW_Prj[Fp[curve], G1], bits, MulIters)
    scalarMulVartimeDoubleAddBench(EC_ShortW_Jac[Fp[curve], G1], bits, MulIters)
    separator()
    scalarMulVartimeMinHammingWeightRecodingBench(EC_ShortW_Prj[Fp[curve], G1], bits, MulIters)
    scalarMulVartimeMinHammingWeightRecodingBench(EC_ShortW_Jac[Fp[curve], G1], bits, MulIters)
    separator()
    scalarMulGenericBench(EC_ShortW_Prj[Fp[curve], G1], bits, window = 2, MulIters)
    scalarMulGenericBench(EC_ShortW_Prj[Fp[curve], G1], bits, window = 3, MulIters)
    scalarMulGenericBench(EC_ShortW_Prj[Fp[curve], G1], bits, window = 4, MulIters)
    scalarMulGenericBench(EC_ShortW_Prj[Fp[curve], G1], bits, window = 5, MulIters)
    scalarMulGenericBench(EC_ShortW_Jac[Fp[curve], G1], bits, window = 2, MulIters)
    scalarMulGenericBench(EC_ShortW_Jac[Fp[curve], G1], bits, window = 3, MulIters)
    scalarMulGenericBench(EC_ShortW_Jac[Fp[curve], G1], bits, window = 4, MulIters)
    scalarMulGenericBench(EC_ShortW_Jac[Fp[curve], G1], bits, window = 5, MulIters)
    separator()
    scalarMulVartimeWNAFBench(EC_ShortW_Prj[Fp[curve], G1], bits, window = 2, MulIters)
    scalarMulVartimeWNAFBench(EC_ShortW_Prj[Fp[curve], G1], bits, window = 3, MulIters)
    scalarMulVartimeWNAFBench(EC_ShortW_Prj[Fp[curve], G1], bits, window = 4, MulIters)
    scalarMulVartimeWNAFBench(EC_ShortW_Prj[Fp[curve], G1], bits, window = 5, MulIters)
    scalarMulVartimeWNAFBench(EC_ShortW_Jac[Fp[curve], G1], bits, window = 2, MulIters)
    scalarMulVartimeWNAFBench(EC_ShortW_Jac[Fp[curve], G1], bits, window = 3, MulIters)
    scalarMulVartimeWNAFBench(EC_ShortW_Jac[Fp[curve], G1], bits, window = 4, MulIters)
    scalarMulVartimeWNAFBench(EC_ShortW_Jac[Fp[curve], G1], bits, window = 5, MulIters)
    separator()
    when curve.hasEndomorphismAcceleration():
      scalarMulVartimeEndoWNAFBench(EC_ShortW_Prj[Fp[curve], G1], bits, window = 2, MulIters)
      scalarMulVartimeEndoWNAFBench(EC_ShortW_Prj[Fp[curve], G1], bits, window = 3, MulIters)
      scalarMulVartimeEndoWNAFBench(EC_ShortW_Prj[Fp[curve], G1], bits, window = 4, MulIters)
      scalarMulVartimeEndoWNAFBench(EC_ShortW_Prj[Fp[curve], G1], bits, window = 5, MulIters)
      scalarMulVartimeEndoWNAFBench(EC_ShortW_Jac[Fp[curve], G1], bits, window = 2, MulIters)
      scalarMulVartimeEndoWNAFBench(EC_ShortW_Jac[Fp[curve], G1], bits, window = 3, MulIters)
      scalarMulVartimeEndoWNAFBench(EC_ShortW_Jac[Fp[curve], G1], bits, window = 4, MulIters)
      scalarMulVartimeEndoWNAFBench(EC_ShortW_Jac[Fp[curve], G1], bits, window = 5, MulIters)
      separator()
      scalarMulEndo(      EC_ShortW_Prj[Fp[curve], G1], bits, MulIters)
      scalarMulEndoWindow(EC_ShortW_Prj[Fp[curve], G1], bits, MulIters)
      scalarMulEndo(      EC_ShortW_Jac[Fp[curve], G1], bits, MulIters)
      scalarMulEndoWindow(EC_ShortW_Jac[Fp[curve], G1], bits, MulIters)
      separator()
    separator()

main()
notes()
