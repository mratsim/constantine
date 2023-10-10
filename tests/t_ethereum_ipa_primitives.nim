# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import 
    ../constantine/commitments/ipa/[barycentric_form,test_helper, helper_types, transcript_gen],
    ../constantine/hashes,
    std/[unittest],
    ../constantine/math/config/[type_ff, curves],
    ../constantine/math/elliptic/[
     ec_twistededwards_affine,
     ec_twistededwards_projective
      ],
    ../constantine/math/io/io_fields,
    ../constantine/serialization/[
      codecs_status_codes,
      codecs_banderwagon,
      codecs
       ],
    ../constantine/math/arithmetic,
    ../constantine/math/constants/zoo_generators,
    ../tests/math_elliptic_curves/t_ec_template,
    ../helpers/prng_unsafe,
    ../constantine/ethereum_verkle_primitives


# ############################################################
#
#   Tests for Barycentric Form using Precompute Optimisation
#
# ############################################################

# Please refer to https://hackmd.io/mJeCRcawTRqr9BooVpHv5g 
# type EC_P_Fr* = Fr[Banderwagon]

# type
#   EC_P* = ECP_TwEdwards_Prj[Fp[Banderwagon]]
#   Bytes* = array[32, byte]



# The generator point from Banderwagon
var generator = Banderwagon.getGenerator()

suite "Barycentric Form Tests":

    test "Testing absolute integers":

        proc testAbsInteger() = 
            var abs {.noInit.} : int
            abs.absIntChecker(-100)
            doAssert (abs == 100).bool() == true, "Absolute value should be 100!"
            doAssert (abs < 0).bool() == false, "Value was negative!"
        
        testAbsInteger()
        
    # The interpolation is only needed for testing purposes,
    # but we need to check if it's correct. It's equivalent to getting 
    # the polynomial in coefficient form for a large number of points 

    # test "Testing Basic Interpolation, without precompute optimisations":

    #     proc testBasicInterpolation(n: static int) =

    #         var point_a : Coord

    #         point_a.x.setZero()
    #         point_a.y.setZero()

    #         var point_b : Coord

    #         point_b.x.setOne()
    #         point_b.y.setOne()

    #         var points: array[n,Coord]
    #         points[0] = point_a
    #         points[1] = point_b       

    #         var poly : array[n,EC_P_Fr]

    #         poly.interpolate(points,n)

    #         var genfp : EC_P
    #         genfp.fromAffine(generator)
    #         var genfr : EC_P_Fr
    #         genfr.mapToScalarField(genfp)

    #         var res : EC_P_Fr
    #         genfr.evaluate(poly,n)

    #         doAssert res.toHex() == genfr.toHex(), "Res and Rand_fr should match!"

    #     testBasicInterpolation(2)

    #     proc testDivideOnDomain() = 
    #         var eval_fr {.noInit.} : EC_P_Fr

    #         #TODO: finishing this up later

suite "Transcript Tests":

    test "Some Test Vectors":

        proc testVec()=

            var tr {.noInit.}: sha256
            tr.newTranscriptGen(asBytes"simple_protocol")

            var challenge1 {.noInit.}: matchingOrderBigInt(Banderwagon)
            challenge1.generateChallengeScalar(asBytes"simple_challenge")

            var challenge2 {.noInit.}: matchingOrderBigInt(Banderwagon)
            challenge2.generateChallengeScalar(asBytes"simple_challenge")

            doAssert (challenge1==challenge2).bool() == true , "Transcripts matched!"

        testVec()







            

            













