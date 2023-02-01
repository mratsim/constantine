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
  ../ec_shortweierstrass

# ############################################################
#
#                Clear Cofactor - Naive
#
# ############################################################

func clearCofactorReference*(P: var ECP_ShortW[Fp[Secp256k1], G1]) {.inline.} =
  ## Clear the cofactor of Secp256k1
  ## The secp256k1 curve has a prime-order group so this is a no-op
  discard

# ############################################################
#
#                Subgroup checks
#
# ############################################################

func isInSubgroup*(P: ECP_ShortW[Fp[Secp256k1], G1]): SecretBool {.inline.} =
  ## This is a no-op, all points on curve are in the correct subgroup.
  ##
  ## Warning ⚠: Assumes that P is on curve
  return CtTrue
