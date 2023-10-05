# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

# ############################################################
#
#             Ethereum Verkle Primitves Tests
#
# ############################################################

import
  std/unittest,
  ../constantine/math/config/[type_ff, curves],
  ../constantine/math/elliptic/[
    ec_twistededwards_affine,
    ec_twistededwards_projective,
    ec_twistededwards_batch_ops
  ],
  ../constantine/math/io/io_fields,
  ../constantine/serialization/[
    codecs_status_codes,
    codecs_banderwagon,
    codecs
  ],
  ../constantine/math/arithmetic,
  ../constantine/math/constants/zoo_generators,
  ../constantine/ethereum_verkle_primitives

type
  EC* = ECP_TwEdwards_Prj[Fp[Banderwagon]]
  Bytes* = array[32, byte]

# The generator point from Banderwagon
var generator = Banderwagon.getGenerator()

# serialized points which lie on Banderwagon
const expected_bit_strings: array[16, string] = [
  "0x4a2c7486fd924882bf02c6908de395122843e3e05264d7991e18e7985dad51e9",
  "0x43aa74ef706605705989e8fd38df46873b7eae5921fbed115ac9d937399ce4d5",
  "0x5e5f550494159f38aa54d2ed7f11a7e93e4968617990445cc93ac8e59808c126",
  "0x0e7e3748db7c5c999a7bcd93d71d671f1f40090423792266f94cb27ca43fce5c",
  "0x14ddaa48820cb6523b9ae5fe9fe257cbbd1f3d598a28e670a40da5d1159d864a",
  "0x6989d1c82b2d05c74b62fb0fbdf8843adae62ff720d370e209a7b84e14548a7d",
  "0x26b8df6fa414bf348a3dc780ea53b70303ce49f3369212dec6fbe4b349b832bf",
  "0x37e46072db18f038f2cc7d3d5b5d1374c0eb86ca46f869d6a95fc2fb092c0d35",
  "0x2c1ce64f26e1c772282a6633fac7ca73067ae820637ce348bb2c8477d228dc7d",
  "0x297ab0f5a8336a7a4e2657ad7a33a66e360fb6e50812d4be3326fab73d6cee07",
  "0x5b285811efa7a965bd6ef5632151ebf399115fcc8f5b9b8083415ce533cc39ce",
  "0x1f939fa2fd457b3effb82b25d3fe8ab965f54015f108f8c09d67e696294ab626",
  "0x3088dcb4d3f4bacd706487648b239e0be3072ed2059d981fe04ce6525af6f1b8",
  "0x35fbc386a16d0227ff8673bc3760ad6b11009f749bb82d4facaea67f58fc60ed",
  "0x00f29b4f3255e318438f0a31e058e4c081085426adb0479f14c64985d0b956e0",
  "0x3fa4384b2fa0ecc3c0582223602921daaa893a97b64bdf94dcaa504e8b7b9e5f",
]

## These are all points which will be shown to be on the curve
## but are not in the correct subgroup
const bad_bit_string: array[16, string] = [
  "0x1b6989e2393c65bbad7567929cdbd72bbf0218521d975b0fb209fba0ee493c32",
  "0x280e608d5bbbe84b16aac62aa450e8921840ea563f1c9c266e0240d89cbe6a78",
  "0x31468782818807366dbbcd20b9f10f0d5b93f22e33fe49b450dfbddaf3ba6a9b",
  "0x6bfc4097e4874cdddebe74e041fcd329d8455278cd42b6dd4f40b042d4fc466b",
  "0x65dc0a9730cce485d82b230ce32c7c21688967c8943b4a51ba468f927e2e28ef",
  "0x0fd3536157199b46617c3fba4bae1c2ffab5409dfea1de62161bc10748651671",
  "0x5bdc73f43e90ae5c2956320ce2ef2b17809b11d6b9758c7861793b41f39b7c01",
  "0x23a89c778ee10b9925ad3df5dc1f7ab244c1daf305669bc6b03d1aaa100037a4",
  "0x67505814852867356aaa8387896efa1d1b9a72aad95549e53e69c15eb36a642c",
  "0x301bc9b1129a727c2a65b96f55a5bcd642a3d37e0834196863c4430e4281dc3a",
  "0x45d08715ac67ebb088bcfa3d04bcce76510edeb9e23f12ed512894ba1e6518fc",
  "0x0b3b6e1f8ec72e63c6aa7ae87628071df3d82ea2bea6516d1948dac2edc12179",
  "0x72430a05f507747aa5a42481b4f93522aa682b1d56e5285f089aa1b5fb09c67a",
  "0x5eb4d3e5ce8107c6dd7c6398f2a903a0df75ce655939c29a3e309f43fe5bcd1f",
  "0x6671109a7a15f4852ead3298318595a36010930fddbd3c8f667c6390e7ac3c66",
  "0x120faa1df94d5d831bbb69fc44816e25afd27288a333299ac3c94518fd0e016f",
]

const expected_scalar_field_elements: array[2, string] = [
  "0x0e0c604381ef3cd11bdc84e8faa59b542fbbc92f800ed5767f21e5dbc59840ce",
  "0x0a21f7dfa8ddaf6ef6f2044f13feec50cbb963996112fa1de4e3f52dbf6b7b6d"
] # test data generated from go-ipa implementation

# ############################################################
#
#              Banderwagon Serialization Tests
#
# ############################################################
suite "Banderwagon Serialization Tests":
  var points: seq[EC]

  ## Check encoding if it is as expected or not
  test "Test Encoding from Fixed Vectors":
    proc testSerialize(len: int) =
      # First the point is set to generator P
      # then with each iteration 2P, 4P, . . . doubling
      var point {.noInit.}: EC
      point.fromAffine(generator)

      for i in 0 ..< len:
        var arr: Bytes
        let stat = arr.serialize(point)

        # Check if the serialization took place and in expected way
        doAssert stat == cttCodecEcc_Success, "Serialization Failed"
        doAssert expected_bit_strings[i] == arr.toHex(), "bit string does not match expected"
        points.add(point)

        point.double() #doubling the point

    testSerialize(expected_bit_strings.len)
  
  ## Check decoding if it is as expected or not
  test "Decoding Each bit string":
    proc testDeserialization(len: int) =
      # Checks if the point serialized in the previous
      # tests matches with the deserialization of expected strings 
      for i, bit_string in expected_bit_strings:

        # converts serialized value in hex to byte array
        var arr: Bytes
        arr.fromHex(bit_string) 

        # deserialization from expected bits
        var point{.noInit.}: EC
        let stat = point.deserialize(arr) 

        # Assertion check for the Deserialization Success & correctness
        doAssert stat == cttCodecEcc_Success, "Deserialization Failed"
        doAssert (point == points[i]).bool(), "Decoded Element is different from expected element"

    testDeserialization(expected_bit_strings.len)
  
  # Check if the subgroup check is working on eliminating
  # points which don't lie on banderwagon, while 
  # deserializing from an untrusted source
  test "Decoding Points Not on Curve":
    proc testBadPointDeserialization(len: int) =
      # Checks whether the bad bit string
      # get deserialized, it should return error -> cttCodecEcc_PointNotInSubgroup
      for bit_string in bad_bit_string:

        # converts serialized value in hex to byte array
        var arr: Bytes
        arr.fromHex(bit_string)

        # deserialization from bits
        var point{.noInit.}: EC
        let stat = point.deserialize(arr)

        # Assertion check for error
        doAssert stat == cttCodecEcc_PointNotInSubgroup, "Bad point Deserialization Failed, in subgroup check"
    
    testBadPointDeserialization(bad_bit_string.len)


# ############################################################
#
#           Banderwagon Point Operations Tests
#
# ############################################################
suite "Banderwagon Points Tests":

  ## Tests if the operation are consistent & correct
  ## consistency of Addition with doubling
  ## and correctness of the subtraction
  test "Test for Addition, Subtraction, Doubling":
    proc testAddSubDouble() =
      var a, b, gen_point, identity {.noInit.} : EC
      gen_point.fromAffine(generator)

      # Setting the identity Element
      identity.x.setZero()
      identity.y.setOne()
      identity.z.setOne()

      a.sum(gen_point, gen_point) # a = g+g = 2g
      b.double(gen_point)         # b = 2g

      doAssert (not (a == gen_point).bool()), "The generator should not have order < 2" 
      doAssert (a == b).bool(), "Add and Double formulae do not match" # Checks is doubling and addition are consistent

      a.diff(a, b) # a <- a - b
      doAssert (a == identity).bool(), "Sub formula is incorrect; any point minus itself should give the identity point"

    testAddSubDouble()

  ## Points that differ by a two torsion point
  ## are equal, where the two torsion point is not the point at infinity 
  test "Test Two Torsion Equality":
    proc testTwoTorsion() =
      var two_torsion: EC

      # Setting the two torsion point
      two_torsion.x.setZero()
      two_torsion.y.setMinusOne()
      two_torsion.z.setOne()

      var point{.noInit.}: EC
      point.fromAffine(generator)

      for i in 0 ..< 1000:
        var point_plus_torsion: EC
        point_plus_torsion.sum(point, two_torsion) # adding generator with two torsion point

        doAssert (point == point_plus_torsion).bool(), "points that differ by an order-2 point should be equal"
        
        # Serializing to the point and point added with two torsion point
        var point_bytes: Bytes
        let stat1 = point_bytes.serialize(point)
        var plus_point_bytes: Bytes
        let stat2 = plus_point_bytes.serialize(point_plus_torsion)

        doAssert stat1 == cttCodecEcc_Success and stat2 == cttCodecEcc_Success, "Serialization Failed"
        doAssert plus_point_bytes == point_bytes, "points that differ by an order-2 point should produce the same bit string"

        point.double()

    testTwoTorsion()

# ############################################################
#
#     Banderwagon Points Mapped to Scalar Field ( Fp -> Fr )
#
# ############################################################
suite "Banderwagon Elements Mapping":

  ## Tests if the mapping from Fp to Fr 
  ## is working as expected or not
  test "Testing Map To Base Field":
    proc testMultiMapToBaseField() =
      var A, B, genPoint {.noInit.}: EC
      genPoint.fromAffine(generator)

      A.sum(genPoint, genPoint) # A = g+g = 2g
      B.double(genPoint)        # B = 2g
      B.double()                # B = 2B = 4g

      var expected_a, expected_b: Fr[Banderwagon]

      # conver the points A & B which are in Fp
      # to the their mapped Fr points 
      expected_a.mapToScalarField(A)
      expected_b.mapToScalarField(B)

      doAssert expected_a.toHex() == expected_scalar_field_elements[0], "Mapping to Scalar Field Incorrect"
      doAssert expected_b.toHex() == expected_scalar_field_elements[1], "Mapping to Scalar Field Incorrect"

    testMultiMapToBaseField()

# ############################################################
#
#               Banderwagon Batch Operations
#
# ############################################################
suite "Batch Operations on Banderwagon":

  ## Tests if the Batch Affine operations are
  ## consistent with the signular affine operation
  ## Using the concept of point double from generator point
  ## we try to achive this
  test "BatchAffine and fromAffine Consistency":
    proc testbatch(n: static int) =
      var g, temp {.noInit.}: EC
      g.fromAffine(generator)     # setting the generator point

      var aff{.noInit.}: ECP_TwEdwards_Aff[Fp[Banderwagon]]
      aff = generator

      var points_prj: array[n, EC]
      var points_aff: array[n, ECP_TwEdwards_Aff[Fp[Banderwagon]]]

      for i in 0 ..< n:
        points_prj[i] = g
        g.double()          # doubling the point

      points_aff.batchAffine(points_prj) # performs the batch operation
      
      # checking correspondence with singular affine conversion
      for i in 0 ..< n:
        doAssert (points_aff[i] == aff).bool(), "batch inconsistent with singular ops"
        temp.fromAffine(aff)
        temp.double()
        aff.affine(temp)      

    testbatch(1000)

  ## Tests to check if the Motgomery Batch Inversion
  ## Check if the Batch Inversion is consistent with
  ## it's respective sigular inversion operation of field elements
  test "Batch Inversion":
    proc batchInvert(n: static int) = 
      var one, two: EC
      var arr_fp: array[n, Fp[Banderwagon]]   # array for Fp field elements

      one.fromAffine(generator)   # setting the 1st generator point
      two.fromAffine(generator)   # setting the 2nd generator point

      for i in 0 ..< n:
        arr_fp[i] = one.x
        one.double()

      var arr_fp_inv: array[n, Fp[Banderwagon]]
      doAssert arr_fp_inv.batchInvert(arr_fp) == true

      # Checking the correspondence with singular element inversion
      for i in 0 ..< n:
        var temp: Fp[Banderwagon]
        temp.inv(two.x)
        doAssert (arr_fp_inv[i] == temp).bool(), "Batch Inversion in consistent"
        two.double()

    batchInvert(10)

  ## Tests to check if the Batch Map to Scalar Field
  ## is consistent with it's respective singular operation
  ## of mapping from Fp to Fr
  ## Using the concept of point double from generator point
  ## we try to achive this
  test "Testing Batch Map to Base Field":
    proc testBatchMapToBaseField() =
      var A, B, g: EC
      g.fromAffine(generator)

      A.sum(g, g)
      B.double(g)
      B.double()

      var expected_a, expected_b: Fr[Banderwagon]
      expected_a.mapToScalarField(A)
      expected_b.mapToScalarField(B)

      var ARes, BRes: Fr[Banderwagon]
      var scalars: array[2, Fr[Banderwagon]] = [ARes, BRes]
      var fps: array[2, EC] = [A, B]

      doAssert scalars.batchMapToScalarField(fps), "Batch Map to Scalar Failed"
      doAssert (expected_a == scalars[0]).bool(), "expected scalar for point `A` is incorrect"
      doAssert (expected_b == scalars[1]).bool(), "expected scalar for point `B` is incorrect"

    testBatchMapToBaseField()