# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

## ############################################################
##
##              Verkle Trie primitives for Ethereum
##
## ############################################################

import
  ./math/config/[type_ff, curves],
  ./math/arithmetic,
  ./math/elliptic/ec_twistededwards_projective,
  ./math/io/[io_bigints, io_fields],
  ./curves_primitives
  

func mapToBaseField*(p: ECP_TwEdwards_Prj[Fp[Banderwagon]]): Fp[Banderwagon] =
  var invY: Fp[Banderwagon]
  invY.inv(p.y)
  result.prod(p.x, invY)

func MapToScalarField*(res: var Fr[Banderwagon], p: ECP_TwEdwards_Prj[Fp[Banderwagon]]): bool {.discardable.} =
  var baseField: Fp[Banderwagon] = p.mapToBaseField()
  var baseFieldBytes: array[32, byte]

  let check1 = baseFieldBytes.marshalBE(baseField)
  let check2 = res.unmarshalBE(baseFieldBytes)

  return check1 and check2