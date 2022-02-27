# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  # Internals
  ../../platforms/abstractions,
  ../config/curves,
  ../arithmetic,
  ../extension_fields,
  ../ec_shortweierstrass,
  ../io/io_bigints,
  ../isogenies/frobenius

func pow_BN254_Nogami_abs_u*[ECP: ECP_ShortW[Fp[BN254_Nogami], G1] or
       ECP_ShortW[Fp2[BN254_Nogami], G2]](
       r{.noalias.}: var ECP,
       P{.noalias.}: ECP
     ) =
  ## [u]P with u the curve parameter
  ## For BN254_Nogami [0x4080000000000001]P
  r.double(P)
  r.double_repeated(6)
  r += P
  r.double_repeated(55)
  r += P

func pow_BN254_Nogami_u[ECP: ECP_ShortW[Fp[BN254_Nogami], G1] or
       ECP_ShortW[Fp2[BN254_Nogami], G2]](
       r{.noalias.}: var ECP,
       P{.noalias.}: ECP
     ) {.inline.}=
  ## Does the scalar multiplication [u]P
  ## with u the BN curve parameter
  pow_BN254_Nogami_abs_u(r, P)
  r.neg()

func pow_BN254_Nogami_minus_u[ECP: ECP_ShortW[Fp[BN254_Nogami], G1] or
       ECP_ShortW[Fp2[BN254_Nogami], G2]](
       r{.noalias.}: var ECP,
       P{.noalias.}: ECP
     ) {.inline.}=
  ## Does the scalar multiplication [-u]P
  ## with u the BN curve parameter
  pow_BN254_Nogami_abs_u(r, P)

# ############################################################
#
#                Clear Cofactor - Naive
#
# ############################################################

const Cofactor_Eff_BN254_Nogami_G1 = BigInt[1].fromHex"0x1"
const Cofactor_Eff_BN254_Nogami_G2 = BigInt[444].fromHex"0xab11da940a5bd10e25327cb22360008556b23c24080002d6845e3404000009a4f95b60000000145460100000000018544800000000000c8"
  # r = 36x⁴ + 36x³ + 18x² + 6x + 1
  # G2.order() = (36x⁴ + 36x³ + 18x² + 6x + 1)(36x⁴ + 36x³ + 30x² + 6x + 1)
  #            = r * cofactor
  # Effective cofactor from Fuentes-Casteneda et al
  # −(18x³ + 12x² + 3x + 1)*cofactor

func clearCofactorReference*(P: var ECP_ShortW_Prj[Fp[BN254_Nogami], G1]) {.inline.} =
  ## Clear the cofactor of BN254_Nogami G1
  ## BN curves have a G1 cofactor of 1 so this is a no-op
  discard

func clearCofactorReference*(P: var ECP_ShortW_Prj[Fp2[BN254_Nogami], G2]) {.inline.} =
  ## Clear the cofactor of BN254_Nogami G2
  # Endomorphism acceleration cannot be used if cofactor is not cleared
  P.scalarMulGeneric(Cofactor_Eff_BN254_Nogami_G2)

# ############################################################
#
#                Clear Cofactor - Naive
#
# ############################################################

# BN G1
# ------------------------------------------------------------

func clearCofactorFast*(P: var ECP_ShortW_Prj[Fp[BN254_Nogami], G1]) {.inline.} =
  ## Clear the cofactor of BN254_Nogami G1
  ## BN curves have a prime order r hence all points on curve are in G1
  ## Hence this is a no-op
  discard

# BN G2
# ------------------------------------------------------------
#
# Implementation 
# Fuentes-Castaneda et al, "Fast Hashing to G2 on Pairing-Friendly Curves", https://doi.org/10.1007/978-3-642-28496-0_25*

func clearCofactorFast*(P: var ECP_ShortW_Prj[Fp2[BN254_Nogami], G2]) {.inline.} =
  ## Clear the cofactor of BN254_Nogami G2
  ## Optimized using endomorphisms
  ## P' → [x]P + [3x]ψ(P) + [x]ψ²(P) + ψ³(P)
  var xP{.noInit.}, t{.noInit.}: typeof(P)

  xP.pow_BN254_Nogami_u(P) # xP = [x]P
  t.frobenius_psi(P, 3)    # t  = ψ³(P)
  P.double(xP)    
  P += xP                  
  P.frobenius_psi(P)       # P  = [3x]ψ(P)
  P += t                   # P  = [3x]ψ(P) + ψ³(P)
  t.frobenius_psi(xP, 2)   # t  = [x]ψ²(P)
  P += xP                  # P  = [x]P + [3x]ψ(P) + ψ³(P)
  P += t                   # P  = [x]P + [3x]ψ(P) + [x]ψ²(P) + ψ³(P)

# ############################################################
#
#                Subgroup checks
#
# ############################################################

func isInSubgroup*(P: ECP_ShortW_Prj[Fp[BN254_Nogami], G1]): SecretBool {.inline.} =
  ## Returns true if P is in G1 subgroup, i.e. P is a point of order r.
  ## A point may be on a curve but not on the prime order r subgroup.
  ## Not checking subgroup exposes a protocol to small subgroup attacks.
  ## This is a no-op as on G1, all points are in the correct subgroup.
  ## 
  ## Warning ⚠: Assumes that P is on curve
  return CtTrue

func isInSubgroup*(P: ECP_ShortW_Prj[Fp2[BN254_Nogami], G2]): SecretBool =
  ## Returns true if P is in G2 subgroup, i.e. P is a point of order r.
  ## A point may be on a curve but not on the prime order r subgroup.
  ## Not checking subgroup exposes a protocol to small subgroup attacks.
  # Implementation: Scott, https://eprint.iacr.org/2021/1130.pdf
  #   A note on group membership tests for G1, G2 and GT
  #   on BLS pairing-friendly curves
  #
  #   The condition to apply the optimized endomorphism check on G₂ 
  #   is gcd(h₁, h₂) == 1 with h₁ and h₂ the cofactors on G₁ and G₂.
  #   In that case [p]Q == [t-1]Q as r = p+1-t and [r]Q = 0
  #   For BN curves h₁ = 1, hence Scott group membership tests can be used for BN curves
  #   
  #   p the prime modulus: 36u⁴ + 36u³ + 24u² + 6u + 1
  #   r the prime order:   36u⁴ + 36u³ + 18u² + 6u + 1
  #   t the trace:         6u² + 1
  var t0{.noInit.}, t1{.noInit.}: ECP_ShortW_Prj[Fp2[BN254_Nogami], G2]
  
  t0.pow_BN254_Nogami_u(P)  # [u]P
  t1.pow_BN254_Nogami_u(t0) # [u²]P
  t0.double(t1)             # [2u²]P
  t0 += t1                  # [3u²]P
  t0.double()               # [6u²]P
  
  t1.frobenius_psi(P)       # ψ(P)

  return t0 == t1