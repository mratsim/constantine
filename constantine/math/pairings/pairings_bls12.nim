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
  constantine/math/arithmetic,
  ./cyclotomic_subgroups,
  ./miller_loops

export zoo_pairings # generic sandwich https://github.com/nim-lang/Nim/issues/11225

# No exceptions allowed
{.push raises: [].}

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

func millerLoopGenericBLS12*[Name](
       f: var AnyFp12[Name],
       Q: EC_ShortW_Aff[Fp2[Name], G2],
       P: EC_ShortW_Aff[Fp[Name], G1]
     ) {.meter.} =
  ## Generic Miller Loop for BLS12 curve
  ## Computes f{u,Q}(P) with u the BLS curve parameter
  var T {.noInit.}: EC_ShortW_Prj[Fp2[Name], G2]
  T.fromAffine(Q)

  basicMillerLoop(f, T, P, Q, pairing(Name, ate_param))

func millerLoopGenericBLS12*[Name](
       f: var AnyFp12[Name],
       Qs: ptr UncheckedArray[EC_ShortW_Aff[Fp2[Name], G2]],
       Ps: ptr UncheckedArray[EC_ShortW_Aff[Fp[Name], G1]],
       N: int
     ) {.noinline, tags:[Alloca], meter.} =
  ## Generic Miller Loop for BLS12 curve
  ## Computes f{u,Q}(P) with u the BLS curve parameter
  var Ts = allocStackArray(EC_ShortW_Prj[Fp2[Name], G2], N)
  for i in 0 ..< N:
    Ts[i].fromAffine(Qs[i])

  basicMillerLoop(f, Ts, Ps, Qs, N, pairing(Name, ate_param))

func finalExpGeneric[Name: static Algebra](f: var Fp12[Name]) =
  ## A generic and slow implementation of final exponentiation
  ## for sanity checks purposes.
  f.pow_vartime(Name.pairing(finalexponent), window = 3)

func pairing_bls12_reference*[Name](
       gt: var AnyFp12[Name],
       P: EC_ShortW_Aff[Fp[Name], G1],
       Q: EC_ShortW_Aff[Fp2[Name], G2]) =
  ## Compute the optimal Ate Pairing for BLS12 curves
  ## Input: P ∈ G1, Q ∈ G2
  ## Output: e(P, Q) ∈ Gt
  ##
  ## Reference implementation
  gt.millerLoopGenericBLS12(Q, P)
  gt.finalExpGeneric()

# Optimized pairing implementation
# ----------------------------------------------------------------

func finalExpHard_BLS12*[Name](f: var AnyFp12[Name]) {.meter.} =
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

  var v0 {.noInit.}, v1 {.noInit.}, v2 {.noInit.}: typeof(f)

  # Save for f³ and (x−1)²
  v2.cyclotomic_square(f)      # v2 = f²

  # (x−1)²
  when Name.pairing(ate_param).isEven().bool:
    v0.cycl_exp_by_curve_param_div2(v2) # v0 = (f²)^(x/2) = f^x
  else:
    v0.cycl_exp_by_curve_param(f)
  v1.cyclotomic_inv(f)         # v1 = f^-1
  v0 *= v1                     # v0 = f^(x-1)
  v1.cycl_exp_by_curve_param(v0) # v1 = (f^(x-1))^x
  v0.cyclotomic_inv()          # v0 = (f^(x-1))^-1
  v0 *= v1                     # v0 = (f^(x-1))^(x-1) = f^((x-1)*(x-1)) = f^((x-1)²)

  # (x+p)
  v1.cycl_exp_by_curve_param(v0) # v1 = f^((x-1)².x)
  v0.frobenius_map(v0)         # v0 = f^((x-1)².p)
  v0 *= v1                     # v0 = f^((x-1)².(x+p))

  # + 3
  f *= v2                      # f = f³

  # (x²+p²−1)
  v2.cycl_exp_by_curve_param(v0, invert = false)
  v1.cycl_exp_by_curve_param(v2, invert = false) # v1 = f^((x-1)².(x+p).x²)
  v2.frobenius_map(v0, 2)      # v2 = f^((x-1)².(x+p).p²)
  v0.cyclotomic_inv()          # v0 = f^((x-1)².(x+p).-1)
  v0 *= v1                     # v0 = f^((x-1)².(x+p).(x²-1))
  v0 *= v2                     # v0 = f^((x-1)².(x+p).(x²+p²-1))

  # (x−1)².(x+p).(x²+p²−1) + 3
  f *= v0

func pairing_bls12*[Name](
       gt: var AnyFp12[Name],
       P: EC_ShortW_Aff[Fp[Name], G1],
       Q: EC_ShortW_Aff[Fp2[Name], G2]) {.meter.} =
  ## Compute the optimal Ate Pairing for BLS12 curves
  ## Input: P ∈ G1, Q ∈ G2
  ## Output: e(P, Q) ∈ Gt
  gt.millerLoopAddchain(Q, P)
  gt.finalExpEasy()
  gt.finalExpHard_BLS12()

func pairing_bls12*[Name: static Algebra](
       gt: var AnyFp12[Name],
       Ps: ptr UncheckedArray[EC_ShortW_Aff[Fp[Name], G1]],
       Qs: ptr UncheckedArray[EC_ShortW_Aff[Fp2[Name], G2]],
       len: int) {.meter.} =
  ## Compute the optimal Ate Pairing for BLS12 curves
  ## Input: an array of Ps ∈ G1 and Qs ∈ G2
  ## Output:
  ##   The product of pairings
  ##   e(P₀, Q₀) * e(P₁, Q₁) * e(P₂, Q₂) * ... * e(Pₙ, Qₙ) ∈ Gt
  gt.millerLoopAddchain(Qs, Ps, len)
  gt.finalExpEasy()
  gt.finalExpHard_BLS12()

func pairing_bls12*[Name: static Algebra](
       gt: var AnyFp12[Name],
       Ps: openArray[EC_ShortW_Aff[Fp[Name], G1]],
       Qs: openArray[EC_ShortW_Aff[Fp2[Name], G2]]) {.inline.} =
  ## Compute the optimal Ate Pairing for BLS12 curves
  ## Input: an array of Ps ∈ G1 and Qs ∈ G2
  ## Output:
  ##   The product of pairings
  ##   e(P₀, Q₀) * e(P₁, Q₁) * e(P₂, Q₂) * ... * e(Pₙ, Qₙ) ∈ Gt
  debug: doAssert Ps.len == Qs.len
  gt.pairing_bls12(Ps.asUnchecked(), Qs.asUnchecked(), Ps.len)
