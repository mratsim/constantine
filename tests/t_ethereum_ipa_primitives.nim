# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import 
    ../constantine/commitments/ipa/[
        barycentric_form,
        test_helper, 
        helper_types, 
        transcript_gen, 
        common_utils,
        ipa_prover],
    ../constantine/hashes,
    std/[unittest],
    ../constantine/math/config/[type_ff, curves],
    ../constantine/math/elliptic/[
     ec_twistededwards_affine,
     ec_twistededwards_projective
      ],
    ../constantine/math/io/io_fields,
    ../constantine/serialization/[
      codecs
       ],
    ../constantine/math/arithmetic,
    ../constantine/math/constants/zoo_generators,
    ../tests/math_elliptic_curves/t_ec_template,
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

    test "Testing Basic Interpolation, without precompute optimisations":

        proc testBasicInterpolation() =

            var point_a : Coord

            point_a.x.setZero()
            point_a.y.setZero()

            var point_b : Coord

            point_b.x.setOne()
            point_b.y.setOne()

            var points: array[2,Coord]
            points[0] = point_a
            points[1] = point_b       

            var poly : array[2,EC_P_Fr]

            poly.interpolate(points,2)

            var genfp : EC_P
            genfp.fromAffine(generator)
            var genfr : EC_P_Fr
            genfr.mapToScalarField(genfp)

            var res {.noInit.}: EC_P_Fr
            res.evaluate(poly,gen_fr,2)
            
            echo res.toHex() 
            echo genfr.toHex() 

            doAssert (res.toHex()==genfr.toHex()) == true, "Not matching!"

        testBasicInterpolation()

    test "Testing Barycentric Precompute Coefficients":
        proc testBarycentricPrecomputeCoefficients()=

            var p_outside_dom : EC_P_Fr

            var i_bg : matchingOrderBigInt(Banderwagon)
            i_bg.setUint(uint64(3400))
            
            p_outside_dom.fromBig(i_bg)

            echo p_outside_dom.toHex()

            var testVals: array[10,uint64] = [1,2,3,4,5,6,7,8,9,10] 
            
            var lagrange_values : array[256,EC_P_Fr]
            lagrange_values.testPoly256(testVals)

            var precomp {.noInit.}: PrecomputedWeights

            precomp.newPrecomputedWeights()

            for i in 0..<10:
                echo "Barycentric Weights"
                echo precomp.barycentricWeights[i].toHex()
                echo "Inverted Domain"
                echo precomp.invertedDomain[i].toHex() 
            
            var bar_coeffs: array[256, EC_P_Fr]

            bar_coeffs.computeBarycentricCoefficients(precomp, p_outside_dom)

            for i in 0..<10:
                echo "Barycentric Coefficients"
                echo bar_coeffs[i].toHex()

            var got: EC_P_Fr

            got.computeInnerProducts(lagrange_values, bar_coeffs)

            var expected : EC_P_Fr
            expected.evalOutsideDomain(precomp, lagrange_values, p_outside_dom)

            var points: array[256, Coord]
            for k in 0..<256:
                var x : matchingOrderBigInt(Banderwagon)
                x.setUint(uint64(k))
                var x_fr : EC_P_Fr
                x_fr.fromBig(x)

                var point : Coord
                point.x = x_fr
                point.y = lagrange_values[k]

                points[k]=point
            echo "Printing the Points"

            for i in 0..<10:
                echo "X points"
                echo points[i].x.toHex()
                echo "Y points"
                echo points[i].y.toHex()

            var poly_coeff : array[DOMAIN, EC_P_Fr]
            poly_coeff.interpolate(points, DOMAIN)

            echo "Printing the Polynomial Coefficients!"

            for i in 0..<20:
                echo poly_coeff[i].toHex()

            var expected2: EC_P_Fr
            expected2.evaluate(poly_coeff, p_outside_dom, DOMAIN)

            echo "Inner Prod Arguments value"
            echo got.toHex()
            echo "Eval outside domain value"
            echo expected.toHex()
            echo "Interpolation and Evalution value"
            echo expected2.toHex()

            #TODO needs better testing?
            doAssert (expected2 == expected).bool() == true, "Problem with Barycentric Weights!"
            doAssert (expected2 == got).bool() == true, "Problem with Inner Products!"

        testBarycentricPrecomputeCoefficients()


    # test "Testing Polynomial Division":

    #     proc testPolynomialDiv() = 

    #         var one {.noInit.} : EC_P_Fr
    #         one.setOne()

    #         var minusOne {.noInit.} : EC_P_Fr
    #         minusOne.setMinusOne()

    #         var minusTwo {.noInit.}: EC_P_Fr
    #         minusTwo.diff(minusOne, one)

    #         var minusThree {.noInit.}: EC_P_Fr
    #         minusThree.diff(minusTwo, one)

    #         var two: EC_P_Fr
    #         two.fromHex("0x2")

    #         #(X-1)(X-2) =  2 - 3X + X^2
    #         var poly_coeff_num :array[3,EC_P_Fr] 
    #         poly_coeff_num[0] = two
    #         poly_coeff_num[1] = minusThree
    #         poly_coeff_num[2] = one

    #         var poly_coeff_den: array[2,EC_P_Fr] 
    #         poly_coeff_den[0]= minusOne
    #         poly_coeff_den[1]= one

    #         var res{.noInit.} :  tuple[q,r : array[DOMAIN, EC_P_Fr], ok: bool]

    #         const n1: int= 2
    #         const n2: int = 3
    #         res.polynomialLongDivision(poly_coeff_num, poly_coeff_den, n1, n2)

    #         var quotient : array[DOMAIN,EC_P_Fr] = res.q
    #         var rem: array[DOMAIN,EC_P_Fr] = res.r
    #         var okay: bool = res.ok

    #         doAssert okay == true, "Poly long div failed"

    #         for i in 0..<rem.len:
    #             doAssert rem[i].isZero().bool() == true, "Remainder should be 0"

    #         var genfp : EC_P
    #         genfp.fromAffine(generator)
    #         var genfr : EC_P_Fr
    #         genfr.mapToScalarField(genfp)

    #         var got : EC_P_Fr
    #         got.evaluate(quotient, genfr, DOMAIN)

    #         var expected {.noInit.} : EC_P_Fr
    #         expected.sum(genfr, minusTwo)

    #         doAssert got.toHex()==expected.toHex() == true, "Quotient is not correct"

    #     testPolynomialDiv()
        



            




    #     proc testDivideOnDomain() = 
    #         var eval_fr {.noInit.} : EC_P_Fr

    #         #TODO: finishing this up later

# ############################################################
#
#          Test for Transcript and Challenge Scalar
#
# ############################################################
suite "Transcript Tests":

    test "Some Test Vectors 0":

        proc testVec()=

            var tr {.noInit.}: sha256
            tr.newTranscriptGen(asBytes"simple_protocol")

            var challenge1 {.noInit.}: matchingOrderBigInt(Banderwagon)
            challenge1.generateChallengeScalar(tr,asBytes"simple_challenge")

            var challenge2 {.noInit.}: matchingOrderBigInt(Banderwagon)
            challenge2.generateChallengeScalar(tr,asBytes"simple_challenge")

            doAssert (challenge1==challenge2).bool() == false , "calling ChallengeScalar twice should yield two different challenges"

        testVec()

    test "Some Test Vectors 1":

        proc testVec1()=

            var tr {.noInit.}: sha256
            var tr2 {.noInit.}: sha256
            tr.newTranscriptGen(asBytes"simple_protocol")
            tr2.newTranscriptGen(asBytes"simple_protocol")
            

            var challenge1 {.noInit.}: matchingOrderBigInt(Banderwagon)
            challenge1.generateChallengeScalar(tr,asBytes"ethereum_challenge")

            var challenge2 {.noInit.}: matchingOrderBigInt(Banderwagon)
            challenge2.generateChallengeScalar(tr2,asBytes"ethereum_challenge")

            doAssert (challenge1==challenge2).bool() == true , "calling ChallengeScalar twice should yield the same challenge"

        testVec1()
# ############################################################
#
#                     Test for IPA Proofs    
#
# ############################################################
suite "IPA proof tests":
    test "Test for initiating IPA proof configuration":
        proc testMain()=
            var ipaConfig: IPASettings
            let stat1 = ipaConfig.genIPAConfig()
            doAssert stat1 == true, "Could not generate new IPA Config properly!"
        testMain()

    test "Test for IPA Proof of Creation and Verification"
        proc testIPAProofCreateAndVerify()=
            var point {.noInit.} : EC_P_Fr

            var i_bg {.noInit.} : matchingOrderBigInt(Banderwagon)
            i_bg.setUint(uint(1234))

        