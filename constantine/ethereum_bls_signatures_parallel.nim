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
##                     Parallel edition
##
## ############################################################

when not compileOption("threads"):
  {.error: "This requires --threads:on compilation flag".}

# Reexport the serial API
import ./ethereum_bls_signatures {.all.}
export ethereum_bls_signatures

import
  std/importutils,
  ./zoo_exports,
  ./platforms/views,
  ./threadpool/threadpool,
  ./signatures/bls_signatures_parallel

# No exceptions allowed in core cryptographic operations
{.push raises: [].}
{.push checks: off.}

# C FFI
proc batch_verify_parallel*[Msg](
        tp: Threadpool,
        pubkeys: ptr UncheckedArray[PublicKey],
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

  privateAccess(PublicKey)
  privateAccess(Signature)

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

  let verified = tp.batchVerify_parallel(
    pubkeys.toOpenArray(len).unwrap(),
    messages,
    signatures.toOpenArray(len).unwrap(),
    sha256, 128, DomainSeparationTag, secureRandomBytes)
  if verified:
    return cttBLS_Success
  return cttBLS_VerificationFailure

# Nim
proc batch_verify_parallel*[Msg](
        tp: Threadpool,
        pubkeys: openArray[PublicKey],
        messages: openarray[Msg],
        signatures: openArray[Signature],
        secureRandomBytes: array[32, byte]): CttBLSStatus =
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

  privateAccess(PublicKey)
  privateAccess(Signature)

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

  let verified = tp.batchVerify_parallel(
    pubkeys.unwrap(),
    messages,
    signatures.unwrap(),
    sha256, 128, DomainSeparationTag, secureRandomBytes)
  if verified:
    return cttBLS_Success
  return cttBLS_VerificationFailure