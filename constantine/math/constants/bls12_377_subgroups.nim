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
  ../isogenies/frobenius,
  ../constants/zoo_endomorphisms

func pow_bls12_377_abs_x[ECP: ECP_ShortW[Fp[BLS12_377], G1] or
       ECP_ShortW[Fp2[BLS12_377], G2]](
       r{.noalias.}: var ECP,
       P{.noalias.}: ECP
     ) =
  ## Does the scalar multiplication [x]P
  ## with x the absolute value of the BLS12 curve parameter
  ## For BLS12_377 [0x8508c00000000001]P
  ## Requires r and P to not alias
  r.double(P)
  r += P
  r.double()
  r += P
  let t111 = r

  r.double_repeated(2)
  let t111000 = r

  r += t111
  let t100011 = r

  r.double()
  r += t100011
  r += t111000

  r.double_repeated(10)
  r += t100011

  r.double_repeated(46)
  r += P

func pow_bls12_377_x[ECP: ECP_ShortW[Fp[BLS12_377], G1] or
       ECP_ShortW[Fp2[BLS12_377], G2]](
       r{.noalias.}: var ECP,
       P{.noalias.}: ECP
     ) {.inline.}=
  ## Does the scalar multiplication [x]P
  ## with x the BLS12 curve parameter
  ## For BLS12_377 [0x8508c00000000001]P
  ## Requires r and P to not alias
  pow_bls12_377_abs_x(r, P)

func pow_bls12_377_minus_x[ECP: ECP_ShortW[Fp[BLS12_377], G1] or
       ECP_ShortW[Fp2[BLS12_377], G2]](
       r{.noalias.}: var ECP,
       P{.noalias.}: ECP
     ) {.inline.}=
  ## Does the scalar multiplication [-x]P
  ## with x the BLS12 curve parameter
  ## For BLS12_377 [-0x8508c00000000001]P
  ## Requires r and P to not alias
  pow_bls12_377_abs_x(r, P)
  r.neg()

# ############################################################
#
#                Clear Cofactor - Naive
#
# ############################################################

const Cofactor_Eff_BLS12_377_G1 = BigInt[64].fromHex"0x8508c00000000000"
  ## P -> (1 - x) P
const Cofactor_Eff_BLS12_377_G2 = BigInt[629].fromHex"0x1f60243677e30653648d3d9502abfba951764c46f4edd28f6ade35a5c7d769f7ee7c4b03103b45b85860aaaad2927678ba2796373885598e8e73ad8a538800cf664765b00000031e34800000000000"
  ## P -> (x^2 - x - 1) P + (x - 1) ψ(P) + ψ(ψ(2P))
  ##
  ## Effective cofactor from Budroni et al https://eprint.iacr.org/2017/419.pdf
  ## (3x² − 3)*cofactor

func clearCofactorReference*(P: var ECP_ShortW_Prj[Fp[BLS12_377], G1]) {.inline.} =
  ## Clear the cofactor of BLS12_377 G1
  # Endomorphism acceleration cannot be used if cofactor is not cleared
  P.scalarMulGeneric(Cofactor_Eff_BLS12_377_G1)
  P.neg()

func clearCofactorReference*(P: var ECP_ShortW_Prj[Fp2[BLS12_377], G2]) {.inline.} =
  ## Clear the cofactor of BLS12_377 G2
  # Endomorphism acceleration cannot be used if cofactor is not cleared
  P.scalarMulGeneric(Cofactor_Eff_BLS12_377_G2)

# ############################################################
#
#                Clear Cofactor - Optimized
#
# ############################################################

# BLS12 G1
# ------------------------------------------------------------

func clearCofactorFast*(P: var ECP_ShortW[Fp[BLS12_377], G1]) =
  ## Clear the cofactor of BLS12_377 G1
  ##
  ## Wahby et al "Fast and simple constant-time hashing to the BLS12-377 elliptic curve", https://eprint.iacr.org/2019/403
  ## Optimized using endomorphisms
  ## P -> (1 - x) P
  var t{.noInit.}: typeof(P)
  t.pow_bls12_377_minus_x(P) # [-x]P
  P += t                     # [1-x]P

# BLS12 G2
# ------------------------------------------------------------
# From any point on the elliptic curve E2 of a BLS12 curve
# Obtain a point in the G2 prime-order subgroup
#
# Described in https://datatracker.ietf.org/doc/html/draft-irtf-cfrg-hash-to-curve-11#appendix-G.4
#
# Implementations, multiple implementations are possible in increasing order of speed:
#
# - The default, canonical, implementation is h_eff * P
# - Scott et al, "Fast Hashing to G2 on Pairing-Friendly Curves", https://doi.org/10.1007/978-3-642-03298-1_8
# - Fuentes-Castaneda et al, "Fast Hashing to G2 on Pairing-Friendly Curves", https://doi.org/10.1007/978-3-642-28496-0_25
# - Budroni et al, "Hashing to G2 on BLS pairing-friendly curves", https://doi.org/10.1145/3313880.3313884
# - Wahby et al "Fast and simple constant-time hashing to the BLS12-377 elliptic curve", https://eprint.iacr.org/2019/403
# - IETF "Hashing to Elliptic Curves", https://datatracker.ietf.org/doc/html/draft-irtf-cfrg-hash-to-curve-11#appendix-G.4
#
# In summary, the elliptic curve point multiplication is very expensive,
# the fast methods uses endomorphism acceleration instead.
#
# The method described in Wahby et al is implemented by Riad Wahby
# in C at: https://github.com/kwantam/bls12-377_hash/blob/23c1930039f58606138459557677668fabc8ce39/src/curve2/ops2.c#L106-L204
# following Budroni et al, "Efficient hash maps to G2 on BLS curves"
# https://eprint.iacr.org/2017/419
#
# "P -> [x² - x - 1] P + [x - 1] ψ(P) + ψ(ψ([2]P))"
#
# with Psi (ψ) - untwist-Frobenius-Twist function
# and x the curve BLS parameter

func clearCofactorFast*(P: var ECP_ShortW[Fp2[BLS12_377], G2]) =
  ## Clear the cofactor of BLS12_377 G2
  ## Optimized using endomorphisms
  ## P -> [x²-x-1]P + [x-1] ψ(P) + ψ²([2]P)

  var xP{.noInit.}, x2P{.noInit.}: typeof(P)

  xP.pow_bls12_377_x(P)   # 1. xP = [x]P
  x2P.pow_bls12_377_x(xP) # 2. x2P = [x²]P

  x2P.diff(x2P, xP)       # 3. x2P = [x²-x]P
  x2P.diff(x2P, P)        # 4. x2P = [x²-x-1]P

  xP.diff(xP, P)          # 5. xP = [x-1]P
  xP.frobenius_psi(xP)    # 6. xP = ψ([x-1]P) = [x-1] ψ(P)

  P.double(P)             # 7. P = [2]P
  P.frobenius_psi(P, k=2) # 8. P = ψ²([2]P)

  P.sum(P, x2P)           # 9. P = [x²-x-1]P + ψ²([2]P)
  P.sum(P, xP)            # 10. P = [x²-x-1]P + [x-1] ψ(P) + ψ²([2]P)

# ############################################################
#
#                Subgroup checks
#
# ############################################################

func isInSubgroup*(P: ECP_ShortW[Fp[BLS12_377], G1]): SecretBool =
  ## Returns true if P is in G1 subgroup, i.e. P is a point of order r.
  ## A point may be on a curve but not on the prime order r subgroup.
  ## Not checking subgroup exposes a protocol to small subgroup attacks.
  ##
  ## Warning ⚠: Assumes that P is on curve
  # Implementation: Scott, https://eprint.iacr.org/2021/1130.pdf
  #   A note on group membership tests for G1, G2 and GT
  #   on BLS pairing-friendly curves
  #   P is in the G1 subgroup iff ϕ(P) == [-u²](P)
  var t0{.noInit.}, t1{.noInit.}: typeof(P)

  # [-u²]P
  t0.pow_bls12_377_x(P)
  t1.pow_bls12_377_minus_x(t0)

  # ϕ(P)
  t0.x.prod(P.x, BLS12_377.getCubicRootOfUnity_mod_p())
  t0.y = P.y
  t0.z = P.z

  return t0 == t1

func isInSubgroup*(P: ECP_ShortW[Fp2[BLS12_377], G2]): SecretBool =
  ## Returns true if P is in G2 subgroup, i.e. P is a point of order r.
  ## A point may be on a curve but not on the prime order r subgroup.
  ## Not checking subgroup exposes a protocol to small subgroup attacks.
  ##
  ## Warning ⚠: Assumes that P is on curve
  # Implementation: Scott, https://eprint.iacr.org/2021/1130.pdf
  #   A note on group membership tests for G1, G2 and GT
  #   on BLS pairing-friendly curves
  #   P is in the G1 subgroup iff ψ(P) == [u](P)
  var t0{.noInit.}, t1{.noInit.}: typeof(P)
  t0.pow_bls12_377_x(P) # [u]P
  t1.frobenius_psi(P)   # ψ(P)

  return t0 == t1

func isInSubgroup*(P: ECP_ShortW_Aff[Fp[BLS12_377], G1]): SecretBool =
  ## Returns true if P is in 𝔾1 subgroup, i.e. P is a point of order r.
  ## A point may be on a curve but not on the prime order r subgroup.
  ## Not checking subgroup exposes a protocol to small subgroup attacks.
  ##
  ## Warning ⚠: Assumes that P is on curve
  var t{.noInit.}: ECP_ShortW_Prj[Fp[BLS12_377], G1]
  t.fromAffine(P)
  return t.isInSubgroup()


func isInSubgroup*(P: ECP_ShortW_Aff[Fp2[BLS12_377], G2]): SecretBool =
  ## Returns true if P is in 𝔾2 subgroup, i.e. P is a point of order r.
  ## A point may be on a curve but not on the prime order r subgroup.
  ## Not checking subgroup exposes a protocol to small subgroup attacks.
  ##
  ## Warning ⚠: Assumes that P is on curve
  var t{.noInit.}: ECP_ShortW_Jac[Fp2[BLS12_377], G2]
  t.fromAffine(P)
  return t.isInSubgroup()