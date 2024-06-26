# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

## ############################################################
##
##                 Banderwagon Serialization
##
## ############################################################

import
  constantine/platforms/abstractions,
  constantine/named/algebras,
  constantine/named/constants/banderwagon_subgroups,
  constantine/math/ec_twistededwards,
  constantine/math/arithmetic/limbs_montgomery,
  constantine/math/[
    extension_fields,
    arithmetic],
  constantine/math/io/[io_bigints, io_fields],
  ./codecs_status_codes

## ############################################################
##
##              Banderwagon Scalar Serialization
##
## ############################################################

# Input validation
# ------------------------------------------------------------------------------------------------
func validate_scalar*(scalar: Fr[Banderwagon].getBigInt()): CttCodecScalarStatus =
  ## Validate a scalar
  ## Regarding timing attacks, this will leak information
  ## if the scalar is 0 or larger than the curve order.
  if scalar.isZero().bool():
    return cttCodecScalar_Zero
  if bool(scalar >= Fr[Banderwagon].getModulus()):
    return cttCodecScalar_ScalarLargerThanCurveOrder
  return cttCodecScalar_Success

# ------------------------------------------------------------------------------------------------

func serialize_scalar*(
      dst: var array[32, byte],
      scalar: Fr[Banderwagon].getBigInt(),
      order: static Endianness = bigEndian): CttCodecScalarStatus {.discardable.} =
  ## Serialize a scalar
  ## Returns cttCodecScalar_Success if successful
  dst.marshal(scalar, order)
  return cttCodecScalar_Success

func serialize_fr*(
      dst: var array[32, byte],
      scalar: Fr[Banderwagon],
      order: static Endianness = bigEndian): CttCodecScalarStatus {.discardable.} =
  ## Serialize a scalar
  ## Returns cttCodecScalar_Success if successful
  return dst.serialize_scalar(scalar.toBig(), order)

func deserialize_scalar*(dst: var Fr[Banderwagon].getBigInt(), src: array[32, byte], order: static Endianness = bigEndian): CttCodecScalarStatus =
  ## Deserialize a scalar
  ## Also validates the scalar range
  ##
  ## This is protected against side-channel unless the scalar is invalid.
  ## In that case it will leak whether it's all zeros or larger than the curve order.
  ##
  ## This special-cases (and leaks) 0 scalar as this is a special-case in most protocols
  ## or completely invalid (for secret keys).
  dst.unmarshal(src, order)
  let status = validate_scalar(dst)
  if status != cttCodecScalar_Success:
    dst.setZero()
    return status
  return cttCodecScalar_Success

func deserialize_fr*(
      dst: var Fr[Banderwagon],
      src: array[32, byte],
      order: static Endianness = bigEndian): CttCodecScalarStatus {.discardable.} =
  ## Deserialize a scalar
  ## Reduce the value of the scalar (modulo the curve order)
  var scalar {.noInit.}: BigInt[256]
  scalar.unmarshal(src, order)

  getMont(dst.mres.limbs, scalar.limbs,
        Fr[Banderwagon].getModulus().limbs,
        Fr[Banderwagon].getR2modP().limbs,
        Fr[Banderwagon].getNegInvModWord(),
        Fr[Banderwagon].getSpareBits())

  return cttCodecScalar_Success

## ############################################################
##
##          Banderwagon Elliptic Curve Serialization
##
## ############################################################


func serialize*(dst: var array[32, byte], P: EC_TwEdw_Aff[Fp[Banderwagon]]): CttCodecEccStatus {.discardable.} =
  ## Serialize a Banderwagon point(x, y) in the format
  ##
  ## serialize = bigEndian( sign(y) * x )
  ## If y is not lexicographically largest
  ## set x -> -x
  ## then serialize
  ##
  ## Returns cttCodecEcc_Success if successful
  ## Spec: https://hackmd.io/@6iQDuIePQjyYBqDChYw_jg/BJBNcv9fq#Serialisation

  # Setting all bits to 0 for the point of infinity
  if P.isNeutral().bool():
    for i in 0 ..< dst.len:
      dst[i] = byte 0
    return cttCodecEcc_Success

  let lexicographicallyLargest = P.y.toBig() >= Fp[Banderwagon].getPrimeMinus1div2()
  var X = P.x
  X.cneg(not lexicographicallyLargest)
  dst.marshal(X, bigEndian)
  return cttCodecEcc_Success

func serialize*(dst: var array[32, byte], P: EC_TwEdw_Prj[Fp[Banderwagon]]): CttCodecEccStatus {.discardable.} =
  ## Serialize a Banderwagon point(x, y) in the format
  ##
  ## serialize = bigEndian( sign(y) * x )
  ## If y is not lexicographically largest
  ## set x -> -x
  ## then serialize
  ##
  ## Returns cttCodecEcc_Success if successful
  ## Spec: https://hackmd.io/@6iQDuIePQjyYBqDChYw_jg/BJBNcv9fq#Serialisation

  # Convert the projective points into affine format before encoding
  var aff {.noInit.}: EC_TwEdw_Aff[Fp[Banderwagon]]
  aff.affine(P)

  return dst.serialize(aff)

func deserialize_unchecked_vartime*(dst: var EC_TwEdw_Aff[Fp[Banderwagon]], src: array[32, byte]): CttCodecEccStatus =
  ## Deserialize a Banderwagon point (x, y) in format
  ##
  ## if y is not lexicographically largest
  ## set y -> -y
  ##
  ## Returns cttCodecEcc_Success if successful
  ## https://hackmd.io/@6iQDuIePQjyYBqDChYw_jg/BJBNcv9fq#Serialisation
  ##
  ## This leaks:
  ##   - if input was infinity
  ##   - if input was invalid: coordinater larger than base prime field
  ##   - if input was invalid: point is not on the curve
  ##
  ## This uses a Banderwagon specific "precomputed discrete log" optimization
  # If infinity, src must be all zeros
  var allZeros = byte(0)
  for i in 0 ..< src.len:
    allZeros = allZeros or src[i]
  if allZeros == 0:
    dst.setNeutral()
    return cttCodecEcc_PointAtInfinity

  var t{.noInit.}: Fp[Banderwagon].getBigInt()
  t.unmarshal(src, bigEndian)

  if bool(t >= Fp[Banderwagon].getModulus()):
    return cttCodecEcc_CoordinateGreaterThanOrEqualModulus

  var x{.noInit.}: Fp[Banderwagon]
  x.fromBig(t)

  let onCurve = dst.trySetFromCoordX_vartime(x)
  if not(bool onCurve):
    return cttCodecEcc_PointNotOnCurve

  let isLexicographicallyLargest = dst.y.toBig() >= Fp[Banderwagon].getPrimeMinus1div2()
  dst.y.cneg(not isLexicographicallyLargest)

  return cttCodecEcc_Success

func deserialize_vartime*(dst: var EC_TwEdw_Aff[Fp[Banderwagon]], src: array[32, byte]): CttCodecEccStatus =
  ## Deserialize a Banderwagon point (x, y) in format
  ##
  ## Also checks if the point lies in the banderwagon scheme subgroup
  ##
  ## Returns cttCodecEcc_Success if successful
  ## Returns cttCodecEcc_PointNotInSubgroup if doesn't lie in subgroup
  ##
  ## This uses a Banderwagon specific "precomputed discrete log" optimization
  result = deserialize_unchecked_vartime(dst, src)
  if result != cttCodecEcc_Success:
    return result

  if not(bool dst.isInSubgroup()):
    return cttCodecEcc_PointNotInSubgroup

  return cttCodecEcc_Success

# Debugging
# ------------------------------------------------------------------------------------------------

func toHex*(P: EC_TwEdw_Aff[Fp[Banderwagon]], canonicalize: static bool = true, indent: static int = 0): string =
  ## Stringify an elliptic curve point to Hex for Banderwagon
  ## (x, y) and (-x, -y) are in the same equivalence class for Banderwagon.
  ## By default, we negate the hex encoding if y is not the lexicographically largest.
  ## Pass `canonicalize` = false to get usual Twisted Edwards hex encoding.
  ##
  ## This is intended for debugging

  var aff {.noInit.}: EC_TwEdw_Aff[Fp[Banderwagon]]
  aff = P

  const sp = spaces(indent)

  let lexicographicallyLargest = P.y.toBig() >= Fp[Banderwagon].getPrimeMinus1div2()
  aff.x.cneg(not lexicographicallyLargest)
  aff.y.cneg(not lexicographicallyLargest)

  result = sp & $EC_TwEdw_Aff[Fp[Banderwagon]] & "(\n" & sp & "  x: "
  result.appendHex(aff.x)
  result &= ",\n" & sp & "  y: "
  result.appendHex(aff.y)
  result &= "\n" & sp & ")"

func toHex*(P: EC_TwEdw_Prj[Fp[Banderwagon]], canonicalize: static bool = true, indent: static int = 0): string =
  ## Stringify an elliptic curve point to Hex for Banderwagon
  ## (x, y) and (-x, -y) are in the same equivalence class for Banderwagon.
  ## By default, we negate the hex encoding if y is not the lexicographically largest.
  ## Pass `canonicalize` = false to get usual Twisted Edwards hex encoding.
  ##
  ## This is intended for debugging
  var aff {.noInit.}: EC_TwEdw_Aff[Fp[Banderwagon]]
  aff.affine(P)
  return aff.toHex(canonicalize, indent)

## ############################################################
##
##              Banderwagon Batch Serialization
##
## ############################################################

func serializeBatch_vartime*(
    dst: ptr UncheckedArray[array[32, byte]],
    points: ptr UncheckedArray[EC_TwEdw_Prj[Fp[Banderwagon]]],
    N: int,
  ) : CttCodecEccStatus {.noInline.} =

  # collect all the z coordinates
  var zs = allocStackArray(Fp[Banderwagon], N)
  var zs_inv = allocStackArray(Fp[Banderwagon], N)
  for i in 0 ..< N:
    zs[i] = points[i].z

  zs_inv.batchInv_vartime(zs, N)

  for i in 0 ..< N:
    var X: Fp[Banderwagon]
    var Y: Fp[Banderwagon]

    X.prod(points[i].x, zs_inv[i])
    Y.prod(points[i].y, zs_inv[i])

    let lexicographicallyLargest = Y.toBig() >= Fp[Banderwagon].getPrimeMinus1div2()
    if not lexicographicallyLargest.bool():
      X.neg()

    dst[i].marshal(X, bigEndian)

  return cttCodecEcc_Success

func serializeBatchUncompressed_vartime*(
    dst: ptr UncheckedArray[array[64, byte]],
    points: ptr UncheckedArray[EC_TwEdw_Prj[Fp[Banderwagon]]],
    N: int) : CttCodecEccStatus {.noInline.} =
  ## Batch Serialization of Banderwagon Points
  ## In uncompressed format
  ## serialize = [ bigEndian( x ) , bigEndian( y ) ]
  ## Returns cttCodecEcc_Success if successful

  # collect all the z coordinates
  var zs = allocStackArray(Fp[Banderwagon], N)
  var zs_inv = allocStackArray(Fp[Banderwagon], N)
  for i in 0 ..< N:
    zs[i] = points[i].z

  zs_inv.batchInv_vartime(zs, N)

  for i in 0 ..< N:
    var X: Fp[Banderwagon]
    var Y: Fp[Banderwagon]

    X.prod(points[i].x, zs_inv[i])
    Y.prod(points[i].y, zs_inv[i])

    var xSerialized: array[32, byte]
    xSerialized.marshal(X, bigEndian)
    var ySerialized: array[32, byte]
    ySerialized.marshal(Y, bigEndian)

    for j in 0 ..< 32:
      dst[i][j] = xSerialized[j]
      dst[i][j + 32] = ySerialized[j]

  return cttCodecEcc_Success

func serializeBatchUncompressed_vartime*[N: static int](
        dst: var array[N, array[64, byte]],
        points: array[N, EC_TwEdw_Prj[Fp[Banderwagon]]]): CttCodecEccStatus {.inline.} =
  return serializeBatchUncompressed_vartime(dst.asUnchecked(), points.asUnchecked(), N)

func serializeBatch_vartime*[N: static int](
        dst: var array[N, array[32, byte]],
        points: array[N, EC_TwEdw_Prj[Fp[Banderwagon]]]): CttCodecEccStatus {.inline.} =
  return serializeBatch_vartime(dst.asUnchecked(), points.asUnchecked(), N)

## ############################################################
##
##       Banderwagon Point Uncompressed Serialization
##
## ############################################################

func serializeUncompressed*(dst: var array[64, byte], P: EC_TwEdw_Aff[Fp[Banderwagon]]): CttCodecEccStatus =
  ## Serialize a Banderwagon point(x, y) in the format
  ##
  ## serialize = [ bigEndian( x ) , bigEndian( y ) ]
  ##
  ## Returns cttCodecEcc_Success if successful
  var xSerialized: array[32, byte]
  xSerialized.marshal(P.x, bigEndian)
  var ySerialized: array[32, byte]
  ySerialized.marshal(P.y, bigEndian)

  for i in 0 ..< 32:
    dst[i] = xSerialized[i]
    dst[i + 32] = ySerialized[i]

  return cttCodecEcc_Success

func deserializeUncompressed_unchecked*(dst: var EC_TwEdw_Aff[Fp[Banderwagon]], src: array[64, byte]): CttCodecEccStatus =
  ## Deserialize a Banderwagon point (x, y) in format
  ## Doesn't check if the point is in the banderwagon scheme subgroup
  ## Returns cttCodecEcc_Success if successful
  var xSerialized: array[32, byte]
  var ySerialized: array[32, byte]

  for i in 0 ..< 32:
    xSerialized[i] = src[i]
    ySerialized[i] = src[i + 32]

  var t{.noInit.}: Fp[Banderwagon].getBigInt()
  t.unmarshal(xSerialized, bigEndian)

  if bool(t >= Fp[Banderwagon].getModulus()):
    return cttCodecEcc_CoordinateGreaterThanOrEqualModulus

  dst.x.fromBig(t)

  t.unmarshal(ySerialized, bigEndian)
  if bool(t >= Fp[Banderwagon].getModulus()):
    return cttCodecEcc_CoordinateGreaterThanOrEqualModulus

  dst.y.fromBig(t)
  return cttCodecEcc_Success

func deserializeUncompressed*(dst: var EC_TwEdw_Aff[Fp[Banderwagon]], src: array[64, byte]): CttCodecEccStatus =
  ## Deserialize a Banderwagon point (x, y) in format
  ##
  ## Also checks if the point lies in the banderwagon scheme subgroup
  ##
  ## Returns cttCodecEcc_Success if successful
  result = dst.deserializeUncompressed_unchecked(src)
  if not(bool dst.isInSubgroup()):
    return cttCodecEcc_PointNotInSubgroup
