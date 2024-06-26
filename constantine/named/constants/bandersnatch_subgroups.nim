# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  # Internals
  constantine/named/algebras,
  constantine/math/arithmetic,
  constantine/math/elliptic/ec_twistededwards_projective

# ############################################################
#
#                Clear Cofactor
#
# ############################################################

func clearCofactorReference*(P: var EC_TwEdw_Prj[Fp[Bandersnatch]]) {.inline.} =
  ## Clear the cofactor of Bandersnatch
  # https://hackmd.io/@6iQDuIePQjyYBqDChYw_jg/BJBNcv9fq#Bandersnatch-Subgroup
  #
  # Bandersnatch Subgroup

  # The group structure of bandersnatch is ℤ₂ x ℤ₂ x p, where p is a prime
  #
  # The non-cyclic subgroup which we may refer to as the 2 torsion subgroup is:
  #   E[2] = {(0, 1), D₀, D₁, D₂}
  #
  # Remark: All of these points have order 2 or 1, so it is sufficient to double any point in the bandersnatch group to clear the cofactor. ie one does not need to multiply by the cofactor; 4.
  # Remark: We may also refer to the 2 torsion subgroup as the small order subgroup.
  P.double()
