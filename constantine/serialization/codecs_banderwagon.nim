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
  ../platforms/abstractions,
  ../math/config/curves,
  ../math/elliptic/[
    ec_twistededwards_affine,
    ec_twistededwards_projective],
  ../math/arithmetic/limbs_montgomery,
  ../math/[
    arithmetic/bigints,
    extension_fields,
    arithmetic,
    constants/banderwagon_subgroups
  ],
  ../math/io/[io_bigints, io_fields],
  ./codecs_status_codes

# Input validation
# ------------------------------------------------------------------------------------------------
func validate_scalar*(scalar: matchingOrderBigInt(Banderwagon)): CttCodecScalarStatus =
  ## Validate a scalar
  ## Regarding timing attacks, this will leak information
  ## if the scalar is 0 or larger than the curve order.
  if scalar.isZero().bool():
    return cttCodecScalar_Zero
  if bool(scalar >= Banderwagon.getCurveOrder()):
    return cttCodecScalar_ScalarLargerThanCurveOrder
  return cttCodecScalar_Success

func make_scalar_mod_order*(reduced_scalar: var Fr[Banderwagon], src: array[32, byte], order: static Endianness = bigEndian): bool =
  ## Convert a 32-byte array to a field element, reducing it modulo Banderwagon's curve order if necessary.

  # Which can be safely stored in a 256 BigInt
  # Now incase of the scalar overflowing the last 3-bits
  # it is converted from its natural representation
  # to the Montgomery residue form
  var res: bool = false
  var scalar {.noInit.}: BigInt[256]
  scalar.unmarshal(src, order)

  getMont(reduced_scalar.mres.limbs, scalar.limbs,
        Fr[Banderwagon].fieldMod().limbs,
        Fr[Banderwagon].getR2modP().limbs,
        Fr[Banderwagon].getNegInvModWord(),
        Fr[Banderwagon].getSpareBits())
  res = true
  return res

func serialize*(dst: var array[32, byte], P: ECP_TwEdwards_Aff[Fp[Banderwagon]]): CttCodecEccStatus =
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
  if P.isInf().bool():
    for i in 0 ..< dst.len:
      dst[i] = byte 0
    return cttCodecEcc_Success

  let lexicographicallyLargest = P.y.toBig() >= Fp[Banderwagon].getPrimeMinus1div2()
  var X = P.x
  X.cneg(not lexicographicallyLargest)
  dst.marshal(X, bigEndian)
  return cttCodecEcc_Success

func serialize*(dst: var array[32, byte], P: ECP_TwEdwards_Prj[Fp[Banderwagon]]): CttCodecEccStatus =
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
  var aff {.noInit.}: ECP_TwEdwards_Aff[Fp[Banderwagon]]
  aff.affine(P)

  return dst.serialize(aff)

func deserialize_unchecked*(dst: var ECP_TwEdwards_Prj[Fp[Banderwagon]], src: array[32, byte]): CttCodecEccStatus =
  ## Deserialize a Banderwagon point (x, y) in format
  ##
  ## if y is not lexicographically largest
  ## set y -> -y
  ##
  ## Returns cttCodecEcc_Success if successful
  ## https://hackmd.io/@6iQDuIePQjyYBqDChYw_jg/BJBNcv9fq#Serialisation
  # If infinity, src must be all zeros
  var check: bool = true
  for i in 0 ..< src.len:
    if src[i] != byte 0:
      check = false
      break
  if check:
    dst.setInf()
    return cttCodecEcc_PointAtInfinity

  var t{.noInit.}: matchingBigInt(Banderwagon)
  t.unmarshal(src, bigEndian)

  if bool(t >= Banderwagon.Mod()):
    return cttCodecEcc_CoordinateGreaterThanOrEqualModulus

  var x{.noInit.}: Fp[Banderwagon]
  x.fromBig(t)

  let onCurve = dst.trySetFromCoordX(x)
  if not(bool onCurve):
    return cttCodecEcc_PointNotOnCurve

  let isLexicographicallyLargest = dst.y.toBig() >= Fp[Banderwagon].getPrimeMinus1div2()
  dst.y.cneg(not isLexicographicallyLargest)

  return cttCodecEcc_Success

func deserialize_unchecked_vartime*(dst: var ECP_TwEdwards_Prj[Fp[Banderwagon]], src: array[32, byte]): CttCodecEccStatus =
  ## This is not in constant-time
  ## Deserialize a Banderwagon point (x, y) in format
  ##
  ## if y is not lexicographically largest
  ## set y -> -y
  ##
  ## Returns cttCodecEcc_Success if successful
  ## https://hackmd.io/@6iQDuIePQjyYBqDChYw_jg/BJBNcv9fq#Serialisation
  # If infinity, src must be all zeros
  var check: bool = true
  for i in 0 ..< src.len:
    if src[i] != byte 0:
      check = false
      break
  if check:
    dst.setInf()
    return cttCodecEcc_PointAtInfinity

  var t{.noInit.}: matchingBigInt(Banderwagon)
  t.unmarshal(src, bigEndian)

  if bool(t >= Banderwagon.Mod()):
    return cttCodecEcc_CoordinateGreaterThanOrEqualModulus

  var x{.noInit.}: Fp[Banderwagon]
  x.fromBig(t)

  let onCurve = dst.trySetFromCoordX_vartime(x)
  if not(bool onCurve):
    return cttCodecEcc_PointNotOnCurve

  let isLexicographicallyLargest = dst.y.toBig() >= Fp[Banderwagon].getPrimeMinus1div2()
  dst.y.cneg(not isLexicographicallyLargest)

  return cttCodecEcc_Success

func deserialize*(dst: var ECP_TwEdwards_Prj[Fp[Banderwagon]], src: array[32, byte]): CttCodecEccStatus =
  ## Deserialize a Banderwagon point (x, y) in format
  ##
  ## Also checks if the point lies in the banderwagon scheme subgroup
  ##
  ## Returns cttCodecEcc_Success if successful
  ## Returns cttCodecEcc_PointNotInSubgroup if doesn't lie in subgroup
  result = deserialize_unchecked(dst, src)
  if result != cttCodecEcc_Success:
    return result

  if not(bool dst.isInSubgroup()):
    return cttCodecEcc_PointNotInSubgroup

  return cttCodecEcc_Success

func deserialize_vartime*(dst: var ECP_TwEdwards_Prj[Fp[Banderwagon]], src: array[32, byte]): CttCodecEccStatus =
  ## Deserialize a Banderwagon point (x, y) in format
  ##
  ## Also checks if the point lies in the banderwagon scheme subgroup
  ##
  ## Returns cttCodecEcc_Success if successful
  ## Returns cttCodecEcc_PointNotInSubgroup if doesn't lie in subgroup
  result = deserialize_unchecked_vartime(dst, src)
  if result != cttCodecEcc_Success:
    return result

  if not(bool dst.isInSubgroup()):
    return cttCodecEcc_PointNotInSubgroup

  return cttCodecEcc_Success

## ############################################################
##
##              Banderwagon Scalar Serialization
##
## ############################################################
##
func serialize_scalar*(dst: var array[32, byte], scalar: matchingOrderBigInt(Banderwagon), order: static Endianness = bigEndian): CttCodecScalarStatus =
  ## Adding an optional Endianness param default at BigEndian
  ## Serialize a scalar
  ## Returns cttCodecScalar_Success if successful
  dst.marshal(scalar, order)
  return cttCodecScalar_Success

## ############################################################
##
##              Banderwagon Scalar Deserialization
##
## ############################################################
##
func deserialize_scalar*(dst: var matchingOrderBigInt(Banderwagon), src: array[32, byte], order: static Endianness = bigEndian): CttCodecScalarStatus =
  ## Adding an optional Endianness param default at BigEndian
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

func deserialize_scalar_mod_order* (dst: var Fr[Banderwagon], src: array[32, byte], order: static Endianness = bigEndian): CttCodecScalarStatus =
  ## Deserialize a scalar
  ## Take mod value of the scalar (MOD CurveOrder)
  ## If the scalar values goes out of range
  let stat {.used.} = dst.make_scalar_mod_order(src, order)
  debug: doAssert stat, "transcript_gen.deserialize_scalar_mod_order: Unexpected failure"

  return cttCodecScalar_Success

## ############################################################
##
##              Banderwagon Batch Serialization
##
## ############################################################

func serializeBatch*(
    dst: ptr UncheckedArray[array[32, byte]],
    points: ptr UncheckedArray[ECP_TwEdwards_Prj[Fp[Banderwagon]]],
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

func serializeBatchUncompressed*(
    dst: ptr UncheckedArray[array[64, byte]],
    points: ptr UncheckedArray[ECP_TwEdwards_Prj[Fp[Banderwagon]]],
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

func serializeBatchUncompressed*[N: static int](
        dst: var array[N, array[64, byte]],
        points: array[N, ECP_TwEdwards_Prj[Fp[Banderwagon]]]): CttCodecEccStatus {.inline.} =
  return serializeBatchUncompressed(dst.asUnchecked(), points.asUnchecked(), N)

func serializeBatch*[N: static int](
        dst: var array[N, array[32, byte]],
        points: array[N, ECP_TwEdwards_Prj[Fp[Banderwagon]]]): CttCodecEccStatus {.inline.} =
  return serializeBatch(dst.asUnchecked(), points.asUnchecked(), N)


## ############################################################
##
##       Banderwagon Point Uncompressed Serialization
##
## ############################################################

func serializeUncompressed*(dst: var array[64, byte], P: ECP_TwEdwards_Prj[Fp[Banderwagon]]): CttCodecEccStatus =
  ## Serialize a Banderwagon point(x, y) in the format
  ##
  ## serialize = [ bigEndian( x ) , bigEndian( y ) ]
  ##
  ## Returns cttCodecEcc_Success if successful
  var aff {.noInit.}: ECP_TwEdwards_Aff[Fp[Banderwagon]]
  aff.affine(P)

  var xSerialized: array[32, byte]
  xSerialized.marshal(aff.x, bigEndian)
  var ySerialized: array[32, byte]
  ySerialized.marshal(aff.y, bigEndian)

  for i in 0 ..< 32:
    dst[i] = xSerialized[i]
    dst[i + 32] = ySerialized[i]

  return cttCodecEcc_Success

func deserializeUncompressed_unchecked*(dst: var ECP_TwEdwards_Prj[Fp[Banderwagon]], src: array[64, byte]): CttCodecEccStatus =
  ## Deserialize a Banderwagon point (x, y) in format
  ## Doesn't check if the point is in the banderwagon scheme subgroup
  ## Returns cttCodecEcc_Success if successful
  var xSerialized: array[32, byte]
  var ySerialized: array[32, byte]

  for i in 0 ..< 32:
    xSerialized[i] = src[i]
    ySerialized[i] = src[i + 32]

  var t{.noInit.}: matchingBigInt(Banderwagon)
  t.unmarshal(xSerialized, bigEndian)

  if bool(t >= Banderwagon.Mod()):
    return cttCodecEcc_CoordinateGreaterThanOrEqualModulus

  dst.x.fromBig(t)

  t.unmarshal(ySerialized, bigEndian)
  if bool(t >= Banderwagon.Mod()):
    return cttCodecEcc_CoordinateGreaterThanOrEqualModulus

  dst.y.fromBig(t)
  return cttCodecEcc_Success

func deserializeUncompressed*(dst: var ECP_TwEdwards_Prj[Fp[Banderwagon]], src: array[64, byte]): CttCodecEccStatus =
  ## Deserialize a Banderwagon point (x, y) in format
  ##
  ## Also checks if the point lies in the banderwagon scheme subgroup
  ##
  ## Returns cttCodecEcc_Success if successful
  result = dst.deserializeUncompressed_unchecked(src)
  if not(bool dst.isInSubgroup()):
    return cttCodecEcc_PointNotInSubgroup
