# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
    ../math/[ec_shortweierstrass, pairings],
    ../math/elliptic/ec_shortweierstrass_batch_ops,
    ../math/constants/zoo_generators,
    ../hash_to_curve/hash_to_curve,
    ../hashes

# ############################################################
#
#                   BLS Signatures
#
# ############################################################

# This module implements generic BLS signatures
# https://datatracker.ietf.org/doc/html/draft-irtf-cfrg-bls-signature-04
# https://github.com/cfrg/draft-irtf-cfrg-bls-signature
#
# We use generic shortnames SecKey, PubKey, Sig
# so tat the algorithms fit whether Pubkey and Sig are on G1 or G2
# Actual protocols should expose publicly the full names SecretKey, PublicKey and Signature


{.push inline.} # inline in the main public procs
{.push raises: [].} # No exceptions allowed in core cryptographic operations


func derivePubkey*[Pubkey, SecKey](pubkey: var Pubkey, seckey: SecKey): bool =
  ## Generates the public key associated with the input secret key.
  ##
  ## Returns:
  ## - false is secret key is invalid (SK == 0 or >= BLS12-381 curve order),
  ##   true otherwise
  ##   By construction no public API should ever instantiate
  ##   an invalid secretkey in the first place.  
  const Group = Pubkey.G
  type Field = Pubkey.F
  const EC = Field.C

  if seckey.isZero().bool:
    return false
  if bool(seckey >= EC.getCurveOrder()):
    return false

  var pk {.noInit.}: ECP_ShortW_Jac[Field, Group]
  pk.fromAffine(EC.getGenerator($Group))
  pk.scalarMul(seckey)
  pubkey.affine(pk)
  return true

func coreSign*[B1, B2, B3: byte|char, Sig, SecKey](
    signature: var Sig,
    secretKey: SecKey,
    message: openarray[B1],
    H: type CryptoHash,
    k: static int,
    augmentation: openarray[B2],
    domainSepTag: openarray[B3]) =
  ## Computes a signature for the message from the specified secret key.
  ## 
  ## Output:
  ## - `signature` is overwritten with `message` signed with `secretKey`
  ## 
  ## Inputs:
  ## - `Hash` a cryptographic hash function.
  ##   - `Hash` MAY be a Merkle-Damgaard hash function like SHA-2
  ##   - `Hash` MAY be a sponge-based hash function like SHA-3 or BLAKE2
  ##   - Otherwise, H MUST be a hash function that has been proved
  ##    indifferentiable from a random oracle [MRH04] under a reasonable
  ##    cryptographic assumption.
  ## - k the security parameter of the suite in bits (for example 128)
  ## - `output`, an elliptic curve point that will be overwritten.
  ## - `augmentation`, an optional augmentation to the message. This will be prepended,
  ##   prior to hashing.
  ##   This is used for building the "message augmentation" variant of BLS signatures
  ##   https://tools.ietf.org/html/draft-irtf-cfrg-bls-signature-04#section-3.2
  ##   which requires `CoreSign(SK, PK || message)`
  ##   and `CoreVerify(PK, PK || message, signature)`
  ## - `message` is the message to hash
  ## - `domainSepTag` is the protocol domain separation tag (DST).
  
  type ECP_Jac = ECP_ShortW_Jac[Sig.F, Sig.G]

  var sig {.noInit.}: ECP_Jac
  H.hashToCurve(k, sig, augmentation, message, domainSepTag)
  sig.scalarMul(secretKey)

  signature.affine(sig)

func coreVerify*[B1, B2, B3: byte|char, Pubkey, Sig](
    pubkey: Pubkey,
    message: openarray[B1],
    signature: Sig,
    H: type CryptoHash,
    k: static int,
    augmentation: openarray[B2],
    domainSepTag: openarray[B3]): bool =
  ## Check that a signature is valid
  ## for a message under the provided public key
  ## This assumes that the PublicKey and Signatures
  ## have been pre-checked for non-infinity and being in the correct subgroup
  ## (likely on deserialization)
  var Q {.noInit.}: ECP_ShortW_Aff[Sig.F, Sig.G]
  var negG {.noInit.}: ECP_ShortW_Aff[Pubkey.F, Pubkey.G]

  negG.neg(Pubkey.F.C.getGenerator($Pubkey.G))
  H.hashToCurve(k, Q, augmentation, message, domainSepTag)

  when Sig.F.C.getEmbeddingDegree() == 12:
    var gt {.noInit.}: Fp12[Sig.F.C]
  else:
    {.error: "Not implemented: signature on k=" & $Sig.F.C.getEmbeddingDegree() & " for curve " & $$Sig.F.C.}

  # e(PK, H(msg))*e(sig, -G) == 1
  when Sig.G == G2:
    pairing(gt, [pubkey, negG], [Q, signature])
  else:
    pairing(gt, [Q, signature], [pubkey, negG])

  return gt.isOne().bool()

# ############################################################
#
#                   Aggregate verification
#
# ############################################################
#
# Terminology:
#
# - fastAggregateVerify:
#   Verify the aggregate of multiple signatures by multiple pubkeys
#   on the same message.
#
# - aggregateVerify:
#   Verify the aggregate of multiple signatures by multiple (pubkey, message) pairs
#
# - batchVerify:
#   Verify that all (pubkey, message, signature) triplets are valid

func fastAggregateVerify*[B1, B2, B3: byte|char, Pubkey, Sig](
    pubkeys: openArray[Pubkey],
    message: openarray[B1],
    signature: Sig,
    H: type CryptoHash,
    k: static int,
    augmentation: openarray[B2],
    domainSepTag: openarray[B3]): bool =
  ## Verify the aggregate of multiple signatures by multiple pubkeys
  ## on the same message.
  
  var accum {.noinit.}: ECP_ShortW_Jac[Pubkey.F, Pubkey.G]
  accum.sum_batch_vartime(pubkeys)

  var aggPubkey {.noinit.}: Pubkey
  aggPubkey.affine(accum)

  aggPubkey.coreVerify(message, signature, H, k, augmentation, domainSepTag)