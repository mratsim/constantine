# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  ./t_ethereum_verkle_ipa_test_helper,
  ../constantine/eth_verkle_ipa/[
      barycentric_form,
      eth_verkle_constants, 
      transcript_gen, 
      common_utils,
      ipa_prover,
      ipa_verifier,
      multiproof],
  ../constantine/hashes,
  std/[unittest],
  ../constantine/math/config/[type_ff, curves],
  ../constantine/math/elliptic/[
    ec_twistededwards_projective
    ],
  ../constantine/math/io/io_fields,
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

          var poly : array[2,Fr[Banderwagon]]

          poly.interpolate(points,2)

          var genfp : EC_P
          genfp.fromAffine(generator)
          var genfr : Fr[Banderwagon]
          genfr.mapToScalarField(genfp)

          var res {.noInit.}: Fr[Banderwagon]
          res.ipaEvaluate(poly,gen_fr,2)

          doAssert (res.toHex() == genfr.toHex()) == true, "Not matching!"

        testBasicInterpolation()

    test "Testing Barycentric Precompute Coefficients":
        proc testBarycentricPrecomputeCoefficients()=

            var p_outside_dom : Fr[Banderwagon]
            
            p_outside_dom.fromInt(3400)

            var testVals: array[10,uint64] = [1,2,3,4,5,6,7,8,9,10] 
            
            var lagrange_values : array[256,Fr[Banderwagon]]
            lagrange_values.testPoly256(testVals)

            var precomp {.noInit.}: PrecomputedWeights

            precomp.newPrecomputedWeights()
            
            var bar_coeffs: array[256, Fr[Banderwagon]]

            bar_coeffs.computeBarycentricCoefficients(precomp, p_outside_dom)

            var expected0: Fr[Banderwagon]

            expected0.computeInnerProducts(lagrange_values, bar_coeffs)

            var points: array[256, Coord]
            for k in 0 ..< 256:
                var x_fr : Fr[Banderwagon]
                x_fr.fromInt(k)

                var point : Coord
                point.x = x_fr
                point.y = lagrange_values[k]

                points[k]=point

            var poly_coeff : array[VerkleDomain, Fr[Banderwagon]]
            poly_coeff.interpolate(points, VerkleDomain)

            var expected2: Fr[Banderwagon]
            expected2.ipaEvaluate(poly_coeff, p_outside_dom, VerkleDomain)


            doAssert (expected0.toHex() == "0x042d5629f4eaac570610673570658986f8a74730d3d8587e34062ac4b3c3b950").bool() == true, "Problem with Barycentric Weights!"
            doAssert (expected2.toHex() == "0x0ddd6424cdfa97f24d8de604a309e1a4eb6ce33663aa132cf87ee874a0ffe506").bool() == true, "Problem with Inner Products!"

        testBarycentricPrecomputeCoefficients()


# ############################################################
#
#          Test for Transcript and Challenge Scalar
#
# ############################################################


suite "Transcript Tests":

    test "Transcript Testing with different challenge scalars to test randomness":

        proc testVec()=

            var tr {.noInit.}: sha256
            tr.newTranscriptGen(asBytes"simple_protocol")

            var challenge1 {.noInit.}: matchingOrderBigInt(Banderwagon)
            challenge1.generateChallengeScalar(tr,asBytes"simple_challenge")

            var challenge2 {.noInit.}: matchingOrderBigInt(Banderwagon)
            challenge2.generateChallengeScalar(tr,asBytes"simple_challenge")

            doAssert (challenge1 == challenge2).bool() == false , "calling ChallengeScalar twice should yield two different challenges"

        testVec()

    test "Transcript testing with same challenge scalar to test transcript correctness":

        proc testVec1()=

            var tr {.noInit.}: sha256
            var tr2 {.noInit.}: sha256
            tr.newTranscriptGen(asBytes"simple_protocol")
            tr2.newTranscriptGen(asBytes"simple_protocol")
            

            var challenge1 {.noInit.}: matchingOrderBigInt(Banderwagon)
            challenge1.generateChallengeScalar(tr,asBytes"ethereum_challenge")

            var challenge2 {.noInit.}: matchingOrderBigInt(Banderwagon)
            challenge2.generateChallengeScalar(tr2,asBytes"ethereum_challenge")

            doAssert (challenge1 == challenge2).bool() == true , "calling ChallengeScalar twice should yield the same challenge"

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
        var ipaTranscript: IpaTranscript[sha256, 32]
        let stat1 = ipaConfig.genIPAConfig(ipaTranscript)
        doAssert stat1 == true, "Could not generate new IPA Config properly!"
    testMain()

  test "Test for IPA proof equality":
    proc testIPAProofEquality()=
        var point: Fr[Banderwagon]
        var ipaConfig: IPASettings
        var ipaTranscript: IpaTranscript[sha256, 32]
        let stat1 = ipaConfig.genIPAConfig(ipaTranscript)

        var testGeneratedPoints: array[256, EC_P]
        testGeneratedPoints.generate_random_points(ipaTranscript, 256)

        var prover_transcript: sha256
        prover_transcript.newTranscriptGen(asBytes"ipa")

        #from a shared view
        point.fromInt(12345)

        #from the prover's side
        var testVals: array[5, uint64] = [1,2,3,4,5]
        var poly: array[256, Fr[Banderwagon]]
        poly.testPoly256(testVals)

        var prover_comm: EC_P
        prover_comm.pedersen_commit_varbasis(testGeneratedPoints,testGeneratedPoints.len, poly, poly.len)

        var ipaProof1: IPAProof
        let stat11 = ipaProof1.createIPAProof(prover_transcript, ipaConfig, prover_comm, poly, point)
        doAssert stat11 == true, "Problem creating IPA proof 1"

        var ipaProof2: IPAProof
        let stat22 = ipaProof2.createIPAProof(prover_transcript, ipaConfig, prover_comm, poly, point)
        doAssert stat22 == true, "Problem creating IPA proof 2"

        var stat33: bool
        stat33 = ipaProof1.isIPAProofEqual(ipaProof2)
        doAssert stat33 == true, "IPA proofs aren't equal"

    testIPAProofEquality()

    test "Test for IPA Proof of Creation and Verification":
      proc testIPAProofCreateAndVerify()=
        var point : Fr[Banderwagon]
        var ipaConfig: IPASettings
        var ipaTranscript: IpaTranscript[sha256, 32]
        let stat1 = ipaConfig.genIPAConfig(ipaTranscript)

        var testGeneratedPoints: array[256,EC_P]
        testGeneratedPoints.generate_random_points(ipaTranscript,256)

        # from a shared view
        point.fromInt(123456789)

        # from the prover's side
        var testVals : array[9, uint64] = [1,2,3,4,5,6,7,8,9]
        var poly: array[256,Fr[Banderwagon]]
        poly.testPoly256(testVals)

        var prover_comm : EC_P
        prover_comm.pedersen_commit_varbasis(testGeneratedPoints, testGeneratedPoints.len,  poly, poly.len)

        var prover_transcript: sha256
        prover_transcript.newTranscriptGen(asBytes"ipa")

        var ipaProof: IPAProof
        let stat = ipaProof.createIPAProof(prover_transcript, ipaConfig, prover_comm, poly, point)
        doAssert stat == true, "Problem creating IPA proof"

        var precomp : PrecomputedWeights

        precomp.newPrecomputedWeights()
        var lagrange_coeffs : array[VerkleDomain, Fr[Banderwagon]]

        lagrange_coeffs.computeBarycentricCoefficients(precomp, point)

        var innerProd : Fr[Banderwagon]
        innerProd.computeInnerProducts(poly, lagrange_coeffs)

        # Verifier view 
        var verifier_comm : EC_P
        verifier_comm = prover_comm

        var verifier_transcript: sha256
        verifier_transcript.newTranscriptGen(asBytes"ipa")

        var ok: bool
        ok = ipaConfig.checkIPAProof(verifier_transcript, verifier_comm, ipaProof, point, innerProd)

        doAssert ok == true, "Issue in checking IPA proof!"
      testIPAProofCreateAndVerify()


# ############################################################
#
#                     Test for Multiproofs    
#
# ############################################################


suite "Multiproof Tests":
  test "IPA Config test for Multiproofs":
    proc testIPAConfigForMultiproofs()=
      var ipaConfig: IPASettings
      var ipaTranscript: IpaTranscript[sha256, 32]
      let stat1 = ipaConfig.genIPAConfig(ipaTranscript)
      doAssert stat1 == true, "Could not initialise new IPA config for multiproofs!"
    testIPAConfigForMultiproofs()
  
  test "Multiproof Creation and Verification":
    proc testMultiproofCreationAndVerification()=

      var ipaConfig: IPASettings
      var ipaTranscript: IpaTranscript[sha256, 32]
      let stat1 = ipaConfig.genIPAConfig(ipaTranscript)

      var testGeneratedPoints: array[256, EC_P]
      testGeneratedPoints.generate_random_points(ipaTranscript, 256)

      var testVals: array[14, uint64] = [1,1,1,4,5,6,7,8,9,10,11,12,13,14]
      var poly : array[256, Fr[Banderwagon]]

      poly.testPoly256(testVals)

      var precomp : PrecomputedWeights
      precomp.newPrecomputedWeights()

      #Prover's view
      var prover_transcript: sha256
      prover_transcript.newTranscriptGen(asBytes"multiproof")
      
      var prover_comm: EC_P
      prover_comm.pedersen_commit_varbasis(testGeneratedPoints,testGeneratedPoints.len, poly, poly.len)

      var one : Fr[Banderwagon]
      one.setOne()

      var Cs : array[VerkleDomain, EC_P]
      var Fs : array[VerkleDomain, array[VerkleDomain, Fr[Banderwagon]]]
      var Zs : array[VerkleDomain, uint8]
      var Ys : array[VerkleDomain, Fr[Banderwagon]]

      Cs[0] = prover_comm
      Fs[0] = poly
      Zs[0] = 1
      Ys[0] = one

      var multiproof: MultiProof
      var stat_create_mult: bool
      stat_create_mult = multiproof.createMultiProof(prover_transcript, ipaConfig, Cs, Fs, Zs, precomp, testGeneratedPoints)

      doAssert stat_create_mult.bool() == true, "Multiproof creation error!"

      #Verifier's view
      var verifier_transcript: sha256
      verifier_transcript.newTranscriptGen(asBytes"multiproof")

      var stat_verify_mult: bool
      stat_verify_mult = multiproof.verifyMultiproof(verifier_transcript,ipaConfig,Cs,Ys,Zs)

      doAssert stat_verify_mult.bool() == true, "Multiproof verification error!"

    testMultiproofCreationAndVerification()
