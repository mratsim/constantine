# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  ../config/[common, curves, type_ff],
  ../towers,
  ../elliptic/[
    ec_shortweierstrass_affine,
    ec_shortweierstrass_projective
  ],
  ../isogeny/frobenius,
  ./lines_projective,
  ./mul_fp12_by_lines,
  ./cyclotomic_fp12,
  ../curves/zoo_pairings

# ############################################################
#
#                 Optimal ATE pairing for
#                      BLS12 curves
#
# ############################################################

# - Efficient Final Exponentiation
#   via Cyclotomic Structure for Pairings
#   over Families of Elliptic Curves
#   Daiki Hayashida and Kenichiro Hayasaka
#   and Tadanori Teruya, 2020
#   https://eprint.iacr.org/2020/875.pdf
#
# - Improving the computation of the optimal ate pairing
#   for a high security level.
#   Loubna Ghammam, Emmanuel Fouotsa
#   J. Appl. Math. Comput.59, 21–36 (2019)
#
# - Faster Pairing Computations on Curves with High-Degree Twists
#   Craig Costello, Tanja Lange, and Michael Naehrig, 2009
#   https://eprint.iacr.org/2009/615.pdf

# Generic pairing implementation
# ----------------------------------------------------------------

func millerLoopGenericBLS12*[C](
       f: var Fp12[C],
       P: ECP_ShortW_Aff[Fp[C], NotOnTwist],
       Q: ECP_ShortW_Aff[Fp2[C], OnTwist]
     ) {.meter.} =
  ## Generic Miller Loop for BLS12 curve
  ## Computes f{u,Q}(P) with u the BLS curve parameter

  # Boundary cases
  #   Loop start
  #     The litterature starts from both L-1 or L-2:
  #     L-1:
  #     - Scott2019, Pairing Implementation Revisited, Algorithm 1
  #     - Aranha2010, Faster Explicit Formulas ..., Algorithm 1
  #     L-2
  #     - Beuchat2010, High-Speed Software Implementation ..., Algorithm 1
  #     - Aranha2013, The Realm of The Pairings, Algorithm 1
  #     - Costello, Thesis, Algorithm 2.1
  #     - Costello2012, Pairings for Beginners, Algorithm 5.1
  #
  #     Even the guide to pairing based cryptography has both
  #     Chapter 3: L-1 (Algorithm 3.1)
  #     Chapter 11: L-2 (Algorithm 11.1) but it explains why L-2 (unrolling)
  #  Loop end
  #    - Some implementation, for example Beuchat2010 or the Guide to Pairing-Based Cryptography
  #      have extra line additions after the main loop,
  #      this is needed for BN curves.
  #    - With r the order of G1 / G2 / GT,
  #      we have [r]T = Inf
  #      Hence, [r-1]T = -T
  #      so either we use complete addition
  #      or we special case line addition of T and -T (it's a vertical line)
  #      or we ensure the loop is done for a number of iterations strictly less
  #      than the curve order which is the case for BLS12 curves
  var
    T {.noInit.}: ECP_ShortW_Proj[Fp2[C], OnTwist]
    line {.noInit.}: Line[Fp2[C]]
    nQ{.noInit.}: typeof(Q)

  T.projectiveFromAffine(Q)
  nQ.neg(Q)
  f.setOne()

  template u: untyped = C.pairing(ate_param)
  let u3 = 3*C.pairing(ate_param)
  for i in countdown(u3.bits - 2, 1):
    f.square()
    line.line_double(T, P)

    f.mul(line)

    let naf = u3.bit(i).int8 - u.bit(i).int8 # This can throw exception
    if naf == 1:
      line.line_add(T, Q, P)
      f.mul(line)
    elif naf == -1:
      line.line_add(T, nQ, P)
      f.mul(line)

  when C.pairing(ate_param_isNeg):
    # In GT, x^-1 == conjugate(x)
    # Remark 7.1, chapter 7.1.1 of Guide to Pairing-Based Cryptography, El Mrabet, 2017
    f.conj()

func finalExpGeneric[C: static Curve](f: var Fp12[C]) =
  ## A generic and slow implementation of final exponentiation
  ## for sanity checks purposes.
  f.powUnsafeExponent(C.pairing(finalexponent), window = 3)

func pairing_bls12_reference*[C](
       gt: var Fp12[C],
       P: ECP_ShortW_Proj[Fp[C], NotOnTwist],
       Q: ECP_ShortW_Proj[Fp2[C], OnTwist]) =
  ## Compute the optimal Ate Pairing for BLS12 curves
  ## Input: P ∈ G1, Q ∈ G2
  ## Output: e(P, Q) ∈ Gt
  ##
  ## Reference implementation
  var Paff {.noInit.}: ECP_ShortW_Aff[Fp[C], NotOnTwist]
  var Qaff {.noInit.}: ECP_ShortW_Aff[Fp2[C], OnTwist]
  Paff.affineFromProjective(P)
  Qaff.affineFromProjective(Q)
  gt.millerLoopGenericBLS12(Paff, Qaff)
  gt.finalExpGeneric()

# Optimized pairing implementation
# ----------------------------------------------------------------

func finalExpHard_BLS12*[C](f: var Fp12[C]) {.meter.} =
  ## Hard part of the final exponentiation
  ## Specialized for BLS12 curves
  ##
  # - Efficient Final Exponentiation
  #   via Cyclotomic Structure for Pairings
  #   over Families of Elliptic Curves
  #   Daiki Hayashida and Kenichiro Hayasaka
  #   and Tadanori Teruya, 2020
  #   https://eprint.iacr.org/2020/875.pdf
  #
  # p14: 3 Φ₁₂(p(x))/r(x) = (x−1)² (x+p) (x²+p²−1) + 3
  #
  # with
  # - Eₓ being f^x
  # - Eₓ/₂ being f^(x/2)
  # - M₁₂ being mul in Fp12
  # - S₁₂ being cyclotomic squaring
  # - Fₙ being n Frobenius applications

  var v0 {.noInit.}, v1 {.noInit.}, v2 {.noInit.}: Fp12[C]

  # Save for f³ and (x−1)²
  v2.cyclotomic_square(f)      # v2 = f²

  # (x−1)²
  when C.pairing(ate_param).isEven.bool:
    v0.pow_xdiv2(v2)           # v0 = (f²)^(x/2) = f^x
  else:
    v0.pow_x(f)
  v1.cyclotomic_inv(f)         # v1 = f^-1
  v0 *= v1                     # v0 = f^(x-1)
  v1.pow_x(v0)                 # v1 = (f^(x-1))^x
  v0.cyclotomic_inv()          # v0 = (f^(x-1))^-1
  v0 *= v1                     # v0 = (f^(x-1))^(x-1) = f^((x-1)*(x-1)) = f^((x-1)²)

  # (x+p)
  v1.pow_x(v0)                 # v1 = f^((x-1)².x)
  v0.frobenius_map(v0)         # v0 = f^((x-1)².p)
  v0 *= v1                     # v0 = f^((x-1)².(x+p))

  # + 3
  f *= v2                      # f = f³

  # (x²+p²−1)
  v2.pow_x(v0, invert = false)
  v1.pow_x(v2, invert = false) # v1 = f^((x-1)².(x+p).x²)
  v2.frobenius_map(v0, 2)      # v2 = f^((x-1)².(x+p).p²)
  v0.cyclotomic_inv()          # v0 = f^((x-1)².(x+p).-1)
  v0 *= v1                     # v0 = f^((x-1)².(x+p).(x²-1))
  v0 *= v2                     # v0 = f^((x-1)².(x+p).(x²+p²-1))

  # (x−1)².(x+p).(x²+p²−1) + 3
  f *= v0

func pairing_bls12*[C](
       gt: var Fp12[C],
       P: ECP_ShortW_Proj[Fp[C], NotOnTwist],
       Q: ECP_ShortW_Proj[Fp2[C], OnTwist]) {.meter.} =
  ## Compute the optimal Ate Pairing for BLS12 curves
  ## Input: P ∈ G1, Q ∈ G2
  ## Output: e(P, Q) ∈ Gt
  var Paff {.noInit.}: ECP_ShortW_Aff[Fp[C], NotOnTwist]
  var Qaff {.noInit.}: ECP_ShortW_Aff[Fp2[C], OnTwist]
  Paff.affineFromProjective(P)
  Qaff.affineFromProjective(Q)
  gt.millerLoopGenericBLS12(Paff, Qaff)
  gt.finalExpEasy()
  gt.finalExpHard_BLS12()
