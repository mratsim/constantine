# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

# ############################################################
#
#         sha256 Generator for Challenge Scalars
#
# ############################################################

import
    ./eth_verkle_constants,
    ../platforms/[primitives,abstractions],
    ../serialization/endians,
    ../math/config/[type_ff, curves],
    ../math/[extension_fields, arithmetic],
    ../math/elliptic/ec_twistededwards_projective,
    ../hashes,
    ../serialization/[codecs_banderwagon,codecs_status_codes]


func newTranscriptGen*[sha256](res: var sha256, label: openArray[byte]) =
    res.init()
    res.update(label)


func messageAppend* [sha256]( res: var sha256, message: openArray[byte], label: openArray[byte]) =
    res.init()
    res.update(label)
    res.update(message)


func messageAppend_u64* [sha256](res: var sha256, label: openArray[byte], num_value: uint64) = 
    res.init()
    res.update(label)
    res.update(num_value.toBytes(bigEndian))

func domainSeparator* [sha256](res: var sha256, label: openArray[byte]) =
    var state {.noInit.} : sha256
    state.update(label)


func pointAppend* [sha256] (res: var sha256, label: openArray[byte], point: EC_P) =
    var bytes {.noInit.}: array[32, byte]
    if(bytes.serialize(point) == cttCodecEcc_Success):
        res.messageAppend(bytes, label)


func scalarAppend* [sha256] (res: var sha256, label: openArray[byte], scalar: matchingOrderBigInt(Banderwagon)) =
    var bytes {.noInit.}: array[32, byte]

    if(bytes.serialize_scalar(scalar) == cttCodecScalar_Success):
        res.messageAppend(bytes, label)



# Generating Challenge Scalars based on the Fiat Shamir method
func generateChallengeScalar* (gen: var matchingOrderBigInt(Banderwagon), transcript: var sha256, label: openArray[byte]) =
    transcript.domainSeparator(label)

    var hash: array[32, byte]
    transcript.finish(hash)

    if(gen.deserialize_scalar(hash) == cttCodecScalar_Success):
        transcript.clear()
        transcript.scalarAppend(label, gen)
