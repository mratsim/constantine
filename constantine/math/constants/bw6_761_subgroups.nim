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
  ../io/io_bigints
  # ../isogenies/frobenius

# ############################################################
#
#                Clear Cofactor - Naive
#
# ############################################################

# TODO https://eprint.iacr.org/2020/351.pdf p12
const Cofactor_Eff_BW6_761_G1 = BigInt[384].fromHex"0xad1972339049ce762c77d5ac34cb12efc856a0853c9db94cc61c554757551c0c832ba4061000003b3de580000000007c"
  ## P -> 103([u³]P)− 83([u²]P)−40([u]P)+136P + φ(7([u²]P)+89([u]P)+130P)

# TODO https://eprint.iacr.org/2020/351.pdf p13
const Cofactor_Eff_BW6_761_G2 = BigInt[384].fromHex"0xad1972339049ce762c77d5ac34cb12efc856a0853c9db94cc61c554757551c0c832ba4061000003b3de580000000007c"
  ## P -> (103([u³]P) − 83([u²]P) − 143([u]P) + 27P) + ψ(7([u²]P) − 117([u]P) − 109P)

func clearCofactorReference*(P: var ECP_ShortW_Prj[Fp[BW6_761], G1]) {.inline.} =
  ## Clear the cofactor of BW6_761 G1
  P.scalarMulGeneric(Cofactor_Eff_BW6_761_G1)

func clearCofactorReference*(P: var ECP_ShortW_Prj[Fp[BW6_761], G2]) {.inline.} =
  ## Clear the cofactor of BW6_761 G2
  # Endomorphism acceleration cannot be used if cofactor is not cleared
  P.scalarMulGeneric(Cofactor_Eff_BW6_761_G2)
