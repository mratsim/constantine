# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

## ############################################################
##
##                 BLS12-381 Serialization
##
## ############################################################
##
## Blockchains have standardized BLS12-381 serialization on Zcash format.
## That format is mentioned in Appendix-A of the IETF BLS signatures draft
##
## BLS12-381 serialization
##
##     𝔽p elements are encoded in big-endian form. They occupy 48 bytes in this form.
##     𝔽p2​ elements are encoded in big-endian form, meaning that the 𝔽p2​ element c0+c1u
##     is represented by the 𝔽p​ element c1​ followed by the 𝔽p element c0​.
##     This means 𝔽p2​ elements occupy 96 bytes in this form.
##     The group 𝔾1​ uses 𝔽p elements for coordinates. The group 𝔾2​ uses 𝔽p2​ elements for coordinates.
##     𝔾1​ and 𝔾2​ elements can be encoded in uncompressed form (the x-coordinate followed by the y-coordinate) or in compressed form (just the x-coordinate).
##     𝔾1​ elements occupy 96 bytes in uncompressed form, and 48 bytes in compressed form.
##     𝔾2​ elements occupy 192 bytes in uncompressed form, and 96 bytes in compressed form.
##
## The most-significant three bits of a 𝔾1​ or 𝔾2​ encoding should be masked away before the coordinate(s) are interpreted. These bits are used to unambiguously represent the underlying element:
##
##     The most significant bit, when set, indicates that the point is in compressed form. Otherwise, the point is in uncompressed form.
##     The second-most significant bit indicates that the point is at infinity. If this bit is set, the remaining bits of the group element’s encoding should be set to zero.
##     The third-most significant bit is set if (and only if) this point is in compressed form
##     and it is not the point at infinity and its y-coordinate is the lexicographically largest of the two associated with the encoded x-coordinate.
##
## - https://datatracker.ietf.org/doc/html/draft-irtf-cfrg-bls-signature-05#appendix-A
## - https://docs.rs/bls12_381/latest/bls12_381/notes/serialization/index.html
##   - https://github.com/zkcrypto/bls12_381/blob/0.6.0/src/notes/serialization.rs

import
    constantine/platforms/abstractions,
    constantine/named/algebras,
    constantine/named/zoo_subgroups,
    constantine/math/[
      ec_shortweierstrass,
      extension_fields,
      arithmetic],
    constantine/math/io/[io_bigints, io_fields],
    ./codecs_status_codes

const pre = "ctt_bls12_381_"
import ../zoo_exports

# Input validation
# ------------------------------------------------------------------------------------------------

func validate_scalar*(scalar: Fr[BLS12_381].getBigInt()): CttCodecScalarStatus {.libPrefix: pre.} =
  ## Validate a scalar
  ## Regarding timing attacks, this will leak information
  ## if the scalar is 0 or larger than the curve order.
  if scalar.isZero().bool():
    return cttCodecScalar_Zero
  if bool(scalar >= Fr[BLS12_381].getModulus()):
    return cttCodecScalar_ScalarLargerThanCurveOrder
  return cttCodecScalar_Success

func validate_g1*(g1P: EC_ShortW_Aff[Fp[BLS12_381], G1]): CttCodecEccStatus {.libPrefix: pre.} =
  ## Validate a G1 point
  ## This is an expensive operation that can be cached
  if g1P.isNeutral().bool():
    return cttCodecEcc_PointAtInfinity
  if not isOnCurve(g1P.x, g1P.y, G1).bool():
    return cttCodecEcc_PointNotOnCurve
  if not g1P.isInSubgroup().bool():
    return cttCodecEcc_PointNotInSubgroup
  return cttCodecEcc_Success

func validate_g2*(g2P: EC_ShortW_Aff[Fp2[BLS12_381], G2]): CttCodecEccStatus {.libPrefix: pre.} =
  ## Validate a G2 point.
  ## This is an expensive operation that can be cached
  if g2P.isNeutral().bool():
    return cttCodecEcc_PointAtInfinity
  if not isOnCurve(g2P.x, g2P.y, G2).bool():
    return cttCodecEcc_PointNotOnCurve
  if not g2P.isInSubgroup().bool():
    return cttCodecEcc_PointNotInSubgroup
  return cttCodecEcc_Success

# Codecs
# ------------------------------------------------------------------------------------------------

func serialize_scalar*(dst: var array[32, byte], scalar: Fr[BLS12_381].getBigInt()): CttCodecScalarStatus {.libPrefix: pre, discardable.} =
  ## Serialize a scalar
  ## Returns cttCodecScalar_Success if successful
  dst.marshal(scalar, bigEndian)
  return cttCodecScalar_Success

func deserialize_scalar*(dst: var Fr[BLS12_381].getBigInt(), src: array[32, byte]): CttCodecScalarStatus {.libPrefix: pre.} =
  ## Deserialize a scalar
  ## Also validates the scalar range
  ##
  ## This is protected against side-channel unless the scalar is invalid.
  ## In that case it will leak whether it's all zeros or larger than the curve order.
  ##
  ## This special-cases (and leaks) 0 scalar as this is a special-case in most protocols
  ## or completely invalid (for secret keys).
  dst.unmarshal(src, bigEndian)
  let status = validate_scalar(dst)
  if status != cttCodecScalar_Success:
    dst.setZero()
    return status
  return cttCodecScalar_Success


func serialize_g1_compressed*(dst: var array[48, byte], g1P: EC_ShortW_Aff[Fp[BLS12_381], G1]): CttCodecEccStatus {.libPrefix: pre, discardable.} =
  ## Serialize a BLS12-381 G1 point in compressed (Zcash) format
  ##
  ## Returns cttCodecEcc_Success if successful
  if g1P.isNeutral().bool():
    for i in 0 ..< dst.len:
      dst[i] = byte 0
    dst[0] = byte 0b11000000 # Compressed + Infinity
    return cttCodecEcc_Success

  dst.marshal(g1P.x, bigEndian)
  # The curve equation has 2 solutions for y² = x³ + 4 with y unknown and x known
  # The lexicographically largest will have bit 381 set to 1
  # (and bit 383 for the compressed representation)
  # The solutions are {y, p-y}.
  # The field contains [0, p-1] hence lexicographically largest
  # are numbers greater or equal (p-1)/2
  # https://github.com/zkcrypto/bls12_381/blob/0.7.0/src/fp.rs#L271-L277
  let lexicographicallyLargest = byte(g1P.y.toBig() >= Fp[BLS12_381].getPrimeMinus1div2())
  dst[0] = dst[0] or (0b10000000 or (lexicographicallyLargest shl 5))

  return cttCodecEcc_Success

func deserialize_g1_compressed_unchecked*(dst: var EC_ShortW_Aff[Fp[BLS12_381], G1], src: array[48, byte]): CttCodecEccStatus {.libPrefix: pre.} =
  ## Deserialize a BLS12-381 G1 point in compressed (Zcash) format.
  ##
  ## Warning ⚠:
  ##   This procedure skips the very expensive subgroup checks.
  ##   Not checking subgroup exposes a protocol to small subgroup attacks.
  ##
  ## Returns cttCodecEcc_Success if successful

  # src must have the compressed flag
  if (src[0] and byte 0b10000000) == byte 0:
    return cttCodecEcc_InvalidEncoding

  # if infinity, src must be all zeros
  if (src[0] and byte 0b01000000) != 0:
    if (src[0] and byte 0b00111111) != 0: # Check all the remaining bytes in MSB
      return cttCodecEcc_InvalidEncoding
    for i in 1 ..< src.len:
      if src[i] != byte 0:
        return cttCodecEcc_InvalidEncoding
    dst.setNeutral()
    return cttCodecEcc_PointAtInfinity

  # General case
  var t{.noInit.}: Fp[BLS12_381].getBigInt()
  t.unmarshal(src, bigEndian)
  t.limbs[t.limbs.len-1] = t.limbs[t.limbs.len-1] and (MaxWord shr 3) # The first 3 bytes contain metadata to mask out

  if bool(t >= Fp[BLS12_381].getModulus()):
    return cttCodecEcc_CoordinateGreaterThanOrEqualModulus

  var x{.noInit.}: Fp[BLS12_381]
  x.fromBig(t)

  let onCurve = dst.trySetFromCoordX(x)
  if not(bool onCurve):
    return cttCodecEcc_PointNotOnCurve

  let isLexicographicallyLargest = dst.y.toBig() >= Fp[BLS12_381].getPrimePlus1div2()
  let srcIsLargest = SecretBool((src[0] shr 5) and byte 1)
  dst.y.cneg(isLexicographicallyLargest xor srcIsLargest)

  return cttCodecEcc_Success

func deserialize_g1_compressed*(dst: var EC_ShortW_Aff[Fp[BLS12_381], G1], src: array[48, byte]): CttCodecEccStatus {.libPrefix: pre.} =
  ## Deserialize a BLS12-381 G1 point in compressed (Zcash) format
  ## This also validates the G1 point
  ##
  ## Returns cttCodecEcc_Success if successful

  result = deserialize_g1_compressed_unchecked(dst, src)
  if result != cttCodecEcc_Success:
    return result

  if not(bool dst.isInSubgroup()):
    return cttCodecEcc_PointNotInSubgroup

  return cttCodecEcc_Success


func serialize_g2_compressed*(dst: var array[96, byte], g2P: EC_ShortW_Aff[Fp2[BLS12_381], G2]): CttCodecEccStatus {.libPrefix: pre.} =
  ## Serialize a BLS12-381 G2 point in compressed (Zcash) format
  ##
  ## Returns cttCodecEcc_Success if successful
  if g2P.isNeutral().bool():
    for i in 0 ..< dst.len:
      dst[i] = byte 0
    dst[0] = byte 0b11000000 # Compressed + Infinity
    return cttCodecEcc_Success

  dst.toOpenArray(0, 48-1).marshal(g2P.x.c1, bigEndian)
  dst.toOpenArray(48, 96-1).marshal(g2P.x.c0, bigEndian)

  let isLexicographicallyLargest =
    if g2P.y.c1.isZero().bool():
      byte(g2P.y.c0.toBig() >= Fp[BLS12_381].getPrimePlus1div2())
    else:
      byte(g2P.y.c1.toBig() >= Fp[BLS12_381].getPrimePlus1div2())
  dst[0] = dst[0] or (byte 0b10000000 or (isLexicographicallyLargest shl 5))

  return cttCodecEcc_Success

func deserialize_g2_compressed_unchecked*(dst: var EC_ShortW_Aff[Fp2[BLS12_381], G2], src: array[96, byte]): CttCodecEccStatus {.libPrefix: pre.} =
  ## Deserialize a BLS12-381 G2 point in compressed (Zcash) format.
  ##
  ## Warning ⚠:
  ##   This procedure skips the very expensive subgroup checks.
  ##   Not checking subgroup exposes a protocol to small subgroup attacks.
  ##
  ## Returns cttCodecEcc_Success if successful

  # src must have the compressed flag
  if (src[0] and byte 0b10000000) == byte 0:
    return cttCodecEcc_InvalidEncoding

  # if infinity, src must be all zeros
  if (src[0] and byte 0b01000000) != 0:
    if (src[0] and byte 0b00111111) != 0: # Check all the remaining bytes in MSB
      return cttCodecEcc_InvalidEncoding
    for i in 1 ..< src.len:
      if src[i] != byte 0:
        return cttCodecEcc_InvalidEncoding
    dst.setNeutral()
    return cttCodecEcc_PointAtInfinity

  # General case
  var t{.noInit.}: Fp[BLS12_381].getBigInt()
  t.unmarshal(src.toOpenArray(0, 48-1), bigEndian)
  t.limbs[t.limbs.len-1] = t.limbs[t.limbs.len-1] and (MaxWord shr 3) # The first 3 bytes contain metadata to mask out

  if bool(t >= Fp[BLS12_381].getModulus()):
    return cttCodecEcc_CoordinateGreaterThanOrEqualModulus

  var x{.noInit.}: Fp2[BLS12_381]
  x.c1.fromBig(t)

  t.unmarshal(src.toOpenArray(48, 96-1), bigEndian)
  if bool(t >= Fp[BLS12_381].getModulus()):
    return cttCodecEcc_CoordinateGreaterThanOrEqualModulus

  x.c0.fromBig(t)

  let onCurve = dst.trySetFromCoordX(x)
  if not(bool onCurve):
    return cttCodecEcc_PointNotOnCurve

  let isLexicographicallyLargest =
    if dst.y.c1.isZero().bool():
      dst.y.c0.toBig() >= Fp[BLS12_381].getPrimePlus1div2()
    else:
      dst.y.c1.toBig() >= Fp[BLS12_381].getPrimePlus1div2()

  let srcIsLargest = SecretBool((src[0] shr 5) and byte 1)
  dst.y.cneg(isLexicographicallyLargest xor srcIsLargest)

  return cttCodecEcc_Success

func deserialize_g2_compressed*(dst: var EC_ShortW_Aff[Fp2[BLS12_381], G2], src: array[96, byte]): CttCodecEccStatus {.libPrefix: pre.} =
  ## Deserialize a BLS12-381 G2 point in compressed (Zcash) format
  ##
  ## Returns cttCodecEcc_Success if successful

  result = deserialize_g2_compressed_unchecked(dst, src)
  if result != cttCodecEcc_Success:
    return result

  if not(bool dst.isInSubgroup()):
    return cttCodecEcc_PointNotInSubgroup

  return cttCodecEcc_Success
