# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

## IPAConfiguration contains all of the necessary information to create Pedersen + IPA proofs
## such as the SRS
import
    ../../../constantine/platforms/primitives,
    ../../math/config/[type_ff, curves],
    ../../math/elliptic/ec_twistededwards_projective,
    ../../../constantine/hashes,
    ../../../constantine/serialization/[codecs_banderwagon,codecs_status_codes]

# ############################################################
#
#               Random Element Generator
#
# ############################################################
const seed* = asBytes"eth_verkle_oct_2021"

{.used.}

type
  EC_P* = ECP_TwEdwards_Prj[Fp[Banderwagon]]

func generate_random_elements* (num_points: var uint64) : ECP_TwEdwards_Prj[Fp[Banderwagon]] {.inline.} =
    var points {.noInit.} : array[256, ECP_TwEdwards_Prj[Fp[Banderwagon]]]

    var incrementer: uint64 = 0

    while uint64(len(points)) !=  num_points:

        var digest : sha256
        digest.init()
        digest.update(seed)

        var b {.noInit.} : array[8, byte]
        digest.update(b)

        var hash {.noInit.} : array[32, byte]

        digest.finish(hash)

        var x {.noInit.}:  EC_P   
        var xFinal {.noInit.}: EC_P

        if(x.deserialize(hash) == cttCodecEcc_Success):
            xFinal = x

        incrementer=incrementer+1

        var x_as_Bytes {.noInit.} : array[32, byte]
        if(x_as_Bytes.serialize(xFinal) == cttCodecEcc_Success):
            x_as_Bytes = x_as_Bytes

        var point_found {.noInit.} : EC_P
        if (point_found.deserialize(x_as_Bytes) == cttCodecEcc_Success):
            points[incrementer] = point_found






        

        

        


        

        






        











