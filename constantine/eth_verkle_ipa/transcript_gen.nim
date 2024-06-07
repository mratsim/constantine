# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

# ############################################################
#
#             Generator for Challenge Scalars
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

  let status {.used.} = bytes.serialize(point)
  debug: doAssert status == cttCodecEcc_Success, "transcript_gen.pointAppend: Serialization Failure!"
  res.messageAppend(bytes, label)

func scalarAppend*(res: var CryptoHash, label: openArray[byte], scalar: matchingOrderBigInt(Banderwagon)) =
  var bytes {.noInit.}: array[32, byte]

  let status {.used.} = bytes.serialize_scalar(scalar, littleEndian)

  debug: doAssert status == cttCodecScalar_Success, "transcript_gen.scalarAppend: Serialization Failure!"
  res.messageAppend(bytes, label)

func generateChallengeScalar*(challenge: var matchingOrderBigInt(Banderwagon), transcript: var CryptoHash, label: openArray[byte]) =
  # Generating Challenge Scalars based on the Fiat Shamir method
  transcript.domainSeparator(label)

  var hash {.noInit.}: array[32, byte]
  # Finalise the transcript state into a hash
  transcript.finish(hash)

  var interim_challenge {.noInit.}: Fr[Banderwagon]
  # Safely deserialize into the Montgomery residue form
  let stat {.used.}  = interim_challenge.make_scalar_mod_order(hash, littleEndian)
  debug: doAssert stat, "transcript_gen.generateChallengeScalar: Unexpected failure"

  # Reset the Transcript state
  transcript.init()
  challenge = interim_challenge.toBig()

  # Append the challenge into the resetted transcript
  transcript.scalarAppend(label, challenge)
