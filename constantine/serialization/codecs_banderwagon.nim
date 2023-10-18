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
    ec_twistededwards_projective,
    ec_twistededwards_batch_ops
  ],
  ../math/[
    extension_fields,
    arithmetic,
    constants/banderwagon_subgroups
  ],
  ../math/io/[io_bigints, io_fields],
  ./codecs_status_codes

type
  EC_Prj* = ECP_TwEdwards_Prj[Fp[Banderwagon]]
  EC_Aff* = ECP_TwEdwards_Aff[Fp[Banderwagon]]

func serialize*(dst: var array[32, byte], P: EC_Prj): CttCodecEccStatus =
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
  
  # Convert the projective points into affine format before encoding
  var aff {.noInit.}: EC_Aff
  aff.affine(P)

  let lexicographicallyLargest = aff.y.toBig() >= Fp[Banderwagon].getPrimeMinus1div2()

  if not lexicographicallyLargest.bool():
    aff.x.neg()

  dst.marshal(aff.x, bigEndian)
  return cttCodecEcc_Success

func deserialize_unchecked*(dst: var EC_Prj, src: array[32, byte]): CttCodecEccStatus =
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

func deserialize*(dst: var EC_Prj, src: array[32, byte]): CttCodecEccStatus =
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

## ############################################################
##
##              Banderwagon Batch Serialization
##
## ############################################################

func serializeBatch*(
    dst: ptr UncheckedArray[array[32, byte]],
    points: ptr UncheckedArray[EC_Prj],
    N: int,
  ) : CttCodecEccStatus {.noInline.} =

  # collect all the z coordinates
  var zs = allocStackArray(Fp[Banderwagon], N)
  var zs_inv = allocStackArray(Fp[Banderwagon], N)
  for i in 0 ..< N:
    zs[i] = points[i].z

  zs_inv.batchInvert(zs, N)
  
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

func serializeBatch*[N: static int](
        dst: var array[N, array[32, byte]],
        points: array[N, EC_Prj]): CttCodecEccStatus {.inline.} =
  return serializeBatch(dst.asUnchecked(), points.asUnchecked(), N)