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
  ../elliptic/[ec_shortweierstrass_projective, ec_scalar_mul]

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
  ## P -> (x^2 - x - 1) P + (x - 1) psi(P) + psi(psi(2P))

# https://tools.ietf.org/html/draft-irtf-cfrg-hash-to-curve-09#section-8.8
const Cofactor_Eff_BLS12_381_G1 = BigInt[64].fromHex"0xd201000000010001"
  ## P -> (1 - x) P
const Cofactor_Eff_BLS12_381_G2 = BigInt[636].fromHex"0xbc69f08f2ee75b3584c6a0ea91b352888e2a8e9145ad7689986ff031508ffe1329c2f178731db956d82bf015d1212b02ec0ec69d7477c1ae954cbc06689f6a359894c0adebbf6b4e8020005aaa95551"
  ## P -> (x^2 - x - 1) P + (x - 1) psi(P) + psi(psi(2P))

func clearCofactorReference*(P: var ECP_ShortW_Prj[Fp[BN254_Nogami], NotOnTwist]) {.inline.} =
  ## Clear the cofactor of BN254_Nogami G1
  ## BN curve have a G1 cofactor of 1 so this is a no-op
  discard

func clearCofactorReference*(P: var ECP_ShortW_Prj[Fp2[BN254_Nogami], OnTwist]) {.inline.} =
  ## Clear the cofactor of BN254_Snarks G2
  # Endomorphism acceleration cannot be used if cofactor is not cleared
  P.scalarMulGeneric(Cofactor_Eff_BN254_Nogami_G2)

func clearCofactorReference*(P: var ECP_ShortW_Prj[Fp[BN254_Snarks], NotOnTwist]) {.inline.} =
  ## Clear the cofactor of BN254_Snarks G1
  ## BN curve have a G1 cofactor of 1 so this is a no-op
  discard

func clearCofactorReference*(P: var ECP_ShortW_Prj[Fp2[BN254_Snarks], OnTwist]) {.inline.} =
  ## Clear the cofactor of BN254_Snarks G2
  # Endomorphism acceleration cannot be used if cofactor is not cleared
  P.scalarMulGeneric(Cofactor_Eff_BN254_Snarks_G2)

func clearCofactorReference*(P: var ECP_ShortW_Prj[Fp[BLS12_377], NotOnTwist]) {.inline.} =
  ## Clear the cofactor of BLS12_377 G1
  P.scalarMulGeneric(Cofactor_Eff_BLS12_377_G1)

func clearCofactorReference*(P: var ECP_ShortW_Prj[Fp2[BLS12_377], OnTwist]) {.inline.} =
  ## Clear the cofactor of BLS12_377 G2
  # Endomorphism acceleration cannot be used if cofactor is not cleared
  P.scalarMulGeneric(Cofactor_Eff_BLS12_377_G2)

func clearCofactorReference*(P: var ECP_ShortW_Prj[Fp[BLS12_381], NotOnTwist]) {.inline.} =
  ## Clear the cofactor of BLS12_381 G1
  P.scalarMulGeneric(Cofactor_Eff_BLS12_381_G1)

func clearCofactorReference*(P: var ECP_ShortW_Prj[Fp2[BLS12_381], OnTwist]) {.inline.} =
  ## Clear the cofactor of BLS12_381 G2
  # Endomorphism acceleration cannot be used if cofactor is not cleared
  P.scalarMulGeneric(Cofactor_Eff_BLS12_381_G2)
