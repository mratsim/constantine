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

const Cofactor_Eff_BN254_Snarks_G1 = BigInt[1].fromHex"0x1"
const Cofactor_Eff_BN254_Snarks_G2 = BigInt[254].fromHex"0x30644e72e131a029b85045b68181585e06ceecda572a2489345f2299c0f9fa8d"
  ## G2.order // 

func clearCofactorReference*(P: var ECP_ShortW_Prj[Fp[BN254_Snarks], G1]) {.inline.} =
  ## Clear the cofactor of BN254_Snarks G1
  ## BN curves have a G1 cofactor of 1 so this is a no-op
  discard

func clearCofactorReference*(P: var ECP_ShortW_Prj[Fp2[BN254_Snarks], G2]) {.inline.} =
  ## Clear the cofactor of BN254_Snarks G2
  # Endomorphism acceleration cannot be used if cofactor is not cleared
  P.scalarMulGeneric(Cofactor_Eff_BN254_Snarks_G2)