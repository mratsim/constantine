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

func pow_bn254_snarks_abs_u*[ECP: ECP_ShortW[Fp[BN254_Snarks], G1] or
       ECP_ShortW[Fp2[BN254_Snarks], G2]](
       r{.noalias.}: var ECP,
       P{.noalias.}: ECP
     ) =
  ## [u]P with u the curve parameter
  ## For BN254_Snarks [0x44e992b44a6909f1]P

  var # Hopefully the compiler optimizes away unused ECP as those are large
    x10       {.noInit.}: ECP
    x11       {.noInit.}: ECP
    x100      {.noInit.}: ECP
    x110      {.noInit.}: ECP
    x1100     {.noInit.}: ECP
    x1111     {.noInit.}: ECP
    x10010    {.noInit.}: ECP
    x10110    {.noInit.}: ECP
    x11100    {.noInit.}: ECP
    x101110   {.noInit.}: ECP
    x1001010  {.noInit.}: ECP
    x1111000  {.noInit.}: ECP
    x10001110 {.noInit.}: ECP

  x10       .double(P)
  x11       .sum(x10, P)
  x100      .sum(x11, P)
  x110      .sum(x10, x100)
  x1100     .double(x110)
  x1111     .sum(x11, x1100)
  x10010    .sum(x11, x1111)
  x10110    .sum(x100, x10010)
  x11100    .sum(x110, x10110)
  x101110   .sum(x10010, x11100)
  x1001010  .sum(x11100, x101110)
  x1111000  .sum(x101110, x1001010)
  x10001110 .sum(x10110, x1111000)

  var
    r15 {.noInit.}: ECP
    r16 {.noInit.}: ECP
    r17 {.noInit.}: ECP
    r18 {.noInit.}: ECP
    r20 {.noInit.}: ECP
    r21 {.noInit.}: ECP
    r22 {.noInit.}: ECP
    r26 {.noInit.}: ECP
    r27 {.noInit.}: ECP
    r61 {.noInit.}: ECP

  r15.double(x10001110)
  r15 += x1001010
  r16.sum(x10001110, r15)
  r17.sum(x1111, r16)
  r18.sum(r16, r17)

  r20.double(r18)
  r20 += r17
  r21.sum(x1111000, r20)
  r22.sum(r15, r21)

  r26.double(r22)
  r26.double()
  r26 += r22
  r26 += r18

  r27.sum(r22, r26)

  r61.sum(r26, r27)
  r61.double_repeated(17)
  r61 += r27
  r61.double_repeated(14)
  r61 += r21

  r = r61
  r.double_repeated(16)
  r += r20

func pow_bn254_snarks_u[ECP: ECP_ShortW[Fp[BN254_Snarks], G1] or
       ECP_ShortW[Fp2[BN254_Snarks], G2]](
       r{.noalias.}: var ECP,
       P{.noalias.}: ECP
     ) {.inline.}=
  ## Does the scalar multiplication [u]P
  ## with u the BN curve parameter
  pow_bn254_snarks_abs_u(r, P)

func pow_bn254_snarks_minus_u[ECP: ECP_ShortW[Fp[BN254_Snarks], G1] or
       ECP_ShortW[Fp2[BN254_Snarks], G2]](
       r{.noalias.}: var ECP,
       P{.noalias.}: ECP
     ) {.inline, used.}=
  ## Does the scalar multiplication [-u]P
  ## with  the BN curve parameter
  pow_bn254_snarks_abs_u(r, P)
  r.neg()

# ############################################################
#
#                Clear Cofactor - Naive
#
# ############################################################

const Cofactor_Eff_BN254_Snarks_G2 = BigInt[445].fromHex"0x10fdac342d9d118eaade453b741519b8e1d63b3400132e99468a9c2b25de5b5f1bf35b43bcc5da2335a0d8a112d43476616edcfabef338ea"
  # r = 36x⁴ + 36x³ + 18x² + 6x + 1
  # G2.order() = (36x⁴ + 36x³ + 18x² + 6x + 1)(36x⁴ + 36x³ + 30x² + 6x + 1)
  #            = r * cofactor
  # Effective cofactor from Fuentes-Casteneda et al
  # -(18x³ + 12x² + 3x + 1)*cofactor

func clearCofactorReference*(P: var ECP_ShortW_Prj[Fp[BN254_Snarks], G1]) {.inline.} =
  ## Clear the cofactor of BN254_Snarks G1
  ## BN curves have a G1 cofactor of 1 so this is a no-op
  discard

func clearCofactorReference*(P: var ECP_ShortW_Prj[Fp2[BN254_Snarks], G2]) {.inline.} =
  ## Clear the cofactor of BN254_Snarks G2
  # Endomorphism acceleration cannot be used if cofactor is not cleared
  P.scalarMulGeneric(Cofactor_Eff_BN254_Snarks_G2)
  P.neg()

# ############################################################
#
#                Clear Cofactor - Naive
#
# ############################################################

# BN G1
# ------------------------------------------------------------

func clearCofactorFast*(P: var ECP_ShortW[Fp[BN254_Snarks], G1]) {.inline.} =
  ## Clear the cofactor of BN254_Snarks G1
  ## BN curves have a prime order r hence all points on curve are in G1
  ## Hence this is a no-op
  discard

# BN G2
# ------------------------------------------------------------
#
# Implementation 
# Fuentes-Castaneda et al, "Fast Hashing to G2 on Pairing-Friendly Curves", https://doi.org/10.1007/978-3-642-28496-0_25*

func clearCofactorFast*(P: var ECP_ShortW[Fp2[BN254_Snarks], G2]) {.inline.} =
  ## Clear the cofactor of BN254_Snarks G2
  ## Optimized using endomorphisms
  ## P' → [x]P + [3x]ψ(P) + [x]ψ²(P) + ψ³(P)
  var xP{.noInit.}, t{.noInit.}: typeof(P)

  xP.pow_bn254_snarks_u(P) # xP = [x]P
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

func isInSubgroup*(P: ECP_ShortW[Fp[BN254_Snarks], G1]): SecretBool {.inline.} =
  ## Returns true if P is in G1 subgroup, i.e. P is a point of order r.
  ## A point may be on a curve but not on the prime order r subgroup.
  ## Not checking subgroup exposes a protocol to small subgroup attacks.
  ## This is a no-op as on G1, all points are in the correct subgroup.
  ## 
  ## Warning ⚠: Assumes that P is on curve
  return CtTrue

func isInSubgroup*(P: ECP_ShortW_Jac[Fp2[BN254_Snarks], G2] or ECP_ShortW_Prj[Fp2[BN254_Snarks], G2]): SecretBool =
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
  var t0{.noInit.}, t1{.noInit.}: typeof(P)
  
  t0.pow_bn254_snarks_u(P)  # [u]P
  t1.pow_bn254_snarks_u(t0) # [u²]P
  t0.double(t1)             # [2u²]P
  t0 += t1                  # [3u²]P
  t0.double()               # [6u²]P
  
  t1.frobenius_psi(P)       # ψ(P)

  return t0 == t1

func isInSubgroup*(P: ECP_ShortW_Aff[Fp2[BN254_Snarks], G2]): SecretBool =
  ## Returns true if P is in 𝔾2 subgroup, i.e. P is a point of order r.
  ## A point may be on a curve but not on the prime order r subgroup.
  ## Not checking subgroup exposes a protocol to small subgroup attacks.
  ## 
  ## Warning ⚠: Assumes that P is on curve
  var t{.noInit.}: ECP_ShortW_Jac[Fp2[BN254_Snarks], G2]
  t.fromAffine(P)
  return t.isInSubgroup()