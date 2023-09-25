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
    ../../../constantine/math/arithmetic,
    ../../../constantine/math/elliptic/ec_scalar_mul,
    ../../../constantine/platforms/bithacks,
    ../../../constantine/serialization/[codecs_banderwagon,codecs_status_codes]

# ############################################################
#
#               Random Element Generator
#
# ############################################################
const seed* = asBytes"eth_verkle_oct_2021"

type
  EC_P* = ECP_TwEdwards_Prj[Fp[Banderwagon]]


func generate_random_elements* (num_points: var uint64) : seq[ECP_TwEdwards_Prj[Fp[Banderwagon]]] {.inline.} =
    var points {.noInit.} : seq[ ECP_TwEdwards_Prj[Fp[Banderwagon]]]

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

    return points

# ############################################################
#
#                       Inner Products
#
# ############################################################

proc compute_inner_products (a,b : var seq[EC_P]): EC_P =

    if (not (len(a) == len(b))):
        echo "a and b are of different lengths! cannot perform inner prod"
    
    var result {.noInit.}: ECP_TwEdwards_Prj[Fp[Banderwagon]]

    result.x.setZero()
    result.y.setZero()
    result.z.setZero()

    for i in 0..len(a):
        var tmp: EC_P
        tmp.x.prod(tmp.x,a[i].x)
        tmp.y.prod(tmp.y,b[i].y)

        result += tmp

    return result

# ############################################################
#
#                    Folding functions
#
# ############################################################

proc fold_scalars (a,b: var seq[EC_P], x: var EC_P) : seq[EC_P]  =
    if (not (len(a) == len(b))):
        echo "slices are not of equal length"

    var result {.noInit.}: seq[EC_P]
    for i in 0..len(a):
        var bx {.noInit.}: EC_P

        bx.x.prod(x.x,b[i].x)
        bx.y.prod(x.y,b[i].y)

        result[i].sum(bx, a[i])

    return result

proc fold_points (a,b: var seq[EC_P], x: var EC_P) : seq[EC_P]  =
    if (not (len(a)==len(b))):
        echo "scalar slices are not of equal length"
    
    var result {.noInit.}: seq[EC_P]
    for i in 0..len(a):
        var bx {.noInit.}: EC_P

        b[i].scalarMul(x.x.toBig())
        b[i].scalarMul(x.y.toBig())

        bx = b[i]
        result[i].sum(bx, a[i])

    return result

proc split_scalars (x: var seq[EC_P]) : tuple[a,b: seq[EC_P]] =
    if (not (len(x)mod 2 == 0)):
        echo "the slices should have an even length"
    
    let mid = len(x) div 2
    return (x[0..mid-1], x[mid..len(x)-1])

proc compute_num_rounds (vectorSize: var uint32) : uint32 = 

    if vectorSize == 0:
        echo "Zero is not a valid input!"

    let isP2 = isPowerOf2_vartime(vectorSize) and isPowerOf2_vartime(vectorSize - 1)

    if not(isP2):
        echo "not a power of 2, hence not a valid inputs"

    var res {.noInit.}: float64
    res = float64(log2_vartime(vectorSize))

    return uint32(res)
    
    







