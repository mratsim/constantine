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
    ../../../constantine/platforms/[bithacks,views],
    ../../../constantine/math/io/[io_fields],
    ../../../constantine/curves_primitives,
    ../../../constantine/serialization/[codecs_banderwagon,codecs_status_codes]

# ############################################################
#
#               Random Element Generator
#
# ############################################################
const seed* = asBytes"eth_verkle_oct_2021"

type
  EC_P* = ECP_TwEdwards_Prj[Fp[Banderwagon]]


type
    IPASettings* = object
     SRS : openArray[EC_P]
     Q_val : EC_P
     PrecomputedWeights: 




func generate_random_elements* [FF](points: var  openArray[FF] , num_points: uint64)  =

    var incrementer: uint64 = 0

    while uint64(len(points)) !=  num_points:

        var digest : sha256
        digest.init()
        digest.update(seed)

        var b {.noInit.} : array[8, byte]
        digest.update(b)

        var hash {.noInit.} : array[32, byte]

        digest.finish(hash)

        var x {.noInit.}:  FF

        x.deserialize(hash)
        doAssert(cttCodecEcc_Success)
        incrementer=incrementer+1

        var x_as_Bytes {.noInit.} : array[32, byte]
        x_as_Bytes.serialize(x)
        doAssert(cttCodecEcc_Success)

        var point_found {.noInit.} : EC_P
        point_found.deserialize(x_as_Bytes)

        doAssert(cttCodecEcc_Success)
        points[incrementer] = point_found


# ############################################################
#
#                       Inner Products
#
# ############################################################

func compute_inner_products* [FF] (res: var FF, a,b : openArray[FF]): bool {.discardable.} =
    
    let check1 = true
    if (not (len(a) == len(b))):
        check1 = false
    res.setZero()
    for i in 0..len(a):
        var tmp {.noInit.} : FF 
        tmp.prod(a[i], b[i])
        res += tmp

    return check1
# ############################################################
#
#                    Folding functions
#
# ############################################################

func fold_scalars* [FF] (res: var openArray[FF], a,b : openArray[FF], x: FF)=
    
    doAssert a.len == b.len , "Lengths should be equal!"

    for i in 0..a.len:
        var bx {.noInit.}: FF
        bx.prod(x, b[i])
        res[i].sum(bx, a[i])


func fold_points* [FF] (res: var openArray[FF], a,b : openArray[FF], x: FF)=
    
    doAssert a.len == b.len , "Should have equal lengths!"

    for i in 0..a.len:
        var bx {.noInit.}: FF

        b[i].scalarMul(x.toBig())
        bx = b[i]
        res[i].sum(bx, a[i])


func split_scalars* (t: var StridedView) : tuple[a1,a2: StridedView] {.inline.}=

    doAssert (t.len and 1), "Length must be even!"  

    let mid = t.len shr 1

    var result {.noInit.}: StridedView
    result.a1.len = mid
    result.a1.stride = t.stride
    result.a1.offset = t.offset
    result.a1.data = t.data

    result.a2.len = mid
    result.a2.stride = t.stride
    result.a2.offset = t.offset + mid
    result.a2.data = t.data


func compute_num_rounds* [float64] (res: var float64, vectorSize: SomeUnsignedInt)= 

    doAssert (vectorSize == 0), "Zero is not a valid input!"

    let isP2 = isPowerOf2_vartime(vectorSize) and isPowerOf2_vartime(vectorSize - 1)

    doAssert (isP2 == 1), "not a power of 2, hence not a valid inputs"

    res = float64(log2_vartime(vectorSize))

    
    







