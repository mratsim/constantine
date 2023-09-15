# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  ../../platforms/abstractions,
  ../config/curves,
  ../arithmetic,
  ../extension_fields,
  ../elliptic/ec_twistededwards_projective

# ############################################################
#
#                Subgroup Check
#
# ############################################################

func isInSubGroup*(P: ECP_TwEdwards_Prj[Fp[Banderwagon]]): SecretBool =
  ## Checks if the point is in the quotient subgroup
  ## The group law does not change because what we quotiented by was a subgroup. 
  ## These are still points on the bandersnatch curve and form a group under point addition.
  ## 
  ## This is to be used to check if the point lies in the Banderwagon
  ## while importing a point from serialized bytes

  var res{.noInit.}: typeof(P).F
  var one{.noInit.}: typeof(P).F

  one.setOne()
  res.setZero()

  ## Compute 1 - aX^2 and check its legendre symbol
  res.prod(P.x, P.x)
  res.prod(res, Banderwagon.getCoefA())
  res.neg(res)
  res.sum(res, one)

  return res.isSquare()