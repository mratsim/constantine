# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  # Internals
  ../config/common,
  ../arithmetic,
  ../primitives,
  ../towers,
  ../config/curves,
  ../io/io_bigints,
  ../elliptic/[ec_shortweierstrass_projective, ec_scalar_mul],
  ../isogeny/frobenius

# ############################################################
#
#                Clear Cofactor - Naive
#
# ############################################################

const Cofactor_Eff_BN254_Nogami_G1 = BigInt[1].fromHex"0x1"
const Cofactor_Eff_BN254_Nogami_G2 = BigInt[254].fromHex"0x2523648240000001ba344d8000000008c2a2800000000016ad00000000000019"
  ## G2.order // r

const Cofactor_Eff_BN254_Snarks_G1 = BigInt[1].fromHex"0x1"
const Cofactor_Eff_BN254_Snarks_G2 = BigInt[254].fromHex"0x30644e72e131a029b85045b68181585e06ceecda572a2489345f2299c0f9fa8d"
  ## G2.order // r

# TODO effective cofactors as per H2C draft like BLS12-381 curve
const Cofactor_Eff_BLS12_377_G1 = BigInt[125].fromHex"0x170b5d44300000000000000000000000"
  ## P -> (1 - x) P
const Cofactor_Eff_BLS12_377_G2 = BigInt[502].fromHex"0x26ba558ae9562addd88d99a6f6a829fbb36b00e1dcc40c8c505634fae2e189d693e8c36676bd09a0f3622fba094800452217cc900000000000000000000001"
  ## P -> (x^2 - x - 1) P + (x - 1) ψ(P) + ψ(ψ(2P))

# https://tools.ietf.org/html/draft-irtf-cfrg-hash-to-curve-09#section-8.8
const Cofactor_Eff_BLS12_381_G1 = BigInt[64].fromHex"0xd201000000010001"
  ## P -> (1 - x) P
const Cofactor_Eff_BLS12_381_G2 = BigInt[636].fromHex"0xbc69f08f2ee75b3584c6a0ea91b352888e2a8e9145ad7689986ff031508ffe1329c2f178731db956d82bf015d1212b02ec0ec69d7477c1ae954cbc06689f6a359894c0adebbf6b4e8020005aaa95551"
  ## P -> (x^2 - x - 1) P + (x - 1) ψ(P) + ψ(ψ(2P))

# TODO https://eprint.iacr.org/2020/351.pdf p12
const Cofactor_Eff_BW6_761_G1 = BigInt[384].fromHex"0xad1972339049ce762c77d5ac34cb12efc856a0853c9db94cc61c554757551c0c832ba4061000003b3de580000000007c"
  ## P -> 103([u³]P)− 83([u²]P)−40([u]P)+136P + φ(7([u²]P)+89([u]P)+130P)

# TODO https://eprint.iacr.org/2020/351.pdf p13
const Cofactor_Eff_BW6_761_G2 = BigInt[384].fromHex"0xad1972339049ce762c77d5ac34cb12efc856a0853c9db94cc61c554757551c0c832ba4061000003b3de580000000007c"
  ## P -> (103([u³]P) − 83([u²]P) − 143([u]P) + 27P) + ψ(7([u²]P) − 117([u]P) − 109P)

func clearCofactorReference*(P: var ECP_ShortW_Prj[Fp[BN254_Nogami], G1]) {.inline.} =
  ## Clear the cofactor of BN254_Nogami G1
  ## BN curve have a G1 cofactor of 1 so this is a no-op
  discard

func clearCofactorReference*(P: var ECP_ShortW_Prj[Fp2[BN254_Nogami], G2]) {.inline.} =
  ## Clear the cofactor of BN254_Snarks G2
  # Endomorphism acceleration cannot be used if cofactor is not cleared
  P.scalarMulGeneric(Cofactor_Eff_BN254_Nogami_G2)

func clearCofactorReference*(P: var ECP_ShortW_Prj[Fp[BN254_Snarks], G1]) {.inline.} =
  ## Clear the cofactor of BN254_Snarks G1
  ## BN curve have a G1 cofactor of 1 so this is a no-op
  discard

func clearCofactorReference*(P: var ECP_ShortW_Prj[Fp2[BN254_Snarks], G2]) {.inline.} =
  ## Clear the cofactor of BN254_Snarks G2
  # Endomorphism acceleration cannot be used if cofactor is not cleared
  P.scalarMulGeneric(Cofactor_Eff_BN254_Snarks_G2)

func clearCofactorReference*(P: var ECP_ShortW_Prj[Fp[BLS12_377], G1]) {.inline.} =
  ## Clear the cofactor of BLS12_377 G1
  P.scalarMulGeneric(Cofactor_Eff_BLS12_377_G1)

func clearCofactorReference*(P: var ECP_ShortW_Prj[Fp2[BLS12_377], G2]) {.inline.} =
  ## Clear the cofactor of BLS12_377 G2
  # Endomorphism acceleration cannot be used if cofactor is not cleared
  P.scalarMulGeneric(Cofactor_Eff_BLS12_377_G2)

func clearCofactorReference*(P: var ECP_ShortW_Prj[Fp[BLS12_381], G1]) {.inline.} =
  ## Clear the cofactor of BLS12_381 G1
  P.scalarMulGeneric(Cofactor_Eff_BLS12_381_G1)

func clearCofactorReference*(P: var ECP_ShortW_Prj[Fp2[BLS12_381], G2]) {.inline.} =
  ## Clear the cofactor of BLS12_381 G2
  # Endomorphism acceleration cannot be used if cofactor is not cleared
  P.scalarMulGeneric(Cofactor_Eff_BLS12_381_G2)

func clearCofactorReference*(P: var ECP_ShortW_Prj[Fp[BW6_761], G1]) {.inline.} =
  ## Clear the cofactor of BW6_761 G1
  P.scalarMulGeneric(Cofactor_Eff_BW6_761_G1)

func clearCofactorReference*(P: var ECP_ShortW_Prj[Fp[BW6_761], G2]) {.inline.} =
  ## Clear the cofactor of BW6_761 G2
  # Endomorphism acceleration cannot be used if cofactor is not cleared
  P.scalarMulGeneric(Cofactor_Eff_BW6_761_G2)

# ############################################################
#
#                Clear Cofactor - Optimized
#
# ############################################################

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
# - Wahby et al "Fast and simple constant-time hashing to the BLS12-381 elliptic curve", https://eprint.iacr.org/2019/403
# - IETF "Hashing to Elliptic Curves", https://datatracker.ietf.org/doc/html/draft-irtf-cfrg-hash-to-curve-11#appendix-G.4
#
# In summary, the elliptic curve point multiplication is very expensive,
# the fast methods uses endomorphism acceleration instead.
#
# The method described in Wahby et al is implemented by Riad Wahby
# in C at: https://github.com/kwantam/bls12-381_hash/blob/23c1930039f58606138459557677668fabc8ce39/src/curve2/ops2.c#L106-L204
# following Budroni et al, "Efficient hash maps to G2 on BLS curves"
# https://eprint.iacr.org/2017/419
#
# "P -> [x² - x - 1] P + [x - 1] ψ(P) + ψ(ψ([2]P))"
#
# with Psi (ψ) - untwist-Frobenius-Twist function
# and x the curve BLS parameter

func double_repeated*[EC](P: var EC, num: int) {.inline.} =
  ## Repeated doublings
  for _ in 0 ..< num:
    P.double()

func pow_x(
       r{.noalias.}: var ECP_ShortW_Prj[Fp2[BLS12_381], G2],
       P{.noalias.}: ECP_ShortW_Prj[Fp2[BLS12_381], G2],
     ) =
  ## Does the scalar multiplication [x]P
  ## with x the BLS12 curve parameter
  ## For BLS12_381 [-0xd201000000010000]P
  ## Requires r and P to not alias

  # In binary
  # 0b11
  r.double(P)
  r += P
  # 0b1101
  r.double_repeated(2)
  r += P
  # 0b1101001
  r.double_repeated(3)
  r += P
  # 0b1101001000000001
  r.double_repeated(9)
  r += P
  # 0b110100100000000100000000000000000000000000000001
  r.double_repeated(32)
  r += P
  # 0b1101001000000001000000000000000000000000000000010000000000000000
  r.double_repeated(16)

  # Negative, x = -0xd201000000010000
  r.neg(r)


func clearCofactorFast*(P: var ECP_ShortW_Prj[Fp2[BLS12_381], G2]) =
  ## Clear the cofactor of BLS12_381 G2
  ## Optimized using endomorphisms
  ## P -> [x²-x-1]P + [x-1] ψ(P) + ψ²([2]P)

  var xP{.noInit.}, x2P{.noInit.}: typeof(P)

  xP.pow_x(P)             # 1. xP = [x]P
  x2P.pow_x(xP)           # 2. x2P = [x²]P

  x2P.diff(x2P, xP)       # 3. x2P = [x²-x]P
  x2P.diff(x2P, P)        # 4. x2P = [x²-x-1]P

  xP.diff(xP, P)          # 5. xP = [x-1]P
  xP.frobenius_psi(xP)    # 6. xP = ψ([x-1]P) = [x-1] ψ(P)

  P.double(P)             # 7. P = [2]P
  P.frobenius_psi(P, k=2) # 8. P = ψ²([2]P)

  P.sum(P, x2P)           # 9. P = [x²-x-1]P + ψ²([2]P)
  P.sum(P, xP)            # 10. P = [x²-x-1]P + [x-1] ψ(P) + ψ²([2]P)
