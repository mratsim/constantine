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
    ./[helper_types],
    ../../../constantine/platforms/primitives,
    ../../math/config/[type_ff, curves],
    ../../math/elliptic/ec_twistededwards_projective,
    ../../../constantine/hashes,
    ../../../constantine/math/arithmetic,
    ../../../constantine/math/elliptic/ec_scalar_mul,
    ../../../constantine/math/elliptic/[ec_multi_scalar_mul, ec_multi_scalar_mul_scheduler],
    ../../../constantine/platforms/[bithacks,views],
    ../../../constantine/curves_primitives,
    ../../../constantine/serialization/[codecs_banderwagon,codecs_status_codes, endians]

# ############################################################
#
#               Random Element Generator
#
# ############################################################



func generate_random_points* [EC_P](points: var  openArray[EC_P] , num_points: uint64)  =

    var incrementer: uint64 = 0
    var idx: int = 0
    while uint64(len(points)) !=  num_points:

        var digest : sha256
        digest.init()
        digest.update(seed)

        digest.update(incrementer.toBytes(bigEndian))

        var hash {.noInit.} : array[32, byte]

        digest.finish(hash)

        var x {.noInit.}:  EC_P

        let stat1 =  x.deserialize(hash) 
        doAssert stat1 == cttCodecEcc_Success, "Deserialization Failure!"
        incrementer=incrementer+1

        var x_as_Bytes {.noInit.} : array[32, byte]
        let stat2 = x_as_Bytes.serialize(x)
        doAssert stat2  == cttCodecEcc_Success, "Serialization Failure!"

        var point_found {.noInit.} : EC_P
        let stat3 = point_found.deserialize(x_as_Bytes)

        doAssert stat3 == cttCodecEcc_Success, "Deserialization Failure!"
        points[idx] = point_found
        idx=idx+1


# ############################################################
#
#                       Inner Products
#
# ############################################################

func computeInnerProducts* [EC_P_Fr] (res: var EC_P_Fr, a,b : openArray[EC_P_Fr])=
  doAssert (a.len == b.len).bool() == true, "Scalar lengths don't match!"
  res.setZero()
  for i in 0..<b.len:
    var tmp : EC_P_Fr 
    tmp.prod(a[i], b[i])
    res.sum(res,tmp)

func computeInnerProducts* [EC_P_Fr] (res: var EC_P_Fr, a,b: StridedView[EC_P_Fr])=
  doAssert (a.len == b.len).bool() == true, "Scalar lengths don't match!"
  res.setZero()
  for i in 0..<b.len:
    var tmp : EC_P_Fr 
    tmp.prod(a[i], b[i])
    res.sum(res,tmp)
  
# ############################################################
#
#                    Folding functions
#
# ############################################################

func foldScalars* [EC_P_Fr] (res: var openArray[EC_P_Fr], a,b : openArray[EC_P_Fr], x: EC_P_Fr)=
    
    doAssert a.len == b.len , "Lengths should be equal!"

    for i in 0..<a.len:
        var bx {.noInit.}: EC_P_Fr
        bx.prod(x, b[i])
        res[i].sum(bx, a[i])


func foldPoints* [EC_P] (res: var openArray[EC_P], a,b : var openArray[EC_P], x: EC_P_Fr)=
    
    doAssert a.len == b.len , "Should have equal lengths!"

    for i in 0..<a.len:
        var bx {.noInit.}: EC_P

        b[i].scalarMul(x.toBig())
        bx = b[i]
        res[i].sum(bx, a[i])


func computeNumRounds* [uint64] (res: var uint64, vectorSize: SomeUnsignedInt)= 

    doAssert (vectorSize == uint64(0)).bool() == false, "Zero is not a valid input!"

    var isP2 : bool = isPowerOf2_vartime(vectorSize)

    doAssert isP2 == true, "not a power of 2, hence not a valid inputs"

    res = uint64(float64(log2_vartime(vectorSize)))


# ############################################################
#
#           Pedersen Commitment for a Single Polynomial
#
# ############################################################

# This Pedersen Commitment function shall be used in specifically the Split scalars 
# and Split points that are used in the IPA polynomial

# Further reference refer to this https://dankradfeist.de/ethereum/2021/07/27/inner-product-arguments.html

func pedersen_commit_varbasis*[EC_P] (res: var EC_P, groupPoints: openArray[EC_P], g: int,  polynomial: openArray[EC_P_Fr], n: int)=
  doAssert groupPoints.len == polynomial.len, "Group Elements and Polynomials should be having the same length!"
  var poly_big = newSeq[matchingOrderBigInt(Banderwagon)](n)
  for i in 0..<n:
    poly_big[i] = polynomial[i].toBig()

  var groupPoints_aff = newSeq[EC_P_Aff](g)
  for i in 0..<g:
    groupPoints_aff[i].affine(groupPoints[i])

  res.multiScalarMul_reference_vartime(poly_big,groupPoints)
