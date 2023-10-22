# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

## ############################################################
##
##              BLS Signatures on for Ethereum
##
## ############################################################
##
## This module implements BLS Signatures (Boneh-Lynn-Schacham)
## on top of the BLS12-381 curve (Barreto-Lynn-Scott) G2.
## for the Ethereum blockchain.
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
## Specs:
## - https://github.com/ethereum/consensus-specs/blob/v1.2.0/specs/phase0/beacon-chain.md#bls-signatures
## - https://github.com/ethereum/consensus-specs/blob/v1.2.0/specs/altair/bls.md
## - https://www.ietf.org/archive/id/draft-irtf-cfrg-bls-signature-05.html
##
## Test vectors:
## - https://github.com/ethereum/bls12-381-tests
##
## The Ethereum blockchain uses the proof-of-possession scheme (PoP).
## Each public key is associated with a deposit proof required to participate
## in the blockchain consensus protocol, hence PopProve and PopVerify
## as defined in the IETF spec are not needed.

const prefix_ffi = "ctt_eth_bls_"

# Dependencies exports for C FFI
# ------------------------------------------------------------------------------------------------

import ./zoo_exports

# static:
#   # Export SHA256 routines with a protocol specific prefix
#   # This exports sha256.init(), sha256.update(), sha256.finish() and sha256.clear()
#   prefix_sha256 = prefix_ffi & "sha256_"

import hashes
export hashes # generic sandwich on sha256

# Imports
# ------------------------------------------------------------------------------------------------

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
    signatures/bls_signatures,
    serialization/codecs_status_codes,
    serialization/codecs_bls12_381

export
  abstractions, # generic sandwich on SecretBool and SecretBool in Jacobian sumImpl
  curves, # generic sandwich on matchingBigInt
  extension_fields, # generic sandwich on extension field access
  ec_shortweierstrass, # generic sandwich on affine

  CttCodecScalarStatus,
  CttCodecEccStatus

const DomainSeparationTag = asBytes"BLS_SIG_BLS12381G2_XMD:SHA-256_SSWU_RO_POP_"

# Protocol types
# ------------------------------------------------------------------------------------------------

{.checks: off.} # No exceptions allowed in core cryptographic operations

type
  SecretKey* {.byref, exportc: prefix_ffi & "seckey".} = object
    ## A BLS12_381 secret key
    raw: matchingOrderBigInt(BLS12_381)

  PublicKey* {.byref, exportc: prefix_ffi & "pubkey".} = object
    ## A BLS12_381 public key for BLS signature schemes with public keys on G1 and signatures on G2
    raw: ECP_ShortW_Aff[Fp[BLS12_381], G1]

  Signature* {.byref, exportc: prefix_ffi & "signature".} = object
    ## A BLS12_381 signature for BLS signature schemes with public keys on G1 and signatures on G2
    raw: ECP_ShortW_Aff[Fp2[BLS12_381], G2]

  CttBLSStatus* = enum
    cttBLS_Success
    cttBLS_VerificationFailure
    cttBLS_PointAtInfinity
    cttBLS_ZeroLengthAggregation
    cttBLS_InconsistentLengthsOfInputs

# Comparisons
# ------------------------------------------------------------------------------------------------

func pubkey_is_zero*(pubkey: PublicKey): bool {.libPrefix: prefix_ffi.} =
  ## Returns true if input is 0
  bool(pubkey.raw.isInf())

func signature_is_zero*(sig: Signature): bool {.libPrefix: prefix_ffi.} =
  ## Returns true if input is 0
  bool(sig.raw.isInf())

func pubkeys_are_equal*(a, b: PublicKey): bool {.libPrefix: prefix_ffi.} =
  ## Returns true if inputs are equal
  bool(a.raw == b.raw)

func signatures_are_equal*(a, b: Signature): bool {.libPrefix: prefix_ffi.} =
  ## Returns true if inputs are equal
  bool(a.raw == b.raw)

# Input validation
# ------------------------------------------------------------------------------------------------

func validate_seckey*(secret_key: SecretKey): CttCodecScalarStatus {.libPrefix: prefix_ffi.} =
  ## Validate the secret key.
  ## Regarding timing attacks, this will leak timing information only if the key is invalid.
  ## Namely, the secret key is 0 or the secret key is too large.
  return secret_key.raw.validate_scalar()

func validate_pubkey*(public_key: PublicKey): CttCodecEccStatus {.libPrefix: prefix_ffi.} =
  ## Validate the public key.
  ## This is an expensive operation that can be cached
  return public_key.raw.validate_g1()

func validate_signature*(signature: Signature): CttCodecEccStatus {.libPrefix: prefix_ffi.} =
  ## Validate the signature.
  ## This is an expensive operation that can be cached
  return signature.raw.validate_g2()

# Codecs
# ------------------------------------------------------------------------------------------------

func serialize_seckey*(dst: var array[32, byte], secret_key: SecretKey): CttCodecScalarStatus {.libPrefix: prefix_ffi.} =
  ## Serialize a secret key
  ## Returns cttCodecScalar_Success if successful
  return dst.serialize_scalar(secret_key.raw)

func serialize_pubkey_compressed*(dst: var array[48, byte], public_key: PublicKey): CttCodecEccStatus {.libPrefix: prefix_ffi.} =
  ## Serialize a public key in compressed (Zcash) format
  ##
  ## Returns cttCodecEcc_Success if successful
  return dst.serialize_g1_compressed(public_key.raw)

func serialize_signature_compressed*(dst: var array[96, byte], signature: Signature): CttCodecEccStatus {.libPrefix: prefix_ffi.} =
  ## Serialize a signature in compressed (Zcash) format
  ##
  ## Returns cttBLS_Success if successful
  return dst.serialize_g2_compressed(signature.raw)

func deserialize_seckey*(dst: var SecretKey, src: array[32, byte]): CttCodecScalarStatus {.libPrefix: prefix_ffi.} =
  ## Deserialize a secret key
  ## This also validates the secret key.
  ##
  ## This is protected against side-channel unless your key is invalid.
  ## In that case it will like whether it's all zeros or larger than the curve order.
  return dst.raw.deserialize_scalar(src)

func deserialize_pubkey_compressed_unchecked*(dst: var PublicKey, src: array[48, byte]): CttCodecEccStatus {.libPrefix: prefix_ffi.} =
  ## Deserialize a public_key in compressed (Zcash) format.
  ##
  ## Warning ⚠:
  ##   This procedure skips the very expensive subgroup checks.
  ##   Not checking subgroup exposes a protocol to small subgroup attacks.
  ##
  ## Returns cttCodecEcc_Success if successful
  return dst.raw.deserialize_g1_compressed_unchecked(src)

func deserialize_pubkey_compressed*(dst: var PublicKey, src: array[48, byte]): CttCodecEccStatus {.libPrefix: prefix_ffi.} =
  ## Deserialize a public_key in compressed (Zcash) format
  ## This also validates the public key.
  ##
  ## Returns cttCodecEcc_Success if successful
  return dst.raw.deserialize_g1_compressed(src)

func deserialize_signature_compressed_unchecked*(dst: var Signature, src: array[96, byte]): CttCodecEccStatus {.libPrefix: prefix_ffi.} =
  ## Deserialize a signature in compressed (Zcash) format.
  ##
  ## Warning ⚠:
  ##   This procedure skips the very expensive subgroup checks.
  ##   Not checking subgroup exposes a protocol to small subgroup attacks.
  ##
  ## Returns cttCodecEcc_Success if successful
  return dst.raw.deserialize_g2_compressed_unchecked(src)

func deserialize_signature_compressed*(dst: var Signature, src: array[96, byte]): CttCodecEccStatus {.libPrefix: prefix_ffi.} =
  ## Deserialize a public_key in compressed (Zcash) format
  ##
  ## Returns cttCodecEcc_Success if successful
  return dst.raw.deserialize_g2_compressed(src)

# BLS Signatures
# ------------------------------------------------------------------------------------------------

func derive_pubkey*(public_key: var PublicKey, secret_key: SecretKey) {.libPrefix: prefix_ffi.} =
  ## Derive the public key matching with a secret key
  ##
  ## The secret_key MUST be validated
  public_key.raw.derivePubkey(secret_key.raw)

func sign*(signature: var Signature, secret_key: SecretKey, message: openArray[byte]) {.libPrefix: prefix_ffi, genCharAPI.} =
  ## Produce a signature for the message under the specified secret key
  ## Signature is on BLS12-381 G2 (and public key on G1)
  ##
  ## For message domain separation purpose, the tag is `BLS_SIG_BLS12381G2_XMD:SHA-256_SSWU_RO_POP_`
  ##
  ## Input:
  ## - A secret key
  ## - A message
  ##
  ## The secret_key MUST be validated
  ##
  ## Output:
  ## - `signature` is overwritten with `message` signed with `secretKey`
  ##   with the scheme
  coreSign(signature.raw, secretKey.raw, message, sha256, 128, augmentation = "", DomainSeparationTag)

func verify*(public_key: PublicKey, message: openArray[byte], signature: Signature): CttBLSStatus {.libPrefix: prefix_ffi, genCharAPI.} =
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

  let verified = coreVerify(public_key.raw, message, signature.raw, sha256, 128, augmentation = "", DomainSeparationTag)
  if verified:
    return cttBLS_Success
  return cttBLS_VerificationFailure

template unwrap[T: PublicKey|Signature](elems: openArray[T]): auto =
  # Unwrap collection of high-level type into collection of low-level type
  toOpenArray(cast[ptr UncheckedArray[typeof elems[0].raw]](elems[0].raw.unsafeAddr), elems.low, elems.high)

func aggregate_pubkeys_unstable_api*(aggregate_pubkey: var PublicKey, pubkeys: openArray[PublicKey]) =
  ## Aggregate public keys into one
  ## The individual public keys are assumed to be validated, either during deserialization
  ## or by validate_pubkeys
  #
  # TODO: Return a bool or status code or nothing?
  if pubkeys.len == 0:
    aggregate_pubkey.raw.setInf()
    return
  aggregate_pubkey.raw.aggregate(pubkeys.unwrap())

func aggregate_signatures_unstable_api*(aggregate_sig: var Signature, signatures: openArray[Signature]) =
  ## Aggregate signatures into one
  ## The individual signatures are assumed to be validated, either during deserialization
  ## or by validate_signature
  #
  # TODO: Return a bool or status code or nothing?
  if signatures.len == 0:
    aggregate_sig.raw.setInf()
    return
  aggregate_sig.raw.aggregate(signatures.unwrap())

func fast_aggregate_verify*(pubkeys: openArray[PublicKey], message: openArray[byte], aggregate_sig: Signature): CttBLSStatus {.libPrefix: prefix_ffi, genCharAPI.} =
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
    sha256, 128, DomainSeparationTag)
  if verified:
    return cttBLS_Success
  return cttBLS_VerificationFailure

# C FFI
func aggregate_verify*(pubkeys: ptr UncheckedArray[PublicKey],
                       messages: ptr UncheckedArray[View[byte]],
                       len: int,
                       aggregate_sig: Signature): CttBLSStatus {.libPrefix: prefix_ffi.} =
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

  if len == 0:
    # IETF spec precondition
    return cttBLS_ZeroLengthAggregation

  # Deal with cases were pubkey or signature were mistakenly zero-init, due to a generic aggregation tentative for example
  if aggregate_sig.raw.isInf().bool:
    return cttBLS_PointAtInfinity

  for i in 0 ..< len:
    if pubkeys[i].raw.isInf().bool:
      return cttBLS_PointAtInfinity

  let verified = aggregateVerify(
    pubkeys.toOpenArray(len).unwrap(),
    messages.toOpenArray(len),
    aggregate_sig.raw,
    sha256, 128, DomainSeparationTag)
  if verified:
    return cttBLS_Success
  return cttBLS_VerificationFailure

# Nim
func aggregate_verify*[Msg](pubkeys: openArray[PublicKey], messages: openArray[Msg], aggregate_sig: Signature): CttBLSStatus =
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
    sha256, 128, DomainSeparationTag)
  if verified:
    return cttBLS_Success
  return cttBLS_VerificationFailure

# C FFI
func batch_verify*[Msg](pubkeys: ptr UncheckedArray[PublicKey],
                        messages: ptr UncheckedArray[View[byte]],
                        signatures: ptr UncheckedArray[Signature],
                        len: int,
                        secureRandomBytes: array[32, byte]): CttBLSStatus {.libPrefix: prefix_ffi.} =
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

  if len == 0:
    # IETF spec precondition
    return cttBLS_ZeroLengthAggregation

  # Deal with cases were pubkey or signature were mistakenly zero-init, due to a generic aggregation tentative for example
  for i in 0 ..< len:
    if pubkeys[i].raw.isInf().bool:
      return cttBLS_PointAtInfinity

  for i in 0 ..< len:
    if signatures[i].raw.isInf().bool:
      return cttBLS_PointAtInfinity

  let verified = batchVerify(
    pubkeys.toOpenArray(len).unwrap(),
    messages,
    signatures.toOpenArray(len).unwrap(),
    sha256, 128, DomainSeparationTag, secureRandomBytes)
  if verified:
    return cttBLS_Success
  return cttBLS_VerificationFailure

# Nim
func batch_verify*[Msg](pubkeys: openArray[PublicKey], messages: openarray[Msg], signatures: openArray[Signature], secureRandomBytes: array[32, byte]): CttBLSStatus =
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
    sha256, 128, DomainSeparationTag, secureRandomBytes)
  if verified:
    return cttBLS_Success
  return cttBLS_VerificationFailure