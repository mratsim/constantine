# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

# ############################################################
#
#         CryptoHash Generator for Challenge Scalars
#
# ############################################################

import
  ./eth_verkle_constants,
  ../platforms/[primitives,abstractions],
  ../serialization/endians,
  ../math/config/[type_ff, curves],
  ../math/io/io_bigints,
  ../math/arithmetic/limbs_montgomery,
  ../math/[extension_fields, arithmetic],
  ../math/elliptic/ec_twistededwards_projective,
  ../hashes,
  ../serialization/[codecs_banderwagon,codecs_status_codes]

func newTranscriptGen*(res: var CryptoHash, label: openArray[byte]) =
  res.init()
  res.update(label)

func messageAppend*(res: var CryptoHash, message: openArray[byte], label: openArray[byte]) =
  res.update(label)
  res.update(message)

func messageAppend_u64*(res: var CryptoHash, label: openArray[byte], num_value: uint64) = 
  res.update(label)
  res.update(num_value.toBytes(bigEndian))

func domainSeparator*(res: var CryptoHash, label: openArray[byte]) =
  res.update(label)

func pointAppend*(res: var CryptoHash, label: openArray[byte], point: EC_P) =
  var bytes {.noInit.}: array[32, byte]
  let stat = bytes.serialize(point) 
  doAssert stat == cttCodecEcc_Success, "Serialization Failure!"
  res.messageAppend(bytes, label)

func scalarAppend*(res: var CryptoHash, label: openArray[byte], scalar: matchingOrderBigInt(Banderwagon)) =
  var bytes {.noInit.}: array[32, byte]

  let stat = bytes.serialize_scalar(scalar, littleEndian)
  doAssert stat == cttCodecScalar_Success, "Issues with marshalling!"
  res.messageAppend(bytes, label)

func fromVerkleDigest(dst: var Fr[Banderwagon], src: array[32, byte]) : bool =
  ## The input src byte array that we get here is 32 bytes
  ## Which can be safely stored in a 256 BigInt
  ## Now incase of the scalar overflowing the last 3-bits
  ## it is converted from its natural representation
  ## to the Montgomery residue form
  ##
  ## `mres` is overwritten. It's bitlength must be properly set before calling this procedure.
  ##
  ## Caller must take care of properly switching between
  ## the natural and montgomery domain.
  ## 
  ## This is a function that can be called for added safety instead using the
  ## `fromBig()` sequence of function calls in case of Banderwagon scalars
  var res : bool = false
  var scalar {.noInit.}: BigInt[256]
  scalar.unmarshal(src, littleEndian)

  getMont(dst.mres.limbs, scalar.limbs,
          Fr[Bandersnatch].fieldMod().limbs,
          Fr[Bandersnatch].getR2modP().limbs,
          Fr[Bandersnatch].getNegInvModWord(),
          Fr[Bandersnatch].getSpareBits())
  res = true
  return res

func generateChallengeScalar*(challenge: var matchingOrderBigInt(Banderwagon), transcript: var CryptoHash, label: openArray[byte]) =
  # Generating Challenge Scalars based on the Fiat Shamir method
  transcript.domainSeparator(label)

  var hash {.noInit.} : array[32, byte]
  # Finalise the transcript state into a hash
  transcript.finish(hash)

  var interim_challenge {.noInit.}: Fr[Banderwagon]
  # Safely deserialize into the Montgomery residue form
  let stat = interim_challenge.fromVerkleDigest(hash)
  doAssert stat == true, "Issues with Verkle Digest!"

  # Reset the Transcript state
  transcript.clear()
  challenge = interim_challenge.toBig()

  # Append the challenge into the resetted transcript
  transcript.scalarAppend(label, challenge)
  