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
  ../elliptic/ec_twistededwards_projective

func `==`*(P, Q: ECP_TwEdwards_Prj[Fp[Banderwagon]]): SecretBool =
  ## Equality check for points in the Banderwagon Group
  ## The equals method is different for the quotient group
  ## 
  ## Check for the (0,0) point, which is possible
  ## 
  ## This is a costly operation

  var lhs{.noInit.}, rhs{.noInit.}: typeof(P).F

  # Check for the zero points
  result = not(P.x.is_zero() and P.y.is_zero())
  result = result or not(Q.x.is_zero() and Q.y.is_zero())

  ## Check for the equality of the points
  ## X1 * Y2 == X2 * Y1
  lhs.prod(P.x, Q.y)
  rhs.prod(Q.x, P.y)
  result = result and lhs == rhs

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