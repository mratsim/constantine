# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

# ############################################################
#
#         Transcript Generator for Challenge Scalars
#
# ############################################################
import
    ../../platforms/primitives,
    ../../serialization/endians,
    ../../math/config/[type_ff, curves],
    ../../math/elliptic/ec_twistededwards_projective,
    ../../../constantine/hashes,
    ../../../constantine/serialization/[codecs_banderwagon,codecs_status_codes]

type 
    Transcript* = object
     state: sha256

type
  EC_P* = ECP_TwEdwards_Prj[Fp[Banderwagon]]
  EC_P_Fr* = ECP_TwEdwards_Prj[Fr[Banderwagon]]

func newTranscriptGen*[Transcript](res: var Transcript, label: openArray[byte]) =
    res.init()
    res.update(label)


func messageAppend* [Transcript]( res: var Transcript, message: openArray[byte], label: openArray[byte]) =
    res.init()
    res.update(label)
    res.update(message)


func messageAppend_u64* [Transcript](res: var Transcript, label: openArray[byte], num_value: uint64) = 
    res.init()
    res.update(label)
    res.update(num_value.toBytes(bigEndian))

func domainSeparator* [Transcript](res: var Transcript, label: openArray[byte]) =
    var state {.noInit.} : sha256
    state.update(label)


func pointAppend* [Transcript] (res: var Transcript, label: openArray[byte], point: EC_P) =
    var bytes {.noInit.}: array[32, byte]
    doAssert point.serialize(bytes) == cttCodecEcc_Success
    res.messageAppend(bytes, label)


func scalarAppend* [Transcript] (res: var Transcript, label: openArray[byte], scalar: EC_P_Fr) =
    var bytes {.noInit.}: array[32, byte]

    doAssert scalar.serialize(bytes) == cttCodecEcc_Success
    res.messageAppend(bytes, label)



## Generating Challenge Scalars based on the Fiat Shamir method
func generateChallengeScalar* [EC_P_Fr] (gen: var EC_P_Fr, label: openArray[byte]) =
    var state {.noInit.}: Transcript
    state.init()
    state.domainSeparator(label)

    var hash: array[32, byte]
    state.finish(hash)

    doAssert hash.deserialize(gen) == cttCodecEcc_Success

    state.scalarAppend(label, gen)


    





