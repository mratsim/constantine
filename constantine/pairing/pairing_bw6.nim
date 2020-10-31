# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  ../config/[curves, type_fp],
  ../towers,
  ../elliptic/[
    ec_shortweierstrass_affine,
    ec_shortweierstrass_projective
  ],
  ../isogeny/frobenius,
  ../curves/zoo_pairings,
  ./lines_projective,
  ./mul_fp6_by_lines,
  ./miller_loops

# ############################################################
#
#                 Optimal ATE pairing for
#                      BW6 curves
#
# ############################################################

# Generic pairing implementation
# ----------------------------------------------------------------

func millerLoopGenericBW6*[C](
       f: var Fp6[C],
       P: ECP_ShortW_Aff[Fp[C], NotOnTwist],
       Q: ECP_ShortW_Aff[Fp[C], OnTwist]
     ) =
  ## Generic Miller Loop for BW6 curve
  ## Computes f_{u+1,Q}(P)*Frobenius(f_{u*(u^2-u-1),Q}(P))
  var
    T {.noInit.}: ECP_ShortW_Proj[Fp[C], OnTwist]
    line {.noInit.}: Line[Fp[C]]
    nQ{.noInit.}: typeof(Q)

  T.projectiveFromAffine(Q)
  nQ.neg(Q)

  # Note we can use the fact that
  #  f_{u+1,Q}(P) = f_{u,Q}(P) . l_{[u]Q,Q}(P)
  #  f_{u³-u²-u,Q}(P) = f_{u (u²-u-1),Q}(P)
  #                   = (f_{u,Q}(P))^(u²-u-1) * f_{v,[u]Q}(P)
  #
  #  to have a common computation f_{u,Q}(P)
  # but this require a scalar mul [u]Q
  # and then its inversion to plug it back in the second Miller loop

  # 1st part: f_{u+1,Q}(P)
  # ------------------------------
  basicMillerLoop(
    f, T, line,
    P, Q, nQ,
    ate_param_1, ate_param_1_isNeg
  )

  # 2nd part: f_{u³-u²-u,Q}(P)
  # ------------------------------
  T.projectiveFromAffine(Q)
  var f2 {.noInit.}: typeof(f)
  
  basicMillerLoop(
    f2, T, line,
    P, Q, nQ,
    ate_param_2, ate_param_2_isNeg
  )
  let t = f2
  f2.frobenius_map(t)

  # Final
  # ------------------------------
  f *= f2

func finalExpGeneric[C: static Curve](f: var Fp6[C]) =
  ## A generic and slow implementation of final exponentiation
  ## for sanity checks purposes.
  f.powUnsafeExponent(C.pairing(finalexponent), window = 3)

func pairing_bw6_reference*[C](
       gt: var Fp6[C],
       P: ECP_ShortW_Proj[Fp[C], NotOnTwist],
       Q: ECP_ShortW_Proj[Fp[C], OnTwist]) =
  ## Compute the optimal Ate Pairing for BW6 curves
  ## Input: P ∈ G1, Q ∈ G2
  ## Output: e(P, Q) ∈ Gt
  ##
  ## Reference implementation
  var Paff {.noInit.}: ECP_ShortW_Aff[Fp[C], NotOnTwist]
  var Qaff {.noInit.}: ECP_ShortW_Aff[Fp[C], OnTwist]
  Paff.affineFromProjective(P)
  Qaff.affineFromProjective(Q)
  gt.millerLoopGenericBW6(Paff, Qaff)
  gt.finalExpGeneric()
