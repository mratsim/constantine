# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  std/typetraits,
  ../primitives,
  ../config/curves,
  ../arithmetic,
  ../towers,
  ../elliptic/ec_shortweierstrass_affine,
  ../io/io_towers

type
  Line*[F; twist: static SexticTwist] = object
    ## Packed line representation over a E'(Fp^k/d)
    ## with k the embedding degree and d the twist degree
    ## i.e. for a curve with embedding degree 12 and sextic twist
    ## F is Fp2
    ##
    ## Assuming a Sextic Twist
    ##
    ## Out of 6 Fp2 coordinates, 3 are 0 and
    ## the non-zero coordinates depend on the twist kind.
    ##
    ## For a D-twist,
    ##   (x, y, z) corresponds to an sparse element of Fp12
    ##   with Fp2 coordinates: xy00z0
    ## For a M-Twist
    ##   (x, y, z) corresponds to an sparse element of Fp12
    ##   with Fp2 coordinates: xyz000
    x*, y*, z*: F

func toHex*(line: Line, order: static Endianness = bigEndian): string =
  result = static($line.typeof.genericHead() & '(')
  for fieldName, fieldValue in fieldPairs(line):
    when fieldName != "x":
      result.add ", "
    result.add fieldName & ": "
    result.appendHex(fieldValue, order)
  result.add ")"

# Line evaluation
# --------------------------------------------------

func line_update*(line: var Line, P: ECP_ShortW_Aff) =
  ## Update the line evaluation with P
  ## after addition or doubling
  ## P in G1
  line.x *= P.y
  line.z *= P.x
