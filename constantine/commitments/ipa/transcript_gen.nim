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

{.used.}

type 
    Transcript = object
     state: sha256

type
  EC_P* = ECP_TwEdwards_Prj[Fp[Banderwagon]]

func new_transcript_gen*[Transcript](label: var seq[byte]): Transcript =
    var state {.noInit.} : sha256
    state.init()
    state.update(label)
    Transcript = {state}
    return Transcript

func message_append* [Transcript]( message: var seq[byte], label: var seq[byte]) =
    var state {.noInit.}: sha256
    state.init()
    state.update(label)
    state.update(message)
    Transcript = {state}

func message_append_u64* [Transcript](label: var seq[byte], num_value: var uint64) = 
    var state {.noInit.}: sha256
    state.init()
    state.update(label)
    state.update(num_value.toBytes(bigEndian))

    Transcript = {state}

func domain_separator* [Transcript](label: var seq[byte]) =
    var state {.noInit.} : sha256
    state.update(label)
    Transcript = {state}

func point_append* [Transcript] (label: var seq[byte], point: var EC_P) =
    var state {.noInit.} : sha256
    var bytes {.noInit.}: array[32, byte]
    if point.serialize(bytes) == cttCodecEcc_Success:
        point = point
    state = message_append(bytes, label)
    Transcript = {state}

func scalar_append* [Transcript] (label: var seq[byte], scalar: var ECP_TwEdwards_Prj[Fr[Banderwagon]]) =
    var state {.noInit.}: sha256
    var bytes {.noInit.}: array[32, byte]
    if scalar.serialize(bytes) == cttCodecEcc_Success:
        bytes = bytes
    state = message_append(bytes, label)
    Transcript = {state}


## Generating Challenge Scalars based on the Fiat Shamir method
func generate_challenge_scalar_multiproof* [Transcript](label: var seq[byte]) : ECP_TwEdwards_Prj[Fr[Banderwagon]] =
    var state {.noInit.}: sha256
    state.init()
    state = domain_separator(label)

    var hash: array[32, byte]
    state.finish(hash)

    var scalar {.noInit.}: ECP_TwEdwards_Prj[Fr[Banderwagon]]
    if hash.deserialize(scalar) == cttCodecEcc_Success:
        scalar = scalar

    state = scalar_append(label, scalar)
    Transcript = {state}

    return scalar

    





