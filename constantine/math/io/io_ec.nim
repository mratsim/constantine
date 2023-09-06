# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  ../../platforms/primitives,
  ./io_bigints, ./io_fields, ./io_extfields,
  ../arithmetic,
  ../extension_fields,
  ../elliptic/[
    ec_shortweierstrass_affine,
    ec_shortweierstrass_projective,
    ec_shortweierstrass_jacobian,
    ec_shortweierstrass_jacobian_extended,
    ec_twistededwards_projective,
    ec_twistededwards_affine
  ]

# No exceptions allowed
{.push raises: [].}
{.push inline.}

# ############################################################
#
#   Parsing from canonical inputs to internal representation
#
# ############################################################

func toHex*[EC: ECP_ShortW_Prj or ECP_ShortW_Jac or ECP_ShortW_Aff or ECP_ShortW_JacExt](P: EC, indent: static int = 0): string =
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

  var aff {.noInit.}: ECP_ShortW_Aff[EC.F, EC.G]
  when EC isnot ECP_ShortW_Aff:
    aff.affine(P)
  else:
    aff = P

  const sp = spaces(indent)

  result = sp & $EC & "(\n" & sp & "  x: "
  result.appendHex(aff.x)
  result &= ",\n" & sp & "  y: "
  result.appendHex(aff.y)
  result &= "\n" & sp & ")"

func toHex*[EC: ECP_TwEdwards_Aff or ECP_TwEdwards_Prj](P: EC, indent: static int = 0): string =
  ## Stringify an elliptic curve point to Hex for Twisted Edwards Curve
  ## Note. Leading zeros are not removed.
  ## Result is prefixed with 0x
  ##
  ## Output will be padded with 0s to maintain constant-time.
  ##
  ## CT:
  ##   - no leaks
  ##
  ## This proc output may change format in the future

  var aff {.noInit.}: ECP_TwEdwards_Aff[EC.F]
  when EC isnot ECP_TwEdwards_Aff:
    aff.affine(P)
  else:
    aff = P

  const sp = spaces(indent)

  result = sp & $EC & "(\n" & sp & "  x: "
  result.appendHex(aff.x)
  result &= ",\n" & sp & "  y: "
  result.appendHex(aff.y)
  result &= "\n" & sp & ")"

func fromHex*(dst: var (ECP_ShortW_Prj or ECP_ShortW_Jac), x, y: string): bool =
  ## Convert hex strings to a G1 curve point
  ## Returns true if point exist or if input is the point at infinity (all 0)
  ## Returns `false` if there is no point with coordinates (`x`, `y`) on the curve
  ## In that case, `dst` content is undefined.
  static: doAssert dst.F is Fp, "dst must be on G1, an elliptic curve over 𝔽p"
  dst.x.fromHex(x)
  dst.y.fromHex(y)
  dst.z.setOne()
  let isInf = dst.x.isZero() and dst.y.isZero()
  dst.z.csetZero(isInf)
  return bool(isOnCurve(dst.x, dst.y, dst.G) or isInf)

func fromHex*(dst: var (ECP_ShortW_Prj or ECP_ShortW_Jac), x0, x1, y0, y1: string): bool =
  ## Convert hex strings to a G2 curve point
  ## Returns `false`
  ## if there is no point with coordinates (`x`, `y`) on the curve
  ## In that case, `dst` content is undefined.
  static: doAssert dst.F is Fp2, "dst must be on G2, an elliptic curve over 𝔽p2"
  dst.x.fromHex(x0, x1)
  dst.y.fromHex(y0, y1)
  dst.z.setOne()
  let isInf = dst.x.isZero() and dst.y.isZero()
  dst.z.csetZero(isInf)
  return bool(isOnCurve(dst.x, dst.y, dst.G) or isInf)

func fromHex*(dst: var ECP_ShortW_Aff, x, y: string): bool =
  ## Convert hex strings to a G1 curve point
  ## Returns true if point exist or if input is the point at infinity (all 0)
  ## Returns `false` if there is no point with coordinates (`x`, `y`) on the curve
  ## In that case, `dst` content is undefined.
  static: doAssert dst.F is Fp, "dst must be on G1, an elliptic curve over 𝔽p"
  dst.x.fromHex(x)
  dst.y.fromHex(y)
  return bool(isOnCurve(dst.x, dst.y, dst.G) or dst.isInf())

func fromHex*(dst: var ECP_ShortW_Aff, x0, x1, y0, y1: string): bool =
  ## Convert hex strings to a G2 curve point
  ## Returns true if point exist or if input is the point at infinity (all 0)
  ## Returns `false` if there is no point with coordinates (`x`, `y`) on the curve
  ## In that case, `dst` content is undefined.
  static: doAssert dst.F is Fp2, "dst must be on G2, an elliptic curve over 𝔽p2"
  dst.x.fromHex(x0, x1)
  dst.y.fromHex(y0, y1)
  return bool(isOnCurve(dst.x, dst.y, dst.G) or dst.isInf())

func fromHex*[EC: ECP_ShortW_Prj or ECP_ShortW_Jac or ECP_ShortW_Aff](
       _: type EC, x, y: string): EC =
  doAssert result.fromHex(x, y)

func fromHex*[EC: ECP_ShortW_Prj or ECP_ShortW_Jac or ECP_ShortW_Aff](
       _: type EC, x0, x1, y0, y1: string): EC =
  doAssert result.fromHex(x0, x1, y0, y1)