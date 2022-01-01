# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  # Internals
  ../config/[common, curves],
  ../arithmetic,
  ../primitives,
  ../towers,
  ../ec_shortweierstrass,
  ../io/io_bigints,
  ../isogeny/frobenius

# ############################################################
#
#                Clear Cofactor - Naive
#
# ############################################################

const Cofactor_Eff_BLS12_377_G1 = BigInt[125].fromHex"0x170b5d44300000000000000000000000"
  ## P -> (1 - x) P
const Cofactor_Eff_BLS12_377_G2 = BigInt[502].fromHex"0x26ba558ae9562addd88d99a6f6a829fbb36b00e1dcc40c8c505634fae2e189d693e8c36676bd09a0f3622fba094800452217cc900000000000000000000001"
  ## P -> (x^2 - x - 1) P + (x - 1) ψ(P) + ψ(ψ(2P))

func clearCofactorReference*(P: var ECP_ShortW_Prj[Fp[BLS12_377], G1]) {.inline.} =
  ## Clear the cofactor of BLS12_377 G1
  # Endomorphism acceleration cannot be used if cofactor is not cleared
  P.scalarMulGeneric(Cofactor_Eff_BLS12_377_G1)

func clearCofactorReference*(P: var ECP_ShortW_Prj[Fp2[BLS12_377], G2]) {.inline.} =
  ## Clear the cofactor of BLS12_377 G2
  # Endomorphism acceleration cannot be used if cofactor is not cleared
  P.scalarMulGeneric(Cofactor_Eff_BLS12_377_G2)
