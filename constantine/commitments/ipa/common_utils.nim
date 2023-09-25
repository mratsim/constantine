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


func generate_random_elements* [Field](points: var  openArray[Field] , num_points: uint64)  =

    var incrementer: uint64 = 0

    while uint64(len(points)) !=  num_points:

        var digest : sha256
        digest.init()
        digest.update(seed)

        var b {.noInit.} : array[8, byte]
        digest.update(b)

        var hash {.noInit.} : array[32, byte]

        digest.finish(hash)

        var x {.noInit.}:  Field
        var xFinal {.noInit.}: Field

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

func compute_inner_products* [Field] (res: var Field, a,b : openArray[Field]): bool {.discardable.} =
    
    let check1 = true
    if (not (len(a) == len(b))):
        check1 = false
    res.setZero()
    for i in 0..len(a):
        var tmp {.noInit.} : Field 
        tmp.prod(a[i], b[i])
        res += tmp

    return check1
# ############################################################
#
#                    Folding functions
#
# ############################################################

func fold_scalars* [Field] (res: var openArray[Field], a,b : openArray[Field], x: Field)=
    
    doAssert(len(a)==len(b))

    var res {.noInit.}: Field
    for i in 0..len(a):
        var bx {.noInit.}: Field
        bx.prod(x, b[i])
        res[i].sum(bx, a[i])


func fold_points* [Field] (res: var openArray[Field], a,b : openArray[Field], x: Field)=
    
    doAssert (len(a)==len(b)), "Should have equal lengths!"
    for i in 0..len(a):
        var bx {.noInit.}: Field

        b[i].scalarMul(x.toBig())
        bx = b[i]
        res[i].sum(bx, a[i])


func split_scalars* [Field] (x: var Field) : tuple[a1,a2: openArray[Field]]=

    doAssert (len(x)mod 2 == 0), "Should have equal lengths!"  
    let mid = len(x) div 2
    let (a1,a2) = (x[0..mid-1], x[mid..len(x)-1])

func compute_num_rounds* [float64] (res: var float64, vectorSize: SomeUnsignedInt)= 

    doAssert (vectorSize == 0), "Zero is not a valid input!"

    let isP2 = isPowerOf2_vartime(vectorSize) and isPowerOf2_vartime(vectorSize - 1)

    doAssert (isP2 == 1), "not a power of 2, hence not a valid inputs"

    res = float64(log2_vartime(vectorSize))

    
    







