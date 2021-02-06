# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  ../config/[curves, type_ff],
  ../arithmetic,
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

  # Note we can use the fact that
  #  f_{u+1,Q}(P) = f_{u,Q}(P) . l_{[u]Q,Q}(P)
  #  f_{u³-u²-u,Q}(P) = f_{u (u²-u-1),Q}(P)
  #                   = (f_{u,Q}(P))^(u²-u-1) * f_{v,[u]Q}(P)
  #
  # to have a common computation f_{u,Q}(P)
  # but this require a scalar mul [u]Q
  # and then its inversion to plug it back in the second Miller loop

  # 1st part: f_{u,Q}(P)
  # ------------------------------
  var
    T {.noInit.}: ECP_ShortW_Prj[Fp[C], OnTwist]
    line {.noInit.}: Line[Fp[C]]

  T.projectiveFromAffine(Q)
  f.setOne()

  template u: untyped = pairing(C, ate_param_1)
  for i in countdown(u.bits - 2, 1):
    square(f)
    line_double(line, T, P)
    mul(f, line)

    let bit = u.bit(i).int8
    if bit == 1:
      line_add(line, T, Q, P)
      mul(f, line)

  # Fixup
  # ------------------------------
  var minvu {.noInit.}, mu {.noInit.}, muplusone: typeof(f)
  var Qu {.noInit.}, nQu {.noInit.}: typeof(Q)

  mu = f
  minvu.inv(f)
  Qu.affineFromProjective(T)
  nQu.neg(Qu)

  # Drop the vertical line
  line.line_add(T, Q, P) # TODO: eval without updating T
  muplusone = mu
  muplusone.mul(line)

  # 2nd part: f_{u²-u-1,Q}(P)
  # ------------------------------
  # We restart from `f` and `T`
  T.projectiveFromAffine(Qu)

  template u: untyped = pairing(C, ate_param_2)
  var u3 = pairing(C, ate_param_2)
  u3 *= 3
  for i in countdown(u3.bits - 2, 1):
    square(f)
    line_double(line, T, P)
    mul(f, line)

    let naf = bit(u3, i).int8 - bit(u, i).int8 # This can throw exception
    if naf == 1:
      line_add(line, T, Qu, P)
      mul(f, line)
      f *= mu
    elif naf == -1:
      line_add(line, T, nQu, P)
      mul(f, line)
      f *= minvu

  # Final
  # ------------------------------
  let t = f
  f.frobenius_map(t)
  f *= muplusone

func finalExpGeneric[C: static Curve](f: var Fp6[C]) =
  ## A generic and slow implementation of final exponentiation
  ## for sanity checks purposes.
  f.powUnsafeExponent(C.pairing(finalexponent), window = 3)

func pairing_bw6_reference*[C](
       gt: var Fp6[C],
       P: ECP_ShortW_Prj[Fp[C], NotOnTwist],
       Q: ECP_ShortW_Prj[Fp[C], OnTwist]) =
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
