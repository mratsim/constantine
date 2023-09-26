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
    std/typetraits,
    ../../platforms/primitives,
    ../../serialization/endians,
    ../../../constantine/platforms/primitives,
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

func new_transcript_gen*[Transcript](res: var Transcript, label: seq[byte]) =
    res.init()
    res.update(label)


func message_append* [Transcript]( res: var Transcript, message: seq[byte], label: seq[byte]) =
    res.init()
    res.update(label)
    res.update(message)


func message_append_u64* [Transcript](res: var Transcript, label: seq[byte], num_value: uint64) = 
    res.init()
    res.update(label)
    res.update(num_value.toBytes(bigEndian))

func domain_separator* [Transcript](res: var Transcript, label: seq[byte]) =
    var state {.noInit.} : sha256
    state.update(label)


func point_append* [Transcript] (res: var Transcript, label: seq[byte], point: EC_P) =
    var bytes {.noInit.}: array[32, byte]
    doAssert point.serialize(bytes) == cttCodecEcc_Success
    res.message_append(bytes, label)


func scalar_append* [Transcript] (res: var Transcript, label: seq[byte], scalar: EC_P_Fr) =
    var bytes {.noInit.}: array[32, byte]

    doAssert scalar.serialize(bytes) == cttCodecEcc_Success
    res.message_append(bytes, label)



## Generating Challenge Scalars based on the Fiat Shamir method
func generate_challenge_scalar_multiproof* [EC_P_Fr] (gen: var EC_P_Fr, label: seq[byte]) =
    var state {.noInit.}: Transcript
    state.init()
    state.domain_separator(label)

    var hash: array[32, byte]
    state.finish(hash)

    doAssert hash.deserialize(gen) == cttCodecEcc_Success

    state.scalar_append(label, gen)


    





