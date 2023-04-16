# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
    ./platforms/[abstractions, views],
    ./math/config/curves,
    ./math/[
      ec_shortweierstrass,
      extension_fields,
      arithmetic,
      constants/zoo_subgroups
    ],
    ./math/io/[io_bigints, io_fields],
    hashes,
    signatures/bls_signatures

export
  abstractions, # generic sandwich on SecretBool and SecretBool in Jacobian sumImpl
  curves, # generic sandwich on matchingBigInt
  extension_fields, # generic sandwich on extension field access
  hashes, # generic sandwich on sha256
  ec_shortweierstrass # generic sandwich on affine

## ############################################################
##
##              BLS Signatures on BLS12-381 G2
##
## ############################################################
##
## This module implements BLS Signatures (Boneh-Lynn-Schacham)
## on top of the BLS12-381 curve (Barreto-Lynn-Scott).
##
## Ciphersuite:
##
## - Secret keys on Fr (32 bytes)
## - Public keys on G1 (48 bytes compressed, 96 bytes uncompressed)
## - Signatures on G2 (96 bytes compressed, 192 bytes uncompressed)
##
## Hash-to curve:
## - Domain separation tag: "BLS_SIG_BLS12381G2_XMD:SHA-256_SSWU_RO_POP_"
## - Hash function: SHA256
##
## Currently Constantine does not provide popProve and popVerify
## which are thin wrapper over sign/verify with
## - the message to sign or verify being the compressed or uncompressed public key
##   or another application-specific "hash_pubkey_to_point" scheme
## - domain-separation-tag: "BLS_POP_BLS12381G2_XMD:SHA-256_SSWU_RO_POP_"
##
## Constantine currently assumes that proof-of-possessions are handled at the application-level
##
## In proof-of-stake blockchains, being part of the staker/validator sets
## already serve as proof-of-possession.

const DST = "BLS_SIG_BLS12381G2_XMD:SHA-256_SSWU_RO_POP_"
const ffi_prefix {.used.} = "ctt_blssigpop_bls12381g2_"

{.push raises: [], checks: off.} # No exceptions allowed in core cryptographic operations

type
  SecretKey* {.byref, exportc: ffi_prefix & "seckey".} = object
    ## A BLS12_381 secret key
    raw: matchingOrderBigInt(BLS12_381)

  PublicKey* {.byref, exportc: ffi_prefix & "pubkey".} = object
    ## A BLS12_381 public key for BLS signature schemes with public keys on G1 and signatures on G2
    raw: ECP_ShortW_Aff[Fp[BLS12_381], G1]

  Signature* {.byref, exportc: ffi_prefix & "signature".} = object
    ## A BLS12_381 signature for BLS signature schemes with public keys on G1 and signatures on G2
    raw: ECP_ShortW_Aff[Fp2[BLS12_381], G2]

  CttBLSStatus* = enum
    cttBLS_Success
    cttBLS_VerificationFailure
    cttBLS_InvalidEncoding
    cttBLS_CoordinateGreaterOrEqualThanModulus
    cttBLS_PointAtInfinity
    cttBLS_PointNotOnCurve
    cttBLS_PointNotInSubgroup
    cttBLS_ZeroSecretKey
    cttBLS_SecretKeyLargerThanCurveOrder
    cttBLS_ZeroLengthAggregation
    cttBLS_InconsistentLengthsOfInputs

# Comparisons
# ------------------------------------------------------------------------------------------------

func pubkey_is_zero*(pubkey: PublicKey): bool {.exportc: ffi_prefix & "$1".} =
  ## Returns true if input is 0
  bool(pubkey.raw.isInf())

func signature_is_zero*(sig: Signature): bool {.exportc: ffi_prefix & "$1".} =
  ## Returns true if input is 0
  bool(sig.raw.isInf())

func pubkeys_are_equal*(a, b: PublicKey): bool {.exportc: ffi_prefix & "$1".} =
  ## Returns true if inputs are equal
  bool(a.raw == b.raw)

func signatures_are_equal*(a, b: Signature): bool {.exportc: ffi_prefix & "$1".} =
  ## Returns true if inputs are equal
  bool(a.raw == b.raw)

# Input validation
# ------------------------------------------------------------------------------------------------

func validate_seckey*(secret_key: SecretKey): CttBLSStatus {.exportc: ffi_prefix & "$1".} =
  ## Validate the secret key.
  ## Regarding timing attacks, this will leak timing information only if the key is invalid.
  ## Namely, the secret key is 0 or the secret key is too large.
  if secret_key.raw.isZero().bool():
    return cttBLS_ZeroSecretKey
  if bool(secret_key.raw >= BLS12_381.getCurveOrder()):
    return cttBLS_SecretKeyLargerThanCurveOrder
  return cttBLS_Success

func validate_pubkey*(public_key: PublicKey): CttBLSStatus {.exportc: ffi_prefix & "$1".} =
  ## Validate the public key.
  ## This is an expensive operation that can be cached
  if public_key.raw.isInf().bool():
    return cttBLS_PointAtInfinity
  if not isOnCurve(public_key.raw.x, public_key.raw.y, G1).bool():
    return cttBLS_PointNotOnCurve
  if not public_key.raw.isInSubgroup().bool():
    return cttBLS_PointNotInSubgroup

func validate_signature*(signature: Signature): CttBLSStatus {.exportc: ffi_prefix & "$1".} =
  ## Validate the signature.
  ## This is an expensive operation that can be cached
  if signature.raw.isInf().bool():
    return cttBLS_PointAtInfinity
  if not isOnCurve(signature.raw.x, signature.raw.y, G2).bool():
    return cttBLS_PointNotOnCurve
  if not signature.raw.isInSubgroup().bool():
    return cttBLS_PointNotInSubgroup

# Codecs
# ------------------------------------------------------------------------------------------------

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
## - https://datatracker.ietf.org/doc/html/draft-irtf-cfrg-bls-signature-04#appendix-A
## - https://docs.rs/bls12_381/latest/bls12_381/notes/serialization/index.html
##   - https://github.com/zkcrypto/bls12_381/blob/0.6.0/src/notes/serialization.rs

func serialize_seckey*(dst: var array[32, byte], secret_key: SecretKey): CttBLSStatus {.exportc: ffi_prefix & "$1".} =
  ## Serialize a secret key
  ## Returns cttBLS_Success if successful
  dst.marshal(secret_key.raw, bigEndian)
  return cttBLS_Success

func serialize_pubkey_compressed*(dst: var array[48, byte], public_key: PublicKey): CttBLSStatus {.exportc: ffi_prefix & "$1".} =
  ## Serialize a public key in compressed (Zcash) format
  ##
  ## Returns cttBLS_Success if successful
  if public_key.raw.isInf().bool():
    for i in 0 ..< dst.len:
      dst[i] = byte 0
    dst[0] = byte 0b11000000 # Compressed + Infinity
    return cttBLS_Success

  dst.marshal(public_key.raw.x, bigEndian)
  # The curve equation has 2 solutions for y² = x³ + 4 with y unknown and x known
  # The lexicographically largest will have bit 381 set to 1
  # (and bit 383 for the compressed representation)
  # The solutions are {y, p-y} hence the lexicographyically largest is greater than p/2
  # so with exact integers, as p is odd, greater or equal (p+1)/2
  let lexicographicallyLargest = byte(public_key.raw.y.toBig() >= Fp[BLS12_381].getPrimePlus1div2())
  dst[0] = dst[0] or (0b10000000 or (lexicographicallyLargest shl 5))

  return cttBLS_Success

func serialize_signature_compressed*(dst: var array[96, byte], signature: Signature): CttBLSStatus {.exportc: ffi_prefix & "$1".} =
  ## Serialize a signature in compressed (Zcash) format
  ##
  ## Returns cttBLS_Success if successful
  if signature.raw.isInf().bool():
    for i in 0 ..< dst.len:
      dst[i] = byte 0
    dst[0] = byte 0b11000000 # Compressed + Infinity
    return cttBLS_Success

  dst.toOpenArray(0, 48-1).marshal(signature.raw.x.c1, bigEndian)
  dst.toOpenArray(48, 96-1).marshal(signature.raw.x.c0, bigEndian)

  let isLexicographicallyLargest =
    if signature.raw.y.c1.isZero().bool():
      byte(signature.raw.y.c0.toBig() >= Fp[BLS12_381].getPrimePlus1div2())
    else:
      byte(signature.raw.y.c1.toBig() >= Fp[BLS12_381].getPrimePlus1div2())
  dst[0] = dst[0] or (byte 0b10000000 or (isLexicographicallyLargest shl 5))

  return cttBLS_Success

func deserialize_seckey*(dst: var SecretKey, src: array[32, byte]): CttBLSStatus {.exportc: ffi_prefix & "$1".} =
  ## Deserialize a secret key
  ## This also validates the secret key.
  ##
  ## This is protected against side-channel unless your key is invalid.
  ## In that case it will like whether it's all zeros or larger than the curve order.
  dst.raw.unmarshal(src, bigEndian)
  let status = validate_seckey(dst)
  if status != cttBLS_Success:
    dst.raw.setZero()
    return status
  return cttBLS_Success

func deserialize_pubkey_compressed_unchecked*(dst: var PublicKey, src: array[48, byte]): CttBLSStatus {.exportc: ffi_prefix & "$1".} =
  ## Deserialize a public_key in compressed (Zcash) format.
  ##
  ## Warning ⚠:
  ##   This procedure skips the very expensive subgroup checks.
  ##   Not checking subgroup exposes a protocol to small subgroup attacks.
  ##
  ## Returns cttBLS_Success if successful

  # src must have the compressed flag
  if (src[0] and byte 0b10000000) == byte 0:
    return cttBLS_InvalidEncoding

  # if infinity, src must be all zeros
  if (src[0] and byte 0b01000000) != 0:
    if (src[0] and byte 0b00111111) != 0: # Check all the remaining bytes in MSB
      return cttBLS_InvalidEncoding
    for i in 1 ..< src.len:
      if src[i] != byte 0:
        return cttBLS_InvalidEncoding
    dst.raw.setInf()
    return cttBLS_PointAtInfinity

  # General case
  var t{.noInit.}: matchingBigInt(BLS12_381)
  t.unmarshal(src, bigEndian)
  t.limbs[t.limbs.len-1] = t.limbs[t.limbs.len-1] and (MaxWord shr 3) # The first 3 bytes contain metadata to mask out

  if bool(t >= BLS12_381.Mod()):
    return cttBLS_CoordinateGreaterOrEqualThanModulus

  var x{.noInit.}: Fp[BLS12_381]
  x.fromBig(t)

  let onCurve = dst.raw.trySetFromCoordX(x)
  if not(bool onCurve):
    return cttBLS_PointNotOnCurve

  let isLexicographicallyLargest = dst.raw.y.toBig() >= Fp[BLS12_381].getPrimePlus1div2()
  let srcIsLargest = SecretBool((src[0] shr 5) and byte 1)
  dst.raw.y.cneg(isLexicographicallyLargest xor srcIsLargest)

func deserialize_pubkey_compressed*(dst: var PublicKey, src: array[48, byte]): CttBLSStatus {.exportc: ffi_prefix & "$1".} =
  ## Deserialize a public_key in compressed (Zcash) format
  ## This also validates the public key.
  ##
  ## Returns cttBLS_Success if successful

  result = deserialize_pubkey_compressed_unchecked(dst, src)
  if result != cttBLS_Success:
    return result

  if not(bool dst.raw.isInSubgroup()):
    return cttBLS_PointNotInSubgroup

func deserialize_signature_compressed_unchecked*(dst: var Signature, src: array[96, byte]): CttBLSStatus {.exportc: ffi_prefix & "$1".} =
  ## Deserialize a signature in compressed (Zcash) format.
  ##
  ## Warning ⚠:
  ##   This procedure skips the very expensive subgroup checks.
  ##   Not checking subgroup exposes a protocol to small subgroup attacks.
  ##
  ## Returns cttBLS_Success if successful

  # src must have the compressed flag
  if (src[0] and byte 0b10000000) == byte 0:
    return cttBLS_InvalidEncoding

  # if infinity, src must be all zeros
  if (src[0] and byte 0b01000000) != 0:
    if (src[0] and byte 0b00111111) != 0: # Check all the remaining bytes in MSB
      return cttBLS_InvalidEncoding
    for i in 1 ..< src.len:
      if src[i] != byte 0:
        return cttBLS_InvalidEncoding
    dst.raw.setInf()
    return cttBLS_PointAtInfinity

  # General case
  var t{.noInit.}: matchingBigInt(BLS12_381)
  t.unmarshal(src.toOpenArray(0, 48-1), bigEndian)
  t.limbs[t.limbs.len-1] = t.limbs[t.limbs.len-1] and (MaxWord shr 3) # The first 3 bytes contain metadata to mask out

  if bool(t >= BLS12_381.Mod()):
    return cttBLS_CoordinateGreaterOrEqualThanModulus

  var x{.noInit.}: Fp2[BLS12_381]
  x.c1.fromBig(t)

  t.unmarshal(src.toOpenArray(48, 96-1), bigEndian)
  if bool(t >= BLS12_381.Mod()):
    return cttBLS_CoordinateGreaterOrEqualThanModulus

  x.c0.fromBig(t)

  let onCurve = dst.raw.trySetFromCoordX(x)
  if not(bool onCurve):
    return cttBLS_PointNotOnCurve

  let isLexicographicallyLargest =
    if dst.raw.y.c1.isZero().bool():
      dst.raw.y.c0.toBig() >= Fp[BLS12_381].getPrimePlus1div2()
    else:
      dst.raw.y.c1.toBig() >= Fp[BLS12_381].getPrimePlus1div2()

  let srcIsLargest = SecretBool((src[0] shr 5) and byte 1)
  dst.raw.y.cneg(isLexicographicallyLargest xor srcIsLargest)

func deserialize_signature_compressed*(dst: var Signature, src: array[96, byte]): CttBLSStatus {.exportc: ffi_prefix & "$1".} =
  ## Deserialize a public_key in compressed (Zcash) format
  ##
  ## Returns cttBLS_Success if successful

  result = deserialize_signature_compressed_unchecked(dst, src)
  if result != cttBLS_Success:
    return result

  if not(bool dst.raw.isInSubgroup()):
    return cttBLS_PointNotInSubgroup

# BLS Signatures
# ------------------------------------------------------------------------------------------------

func derive_pubkey*(public_key: var PublicKey, secret_key: SecretKey): CttBLSStatus {.exportc: ffi_prefix & "$1".} =
  ## Derive the public key matching with a secret key
  ##
  ## Secret protection:
  ## - A valid secret key will only leak that it is valid.
  ## - An invalid secret key will leak whether it's all zero or larger than the curve order.
  let status = validate_seckey(secret_key)
  if status != cttBLS_Success:
    return status

  let ok = public_key.raw.derivePubkey(secret_key.raw)
  if not ok:
    # This is unreachable since validate_seckey would have caught those
    return cttBLS_InvalidEncoding
  return cttBLS_Success

func sign*(signature: var Signature, secret_key: SecretKey, message: openArray[byte]): CttBLSStatus {.exportc: ffi_prefix & "$1", genCharAPI.} =
  ## Produce a signature for the message under the specified secret key
  ## Signature is on BLS12-381 G2 (and public key on G1)
  ##
  ## For message domain separation purpose, the tag is `BLS_SIG_BLS12381G2_XMD:SHA-256_SSWU_RO_POP_`
  ##
  ## Input:
  ## - A secret key
  ## - A message
  ##
  ## Output:
  ## - `signature` is overwritten with `message` signed with `secretKey`
  ##   with the scheme
  ## - A status code indicating success or if the secret key is invalid.
  ##
  ## Secret protection:
  ## - A valid secret key will only leak that it is valid.
  ## - An invalid secret key will leak whether it's all zero or larger than the curve order.
  let status = validate_seckey(secret_key)
  if status != cttBLS_Success:
    signature.raw.setInf()
    return status

  coreSign(signature.raw, secretKey.raw, message, sha256, 128, augmentation = "", DST)
  return cttBLS_Success

func verify*(public_key: PublicKey, message: openArray[byte], signature: Signature): CttBLSStatus {.exportc: ffi_prefix & "$1", genCharAPI.} =
  ## Check that a signature is valid for a message
  ## under the provided public key.
  ## returns `true` if the signature is valid, `false` otherwise.
  ##
  ## For message domain separation purpose, the tag is `BLS_SIG_BLS12381G2_XMD:SHA-256_SSWU_RO_POP_`
  ##
  ## Input:
  ## - A public key initialized by one of the key derivation or deserialization procedure.
  ##   Or validated via validate_pubkey
  ## - A message
  ## - A signature initialized by one of the key derivation or deserialization procedure.
  ##   Or validated via validate_signature
  ##
  ## Output:
  ## - a status code with verification success if signature is valid
  ##   or indicating verification failure
  ##
  ## In particular, the public key and signature are assumed to be on curve and subgroup-checked.

  # Deal with cases were pubkey or signature were mistakenly zero-init, due to a generic aggregation tentative for example
  if bool(public_key.raw.isInf() or signature.raw.isInf()):
    return cttBLS_PointAtInfinity

  let verified = coreVerify(public_key.raw, message, signature.raw, sha256, 128, augmentation = "", DST)
  if verified:
    return cttBLS_Success
  return cttBLS_VerificationFailure

template unwrap[T: PublicKey|Signature](elems: openArray[T]): auto =
  # Unwrap collection of high-level type into collection of low-level type
  toOpenArray(cast[ptr UncheckedArray[typeof elems[0].raw]](elems[0].raw.unsafeAddr), elems.low, elems.high)

func aggregate_pubkeys_unstable_api*(aggregate_pubkey: var PublicKey, pubkeys: openArray[PublicKey]) {.exportc: ffi_prefix & "$1".} =
  ## Aggregate public keys into one
  ## The individual public keys are assumed to be validated, either during deserialization
  ## or by validate_pubkeys
  #
  # TODO: Return a bool or status code or nothing?
  if pubkeys.len == 0:
    aggregate_pubkey.raw.setInf()
    return
  aggregate_pubkey.raw.aggregate(pubkeys.unwrap())

func aggregate_signatures_unstable_api*(aggregate_sig: var Signature, signatures: openArray[Signature]) {.exportc: ffi_prefix & "$1".} =
  ## Aggregate signatures into one
  ## The individual signatures are assumed to be validated, either during deserialization
  ## or by validate_signature
  #
  # TODO: Return a bool or status code or nothing?
  if signatures.len == 0:
    aggregate_sig.raw.setInf()
    return
  aggregate_sig.raw.aggregate(signatures.unwrap())

func fast_aggregate_verify*(pubkeys: openArray[PublicKey], message: openArray[byte], aggregate_sig: Signature): CttBLSStatus {.exportc: ffi_prefix & "$1", genCharAPI.} =
  ## Check that a signature is valid for a message
  ## under the aggregate of provided public keys.
  ## returns `true` if the signature is valid, `false` otherwise.
  ##
  ## For message domain separation purpose, the tag is `BLS_SIG_BLS12381G2_XMD:SHA-256_SSWU_RO_POP_`
  ##
  ## Input:
  ## - Public keys initialized by one of the key derivation or deserialization procedure.
  ##   Or validated via validate_pubkey
  ## - A message
  ## - A signature initialized by one of the key derivation or deserialization procedure.
  ##   Or validated via validate_signature
  ##
  ## In particular, the public keys and signature are assumed to be on curve subgroup checked.

  if pubkeys.len == 0:
    # IETF spec precondition
    return cttBLS_ZeroLengthAggregation

  # Deal with cases were pubkey or signature were mistakenly zero-init, due to a generic aggregation tentative for example
  if aggregate_sig.raw.isInf().bool:
    return cttBLS_PointAtInfinity

  for i in 0 ..< pubkeys.len:
    if pubkeys[i].raw.isInf().bool:
      return cttBLS_PointAtInfinity

  let verified = fastAggregateVerify(
    pubkeys.unwrap(),
    message, aggregate_sig.raw,
    sha256, 128, DST)
  if verified:
    return cttBLS_Success
  return cttBLS_VerificationFailure

func aggregate_verify*[Msg](pubkeys: openArray[PublicKey], messages: openArray[Msg], aggregate_sig: Signature): CttBLSStatus {.exportc: ffi_prefix & "$1".} =
  ## Verify the aggregated signature of multiple (pubkey, message) pairs
  ## returns `true` if the signature is valid, `false` otherwise.
  ##
  ## For message domain separation purpose, the tag is `BLS_SIG_BLS12381G2_XMD:SHA-256_SSWU_RO_POP_`
  ##
  ## Input:
  ## - Public keys initialized by one of the key derivation or deserialization procedure.
  ##   Or validated via validate_pubkey
  ## - Messages
  ## - a signature initialized by one of the key derivation or deserialization procedure.
  ##   Or validated via validate_signature
  ##
  ## In particular, the public keys and signature are assumed to be on curve subgroup checked.
  ##
  ## To avoid splitting zeros and rogue keys attack:
  ## 1. Public keys signing the same message MUST be aggregated and checked for 0 before calling this function.
  ## 2. Augmentation or Proof of possessions must used for each public keys.

  if pubkeys.len == 0:
    # IETF spec precondition
    return cttBLS_ZeroLengthAggregation

  if pubkeys.len != messages.len:
    return cttBLS_InconsistentLengthsOfInputs

  # Deal with cases were pubkey or signature were mistakenly zero-init, due to a generic aggregation tentative for example
  if aggregate_sig.raw.isInf().bool:
    return cttBLS_PointAtInfinity

  for i in 0 ..< pubkeys.len:
    if pubkeys[i].raw.isInf().bool:
      return cttBLS_PointAtInfinity

  let verified = aggregateVerify(
    pubkeys.unwrap(),
    messages, aggregate_sig.raw,
    sha256, 128, DST)
  if verified:
    return cttBLS_Success
  return cttBLS_VerificationFailure

func batch_verify*[Msg](pubkeys: openArray[PublicKey], messages: openarray[Msg], signatures: openArray[Signature], secureRandomBytes: array[32, byte]): CttBLSStatus {.exportc: ffi_prefix & "$1".} =
  ## Verify that all (pubkey, message, signature) triplets are valid
  ## returns `true` if all signatures are valid, `false` if at least one is invalid.
  ##
  ## For message domain separation purpose, the tag is `BLS_SIG_BLS12381G2_XMD:SHA-256_SSWU_RO_POP_`
  ##
  ## Input:
  ## - Public keys initialized by one of the key derivation or deserialization procedure.
  ##   Or validated via validate_pubkey
  ## - Messages
  ## - Signatures initialized by one of the key derivation or deserialization procedure.
  ##   Or validated via validate_signature
  ##
  ## In particular, the public keys and signature are assumed to be on curve subgroup checked.
  ##
  ## To avoid splitting zeros and rogue keys attack:
  ## 1. Cryptographically-secure random bytes must be provided.
  ## 2. Augmentation or Proof of possessions must used for each public keys.
  ##
  ## The secureRandomBytes will serve as input not under the attacker control to foil potential splitting zeros inputs.
  ## The scheme assumes that the attacker cannot
  ## resubmit 2^64 times forged (publickey, message, signature) triplets
  ## against the same `secureRandomBytes`

  if pubkeys.len == 0:
    # IETF spec precondition
    return cttBLS_ZeroLengthAggregation

  if pubkeys.len != messages.len or  pubkeys.len != signatures.len:
    return cttBLS_InconsistentLengthsOfInputs

  # Deal with cases were pubkey or signature were mistakenly zero-init, due to a generic aggregation tentative for example
  for i in 0 ..< pubkeys.len:
    if pubkeys[i].raw.isInf().bool:
      return cttBLS_PointAtInfinity

  for i in 0 ..< signatures.len:
    if signatures[i].raw.isInf().bool:
      return cttBLS_PointAtInfinity

  let verified = batchVerify(
    pubkeys.unwrap(),
    messages,
    signatures.unwrap(),
    sha256, 128, DST, secureRandomBytes)
  if verified:
    return cttBLS_Success
  return cttBLS_VerificationFailure