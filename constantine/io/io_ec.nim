# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  ./io_bigints, ./io_fields, ./io_towers,
  ../arithmetic,
  ../towers,
  ../elliptic/[
    ec_shortweierstrass_affine,
    ec_shortweierstrass_projective,
    ec_shortweierstrass_jacobian
  ]

# No exceptions allowed
{.push raises: [].}
{.push inline.}

# ############################################################
#
#   Parsing from canonical inputs to internal representation
#
# ############################################################

func toHex*[EC](P: EC): string =
  ## Stringify an elliptic curve point to Hex
  ## Note. Leading zeros are not removed.
  ## Result is prefixed with 0x
  ##
  ## Output will be padded with 0s to maintain constant-time.
  ##
  ## CT:
  ##   - no leaks
  ##
  ## This proc output may change format in the future

  var aff {.noInit.}: ECP_ShortW_Aff[EC.F, EC.Tw]
  when EC is ECP_ShortW_Proj:
    aff.affineFromProjective(P)
  elif EC is ECP_ShortW_Jac:
    aff.affineFromJacobian(P)
  else:
    aff = P

  result = "ECP[" & $aff.F & "](\n  x: "
  result.appendHex(aff.x, bigEndian)
  result &= ",\n  y: "
  result.appendHex(aff.y, bigEndian)
  result &= "\n)"

func fromHex*(dst: var (ECP_ShortW_Proj or ECP_ShortW_Jac), x, y: string): bool {.raises: [ValueError].}=
  ## Convert hex strings to a G1 curve point
  ## Returns `false`
  ## if there is no point with coordinates (`x`, `y`) on the curve
  ## In that case, `dst` content is undefined.
  static: doAssert dst.F is Fp, "dst must be on G1, an elliptic curve over 𝔽p"
  dst.x.fromHex(x)
  dst.y.fromHex(y)
  dst.z.setOne()
  return bool(isOnCurve(dst.x, dst.y, dst.Tw))

func fromHex*(dst: var (ECP_ShortW_Proj or ECP_ShortW_Jac), x0, x1, y0, y1: string): bool {.raises: [ValueError].}=
  ## Convert hex strings to a G2 curve point
  ## Returns `false`
  ## if there is no point with coordinates (`x`, `y`) on the curve
  ## In that case, `dst` content is undefined.
  static: doAssert dst.F is Fp2, "dst must be on G2, an elliptic curve over 𝔽p2"
  dst.x.fromHex(x0, x1)
  dst.y.fromHex(y0, y1)
  dst.z.setOne()
  return bool(isOnCurve(dst.x, dst.y, dst.Tw))

func fromHex*(dst: var ECP_ShortW_Aff, x, y: string): bool {.raises: [ValueError].}=
  ## Convert hex strings to a G1 curve point
  ## Returns `false`
  ## if there is no point with coordinates (`x`, `y`) on the curve
  ## In that case, `dst` content is undefined.
  static: doAssert dst.F is Fp, "dst must be on G1, an elliptic curve over 𝔽p"
  dst.x.fromHex(x)
  dst.y.fromHex(y)
  return bool(isOnCurve(dst.x, dst.y, dst.Tw))

func fromHex*(dst: var ECP_ShortW_Aff, x0, x1, y0, y1: string): bool {.raises: [ValueError].}=
  ## Convert hex strings to a G2 curve point
  ## Returns `false`
  ## if there is no point with coordinates (`x`, `y`) on the curve
  ## In that case, `dst` content is undefined.
  static: doAssert dst.F is Fp2, "dst must be on G2, an elliptic curve over 𝔽p2"
  dst.x.fromHex(x0, x1)
  dst.y.fromHex(y0, y1)
  return bool(isOnCurve(dst.x, dst.y, dst.Tw))
