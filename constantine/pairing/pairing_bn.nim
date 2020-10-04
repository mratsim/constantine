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
  ./lines_projective,
  ./mul_fp12_by_lines,
  ./cyclotomic_fp12,
  ../isogeny/frobenius,
  ../curves/zoo_pairings

# ############################################################
#
#                 Optimal ATE pairing for
#                      BN curves
#
# ############################################################

# - Memory-saving computation of the pairing final exponentiation on BN curves
#   Sylvain Duquesne and Loubna Ghammam, 2015
#   https://eprint.iacr.org/2015/192
#
# - Faster hashing to G2
#   Laura Fuentes-Castañeda, Edward Knapp,
#   Francisco Jose Rodríguez-Henríquez, 2011
#   https://link.springer.com/content/pdf/10.1007%2F978-3-642-28496-0_25.pdf
#
# - Faster Pairing Computations on Curves with High-Degree Twists
#   Craig Costello, Tanja Lange, and Michael Naehrig, 2009
#   https://eprint.iacr.org/2009/615.pdf

# Generic pairing implementation
# ----------------------------------------------------------------

func millerLoopGenericBN*[C](
       f: var Fp12[C],
       P: ECP_ShortW_Aff[Fp[C]],
       Q: ECP_ShortW_Aff[Fp2[C]]
     ) =
  ## Generic Miller Loop for BN curves
  ## Computes f{6u+2,Q}(P) with u the BN curve parameter
  # TODO: retrieve the curve parameter from the curve declaration

  # TODO - boundary cases
  #   Loop start
  #     The literatture starts from both L-1 or L-2:
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
  #      have an extra line addition after the main loop, this seems related to
  #      the NAF recoding and not Miller Loop
  #    - With r the order of G1 / G2 / GT,
  #      we have [r]T = Inf
  #      Hence, [r-1]T = -T
  #      so either we use complete addition
  #      or we special case line addition of T and -T (it's a vertical line)
  #      or we ensure the loop is done for a number of iterations strictly less
  #      than the curve order which is the case for BN curves

  var
    T {.noInit.}: ECP_ShortW_Proj[Fp2[C]]
    line {.noInit.}: Line[Fp2[C], C.getSexticTwist()]
    nQ{.noInit.}: typeof(Q)

  T.projectiveFromAffine(Q)
  nQ.neg(Q)
  f.setOne()

  template mul(f, line): untyped =
    when C.getSexticTwist() == D_Twist:
      f.mul_sparse_by_line_xyz000(line)
    else:
      f.mul_sparse_by_line_xy000z(line)

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

  # Ate pairing for BN curves need adjustment after Miller loop
  when C.pairing(ate_param_isNeg):
    T.neg()
  var V {.noInit.}: typeof(Q)

  V.frobenius_psi(Q)
  line.line_add(T, V, P)
  f.mul_sparse_by_line_xyz000(line)

  V.frobenius_psi2(Q)
  V.neg()
  line.line_add(T, V, P)
  f.mul_sparse_by_line_xyz000(line)

func finalExpGeneric[C: static Curve](f: var Fp12[C]) =
  ## A generic and slow implementation of final exponentiation
  ## for sanity checks purposes.
  f.powUnsafeExponent(C.pairing(finalexponent), window = 3)

func pairing_bn_reference*[C](gt: var Fp12[C], P: ECP_ShortW_Proj[Fp[C]], Q: ECP_ShortW_Proj[Fp2[C]]) =
  ## Compute the optimal Ate Pairing for BN curves
  ## Input: P ∈ G1, Q ∈ G2
  ## Output: e(P, Q) ∈ Gt
  ##
  ## Reference implementation
  var Paff {.noInit.}: ECP_ShortW_Aff[Fp[C]]
  var Qaff {.noInit.}: ECP_ShortW_Aff[Fp2[C]]
  Paff.affineFromProjective(P)
  Qaff.affineFromProjective(Q)
  gt.millerLoopGenericBN(Paff, Qaff)
  gt.finalExpGeneric()

# Optimized pairing implementation
# ----------------------------------------------------------------

func finalExpHard_BN*[C: static Curve](f: var Fp12[C]) =
  ## Hard part of the final exponentiation
  ## Specialized for BN curves
  ##
  # - Memory-saving computation of the pairing final exponentiation on BN curves
  #   Sylvain Duquesne and Loubna Ghammam, 2015
  #   https://eprint.iacr.org/2015/192
  # - Faster hashing to G2
  #   Laura Fuentes-Castañeda, Edward Knapp,
  #   Francisco Jose Rodríguez-Henríquez, 2011
  #   https://link.springer.com/content/pdf/10.1007%2F978-3-642-28496-0_25.pdf
  #
  # We use the Fuentes-Castañeda et al algorithm without
  # memory saving optimization
  # as that variant has an exponentiation by -2u-1
  # that requires another addition chain
  var t0 {.noInit.}, t1 {.noinit.}, t2 {.noinit.}, t3 {.noinit.}, t4 {.noinit.}: Fp12[C]

  t0.pow_u(f, invert = false)  # t0 = f^|u|
  t0.cyclotomic_square()       # t0 = f^2|u|
  t1.cyclotomic_square(t0)     # t1 = f^4|u|
  t1 *= t0                     # t1 = f^6|u|
  t2.pow_u(t1, invert = false) # t2 = f^6u²

  if C.pairing(ate_param_is_Neg):
    t3.cyclotomic_inv(t1)      # t3 = f^6u
  else:
    t3 = t1                    # t3 = f^6u
  t1.prod(t2, t3)              # t1 = f^6u.f^6u²
  t3.cyclotomic_square(t2)     # t3 = f^12u²
  t4.pow_u(t3)                 # t4 = f^12u³
  t4 *= t1                     # t4 = f^(6u + 6u² + 12u³) = f^λ₂

  if not C.pairing(ate_param_is_Neg):
    t0.cyclotomic_inv()        # t0 = f^-2u
  t3.prod(t4, t0)              # t3 = f^(4u + 6u² + 12u³)

  t0.prod(t2, t4)              # t0 = f^6u.f^12u².f^12u³
  t0 *= f                      # t0 = f^(1 + 6u + 12u² + 12u³) = f^λ₀

  t2.frobenius_map(t3)         # t2 = f^(4u + 6u² + 12u³)p = f^λ₁p
  t0 *= t2                     # t0 = f^(λ₀+λ₁p)

  t2.frobenius_map(t4, 2)      # t2 = f^λ₂p²
  t0 *= t2                     # t0 = f^(λ₀ + λ₁p + λ₂p²)

  t2.cyclotomic_inv(f)         # t2 = f⁻¹
  t2 *= t3                     # t3 = f^(-1 + 4u + 6u² + 12u³) = f^λ₃

  f.frobenius_map(t2, 3)       # r = f^λ₃p³
  f *= t0                      # r = f^(λ₀ + λ₁p + λ₂p² + λ₃p³) = f^((p⁴-p²+1)/r)

func pairing_bn*[C](gt: var Fp12[C], P: ECP_ShortW_Proj[Fp[C]], Q: ECP_ShortW_Proj[Fp2[C]]) =
  ## Compute the optimal Ate Pairing for BLS12 curves
  ## Input: P ∈ G1, Q ∈ G2
  ## Output: e(P, Q) ∈ Gt
  var Paff {.noInit.}: ECP_ShortW_Aff[Fp[C]]
  var Qaff {.noInit.}: ECP_ShortW_Aff[Fp2[C]]
  Paff.affineFromProjective(P)
  Qaff.affineFromProjective(Q)
  gt.millerLoopGenericBN(Paff, Qaff)
  gt.finalExpEasy()
  gt.finalExpHard_BN()
