# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  constantine/platforms/abstractions,
  constantine/named/algebras,
  constantine/math/extension_fields,
  constantine/math/elliptic/[
    ec_shortweierstrass_affine,
    ec_shortweierstrass_projective
  ],
  constantine/math/endomorphisms/frobenius,
  constantine/named/zoo_pairings,
  ./cyclotomic_subgroups,
  ./miller_loops

export zoo_pairings # generic sandwich https://github.com/nim-lang/Nim/issues/11225

# No exceptions allowed
{.push raises: [].}

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

func millerLoopGenericBN*[Name](
       f: var AnyFp12[Name],
       Q: EC_ShortW_Aff[Fp2[Name], G2],
       P: EC_ShortW_Aff[Fp[Name], G1],
     ) {.meter.} =
  ## Generic Miller Loop for BN curves
  ## Computes f{6u+2,Q}(P) with u the BN curve parameter
  var T {.noInit.}: EC_ShortW_Prj[Fp2[Name], G2]
  T.fromAffine(Q)

  basicMillerLoop(f, T, P, Q, pairing(Name, ate_param))

  when pairing(Name, ate_param_is_neg):
    f.conj()
    T.neg()

  # Ate pairing for BN curves needs adjustment after basic Miller loop
  f.millerCorrectionBN(T, Q, P)

func millerLoopGenericBN*[Name](
       f: var AnyFp12[Name],
       Qs: ptr UncheckedArray[EC_ShortW_Aff[Fp2[Name], G2]],
       Ps: ptr UncheckedArray[EC_ShortW_Aff[Fp[Name], G1]],
       N: int
     ) {.noinline, tags:[Alloca], meter.} =
  ## Generic Miller Loop for BN curves
  ## Computes f{6u+2,Q}(P) with u the BN curve parameter
  var Ts = allocStackArray(EC_ShortW_Prj[Fp2[Name], G2], N)
  for i in 0 ..< N:
    Ts[i].fromAffine(Qs[i])

  basicMillerLoop(f, Ts, Ps, Qs, N, pairing(Name, ate_param))

  when pairing(Name, ate_param_is_neg):
    f.conj()
    for i in 0 ..< N:
      Ts[i].neg()

  # Ate pairing for BN curves needs adjustment after basic Miller loop
  for i in 0 ..< N:
    f.millerCorrectionBN(Ts[i], Qs[i], Ps[i])

func finalExpGeneric[Name: static Algebra](f: var Fp12[Name]) =
  ## A generic and slow implementation of final exponentiation
  ## for sanity checks purposes.
  f.pow_vartime(Name.pairing(finalexponent), window = 3)

func pairing_bn_reference*[Name](
       gt: var AnyFp12[Name],
       P: EC_ShortW_Aff[Fp[Name], G1],
       Q: EC_ShortW_Aff[Fp2[Name], G2]) =
  ## Compute the optimal Ate Pairing for BN curves
  ## Input: P ∈ G1, Q ∈ G2
  ## Output: e(P, Q) ∈ Gt
  ##
  ## Reference implementation
  gt.millerLoopGenericBN(P, Q)
  gt.finalExpGeneric()

# Optimized pairing implementation
# ----------------------------------------------------------------

func finalExpHard_BN*[Name: static Algebra](f: var AnyFp12[Name]) {.meter.} =
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
  var t0 {.noInit.}, t1 {.noinit.}, t2 {.noinit.}, t3 {.noinit.}, t4 {.noinit.}: typeof(f)

  t0.cycl_exp_by_curve_param(f, invert = false)  # t0 = f^|u|
  t0.cyclotomic_square()       # t0 = f^2|u|
  t1.cyclotomic_square(t0)     # t1 = f^4|u|
  t1 *= t0                     # t1 = f^6|u|
  t2.cycl_exp_by_curve_param(t1, invert = false) # t2 = f^6u²

  if Name.pairing(ate_param_is_Neg):
    t3.cyclotomic_inv(t1)      # t3 = f^6u
  else:
    t3 = t1                    # t3 = f^6u
  t1.prod(t2, t3)              # t1 = f^6u.f^6u²
  t3.cyclotomic_square(t2)     # t3 = f^12u²
  t4.cycl_exp_by_curve_param(t3)                 # t4 = f^12u³
  t4 *= t1                     # t4 = f^(6u + 6u² + 12u³) = f^λ₂

  if not Name.pairing(ate_param_is_Neg):
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

func pairing_bn*[Name](
       gt: var AnyFp12[Name],
       P: EC_ShortW_Aff[Fp[Name], G1],
       Q: EC_ShortW_Aff[Fp2[Name], G2]) {.meter.} =
  ## Compute the optimal Ate Pairing for BN curves
  ## Input: P ∈ G1, Q ∈ G2
  ## Output: e(P, Q) ∈ Gt
  when Name == BN254_Nogami:
    gt.millerLoopAddChain(Q, P)
  else:
    gt.millerLoopGenericBN(Q, P)
  gt.finalExpEasy()
  gt.finalExpHard_BN()

func pairing_bn*[Name: static Algebra](
       gt: var AnyFp12[Name],
       Ps: ptr UncheckedArray[EC_ShortW_Aff[Fp[Name], G1]],
       Qs: ptr UncheckedArray[EC_ShortW_Aff[Fp2[Name], G2]],
       len: int) {.meter.} =
  ## Compute the optimal Ate Pairing for BLS12 curves
  ## Input: an array of Ps ∈ G1 and Qs ∈ G2
  ## Output:
  ##   The product of pairings
  ##   e(P₀, Q₀) * e(P₁, Q₁) * e(P₂, Q₂) * ... * e(Pₙ, Qₙ) ∈ Gt
  when Name == BN254_Nogami:
    gt.millerLoopAddChain(Qs, Ps, len)
  else:
    gt.millerLoopGenericBN(Qs, Ps, len)
  gt.finalExpEasy()
  gt.finalExpHard_BN()

func pairing_bn*[Name: static Algebra](
       gt: var AnyFp12[Name],
       Ps: openArray[EC_ShortW_Aff[Fp[Name], G1]],
       Qs: openArray[EC_ShortW_Aff[Fp2[Name], G2]]) {.inline.} =
  ## Compute the optimal Ate Pairing for BLS12 curves
  ## Input: an array of Ps ∈ G1 and Qs ∈ G2
  ## Output:
  ##   The product of pairings
  ##   e(P₀, Q₀) * e(P₁, Q₁) * e(P₂, Q₂) * ... * e(Pₙ, Qₙ) ∈ Gt
  debug: doAssert Ps.len == Qs.len
  gt.pairing_bn(Ps.asUnchecked(), Qs.asUnchecked(), Ps.len)
