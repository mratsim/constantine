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

func clearCofactorReference*(P: var ECP_ShortW[Fp[Vesta], G1]) {.inline.} =
  ## Clear the cofactor of Vesta G1
  ## The Pasta curves have a prime-order group so this is a no-op
  discard

# ############################################################
#
#                Subgroup checks
#
# ############################################################

func isInSubgroup*(P: ECP_ShortW[Fp[Vesta], G1]): SecretBool {.inline.} =
  ## Returns true if P is in G1 subgroup, i.e. P is a point of order r.
  ## A point may be on a curve but not on the prime order r subgroup.
  ## Not checking subgroup exposes a protocol to small subgroup attacks.
  ## This is a no-op as on G1, all points are in the correct subgroup.
  ##
  ## Warning ⚠: Assumes that P is on curve
  return CtTrue
