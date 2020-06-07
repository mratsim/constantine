# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  ./io_bigints, ./io_fields,
  ../config/curves,
  ../elliptic/[
    ec_weierstrass_affine,
    ec_weierstrass_projective
  ]

# No exceptions allowed
{.push raises: [].}
{.push inline.}

# ############################################################
#
#   Parsing from canonical inputs to internal representation
#
# ############################################################

func toHex*(P: ECP_SWei_Proj): string =
  ## Stringify an elliptic curve point to Hex
  ## Note. Leading zeros are not removed.
  ## Result is prefixed with 0x
  ##
  ## Output will be padded with 0s to maintain constant-time.
  ##
  ## CT:
  ##   - no leaks
  ##
  ## TODO: only normalize and don't display the Z coordinate
  ##
  ## This proc output may change format in the future
  result = $P.F.C & "(x: "
  result &= P.x.tohex(bigEndian)
  result &= ", y: "
  result &= P.y.tohex(bigEndian)
  result &= ", z: "
  result &= P.y.tohex(bigEndian)
  result &= ')'

func fromHex*(dst: var ECP_SWei_Proj, x, y: string): bool {.raises: [ValueError].}=
  ## Convert hex strings to a curve point
  ## Returns `false`
  ## if there is no point with coordinates (`x`, `y`) on the curve
  ## In that case, `dst` content is undefined.
  dst.x.fromHex(x)
  dst.y.fromHex(y)
  dst.z.setOne()
  return bool(isOnCurve(dst.x, dst.y))
