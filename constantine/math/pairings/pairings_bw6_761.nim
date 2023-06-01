# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  ../config/curves,
  ../arithmetic,
  ../extension_fields,
  ../elliptic/[
    ec_shortweierstrass_affine,
    ec_shortweierstrass_projective
  ],
  ../isogenies/frobenius,
  ../constants/zoo_pairings,
  ./lines_eval,
  ./miller_loops

export zoo_pairings # generic sandwich https://github.com/nim-lang/Nim/issues/11225

# ############################################################
#
#                 Optimal ATE pairing for
#                      BW6-761 curve
#
# ############################################################

# Generic pairing implementation
# ----------------------------------------------------------------

func millerLoopBW6_761_naive[C](
       f: var Fp6[C],
       Q: ECP_ShortW_Aff[Fp[C], G2],
       P: ECP_ShortW_Aff[Fp[C], G1]
     ) =
  ## Miller Loop for BW6_761 curve
  ## Computes f_{u+1,Q}(P)*Frobenius(f_{u*(u^2-u-1),Q}(P))
  var T {.noInit.}: ECP_ShortW_Prj[Fp[C], G2]
  T.fromAffine(Q)

  basicMillerLoop(
    f, T,
    P, Q,
    pairing(C, ate_param_1_unopt), pairing(C, ate_param_1_unopt_isNeg)
  )

  var f2 {.noInit.}: typeof(f)
  T.fromAffine(Q)

  basicMillerLoop(
    f2, T,
    P, Q,
    pairing(C, ate_param_2_unopt), pairing(C, ate_param_2_unopt_isNeg)
  )

  let t = f2
  f2.frobenius_map(t)
  f *= f2

func finalExpGeneric[C: static Curve](f: var Fp6[C]) =
  ## A generic and slow implementation of final exponentiation
  ## for sanity checks purposes.
  f.pow_vartime(C.pairing(finalexponent), window = 3)

func finalExpHard_BW6_761*[C: static Curve](f: var Fp6[C]) =
  ## A generic and slow implementation of final exponentiation
  ## for sanity checks purposes.
  f.pow_vartime(C.pairing(finalexponent_hard), window = 3)

# Optimized pairing implementation
# ----------------------------------------------------------------

func millerLoopBW6_761_opt_to_debug[C](
       f: var Fp6[C],
       Q: ECP_ShortW_Aff[Fp[C], G2],
       P: ECP_ShortW_Aff[Fp[C], G1]
     ) {.used.} =
  ## Miller Loop Otpimized for BW6_761 curve

  # 1st part: f_{u,Q}(P)
  # ------------------------------
  var T {.noInit.}: ECP_ShortW_Prj[Fp[C], G2]
  var line {.noInit.}: Line[Fp[C]]

  T.fromAffine(Q)
  f.setOne()

  template u: untyped = pairing(C, ate_param_1_opt)
  for i in countdown(u.bits - 2, 1):
    square(f)
    line_double(line, T, P)
    mul_by_line(f, line)

    let bit = u.bit(i).int8
    if bit == 1:
      line_add(line, T, Q, P)
      mul_by_line(f, line)

  # Fixup
  # ------------------------------
  var minvu {.noInit.}, mu {.noInit.}, muplusone: typeof(f)
  var Qu {.noInit.}, nQu {.noInit.}: typeof(Q)

  mu = f
  minvu.inv(f)
  Qu.affine(T)
  nQu.neg(Qu)

  # Drop the vertical line
  line.line_add(T, Q, P) # TODO: eval without updating T
  muplusone = mu
  muplusone.mul_by_line(line)

  # 2nd part: f_{u²-u-1,Q}(P)
  # ------------------------------
  # We restart from `f` and `T`
  T.fromAffine(Qu)

  template u: untyped = pairing(C, ate_param_2_opt)
  var u3 = pairing(C, ate_param_2_opt)
  u3 *= 3
  for i in countdown(u3.bits - 2, 1):
    square(f)
    line_double(line, T, P)
    mul_by_line(f, line)

    let naf = bit(u3, i).int8 - bit(u, i).int8 # This can throw exception
    if naf == 1:
      line_add(line, T, Qu, P)
      mul_by_line(f, line)
      f *= mu
    elif naf == -1:
      line_add(line, T, nQu, P)
      mul_by_line(f, line)
      f *= minvu

  # Final
  # ------------------------------
  let t = f
  f.frobenius_map(t)
  f *= muplusone

# Public
# ----------------------------------------------------------------

func pairing_bw6_761_reference*[C](
       gt: var Fp6[C],
       P: ECP_ShortW_Aff[Fp[C], G1],
       Q: ECP_ShortW_Aff[Fp[C], G2]) =
  ## Compute the optimal Ate Pairing for BW6 curves
  ## Input: P ∈ G1, Q ∈ G2
  ## Output: e(P, Q) ∈ Gt
  ##
  ## Reference implementation
  {.error: "BW6_761 Miller loop is not working yet".}
  gt.millerLoopBW6_761_naive(Q, P)
  gt.finalExpEasy()
  gt.finalExpHard_BW6_761()