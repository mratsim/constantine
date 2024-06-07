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
  ../constantine/serialization/[
    codecs_status_codes,
    codecs_banderwagon,
    codecs
    ],
  ../constantine/math/config/[type_ff, curves],
  ../constantine/math/elliptic/[
    ec_twistededwards_projective
    ],
  ../constantine/math/io/[io_fields, io_bigints],
  ../constantine/math/arithmetic,
  ../constantine/math/constants/zoo_generators,
  ../tests/math_elliptic_curves/t_ec_template,
  ../constantine/ethereum_verkle_primitives,
  ../constantine/platforms/abstractions


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

      var point_a: Coord

      point_a.x.setZero()
      point_a.y.setZero()

      var point_b: Coord

      point_b.x.setOne()
      point_b.y.setOne()

      var points: array[2,Coord]
      points[0] = point_a
      points[1] = point_b

      var poly : array[2,Fr[Banderwagon]]

      poly.interpolate(points,2)

      var genfp: EC_P
      genfp.fromAffine(generator)
      var genfr: Fr[Banderwagon]
      genfr.mapToScalarField(genfp)

      var res {.noInit.}: Fr[Banderwagon]
      res.ipaEvaluate(poly,gen_fr,2)

      doAssert (res.toHex() == genfr.toHex()) == true, "Not matching!"

    testBasicInterpolation()

  test "Testing Barycentric Precompute Coefficients":
    proc testBarycentricPrecomputeCoefficients()=
        var p_outside_dom : Fr[Banderwagon]
        p_outside_dom.fromInt(3400)

        var testVals: array[10, int] = [1,2,3,4,5,6,7,8,9,10]

        var lagrange_values: array[256, Fr[Banderwagon]]
        lagrange_values.testPoly256(testVals)

        var precomp {.noInit.}: PrecomputedWeights
        precomp.newPrecomputedWeights()

        var bar_coeffs {.noInit.}: array[256, Fr[Banderwagon]]
        bar_coeffs.computeBarycentricCoefficients(precomp, p_outside_dom)

        var expected0: Fr[Banderwagon]
        expected0.computeInnerProducts(lagrange_values, bar_coeffs)

        var expected1: Fr[Banderwagon]
        expected1.evalOutsideDomain(precomp, lagrange_values, p_outside_dom)

        var points: array[VerkleDomain, Coord]
        for k in 0 ..< 256:
            var x_fr: Fr[Banderwagon]
            x_fr.fromInt(k)

            var point {.noInit.}: Coord
            point.x = x_fr
            point.y = lagrange_values[k]

            discard x_fr
            points[k] = point

        discard lagrange_values

        # testing with a no-precompute optimized Lagrange Interpolation value from Go-IPA
        doAssert expected0.toHex(littleEndian) == "0x50b9c3b3c42a06347e58d8d33047a7f8868965703567100657aceaf429562d04", "Barycentric Precompute and Lagrange should NOT give different values"
        doAssert expected0.toHex(littleEndian) == expected1.toHex(littleEndian), "Issue Barycentric Precomputes"

    testBarycentricPrecomputeCoefficients()

    test "Divide on Domain using Barycentric Precomputes":

      proc testDivideOnDomain()=

        var points: array[VerkleDomain, Coord]
        for k in 0 ..< VerkleDomain:
          var x: Fr[Banderwagon]
          x.fromInt(k)

          points[k].x = x
          var res: Fr[Banderwagon]
          res.evalFunc(x)
          points[k].y = res

        var precomp {.noInit.}: PrecomputedWeights
        precomp.newPrecomputedWeights()

        var indx = uint8(1)

        var evaluations: array[VerkleDomain, Fr[Banderwagon]]
        for i in 0 ..< VerkleDomain:
          evaluations[i] = points[i].y

        var quotient: array[VerkleDomain, Fr[Banderwagon]]
        quotient.divisionOnDomain(precomp, indx, evaluations)

        doAssert quotient[255].toHex(littleEndian) == "0x616b0e203a877177e2090013a77ce4ea8726941aac613b532002f3653d54250b", "Issue with Divide on Domain using Barycentric Precomputes!"

      testDivideOnDomain()




# ############################################################
#
#      Test for Random Point Generation and CRS Consistency
#
# ############################################################

suite "Random Elements Generation and CRS Consistency":
  test "Test for Generating Random Points and Checking the 1st and 256th point with the Verkle Spec":

    proc testGenPoints()=
      var ipaConfig {.noInit.}: IPASettings
      discard ipaConfig.genIPAConfig()

      var basisPoints {.noInit.}: array[256, EC_P]
      basisPoints.generate_random_points(256)

      var arr_byte {.noInit.}: array[256, array[32, byte]]
      discard arr_byte.serializeBatch(basisPoints)

      doAssert arr_byte[0].toHex() == "0x01587ad1336675eb912550ec2a28eb8923b824b490dd2ba82e48f14590a298a0", "Failed to generate the 1st point!"
      doAssert arr_byte[255].toHex() == "0x3de2be346b539395b0c0de56a5ccca54a317f1b5c80107b0802af9a62276a4d8", "Failed to generate the 256th point!"

    testGenPoints()

# ############################################################
#
#      Test for Computing the Correct Vector Commitment
#
# ############################################################
## Test vectors are in this link, as bigint strings
## https://github.com/jsign/verkle-test-vectors/blob/main/crypto/001_vector_commitment.json#L5-L261

suite "Computing the Correct Vector Commitment":
  test "Test for Vector Commitments from Verkle Test Vectors by @Ignacio":
    proc testVectorComm() =
      var ipaConfig: IPASettings
      discard ipaConfig.genIPAConfig()

      var basisPoints: array[256, EC_P]
      basisPoints.generate_random_points(256)


      var test_scalars {.noInit.}: array[256, Fr[Banderwagon]]
      for i in 0 ..< 256:
        test_scalars[i].fromHex(testScalarsHex[i])

      var commitment {.noInit.}: EC_P
      commitment.pedersen_commit_varbasis(basisPoints, basisPoints.len, test_scalars, test_scalars.len)

      var arr22 {.noInit.}: Bytes
      discard arr22.serialize(commitment)

      doAssert "0x524996a95838712c4580220bb3de453d76cffd7f732f89914d4417bc8e99b513" == arr22.toHex(), "bit string does not match expected"
    testVectorComm()


# #######################################################################################################
#
#          Test for Deserializing a Scalar whose final size is bigger than the Scalar Field Size
#
# ########################################################################################################

suite "Deserialize a proof which contains an invalid final scalar by @Ignacio":

  test "Deserialize a proof which contains a final scalar bigger than the field size (MUST fail)":

    proc testBiggerThanFieldSizeDeserialize() =
      var test_big {.noInit.}: matchingOrderBigInt(Banderwagon)

      var proof1_bytes = newSeq[byte](serializedProof1.len)
      proof1_bytes.fromHex(serializedProof1)

      var proof2_bytes: array[32, byte]

      for i in 0 ..< 32:
        proof2_bytes[i] = proof1_bytes[i]

      let stat1 = test_big.deserialize_scalar(proof2_bytes, littleEndian)

      doAssert stat1 != cttCodecScalar_Success, "This test should have FAILED"

    testBiggerThanFieldSizeDeserialize()

# #######################################################################################################
#
#          Test for Deserializing a Scalar whose final size is INVALID
#
# ########################################################################################################

suite "Deserialize a proof which wrong lengths by @Ignacio":

  test "Deserialize a proof which wrong lengths (all MUST fail)":

    proc testInvalidFieldSizeDeserialize() =

      var test_big {.noInit.}: array[3, matchingOrderBigInt(Banderwagon)]

      var i: int = 0

      while i != 3:
        var proof_bytes = newSeq[byte](serializedProofs2[2].len)
        proof_bytes.fromHex(serializedProofs2[i])

        var proof2_bytes: array[32, byte]

        for j in 0 ..< 32:
          proof2_bytes[j] = proof_bytes[j]

        let stat = test_big[i].deserialize_scalar(proof2_bytes, littleEndian)

        i = i + 1
        doAssert stat != cttCodecScalar_Success, "This test should FAIL"


    testInvalidFieldSizeDeserialize()

# ############################################################
#
#          Test for Transcript and Challenge Scalar
#
# ############################################################

suite "Transcript Tests":

  test "Transcript Testing with different challenge scalars to test randomness":

    proc testVec()=

      # Initializing a new transcript state
      var tr {.noInit.}: sha256
      # Generating with a new label
      tr.newTranscriptGen(asBytes"simple_protocol")

      # Generating Challenge Scalar
      var challenge1 {.noInit.}: matchingOrderBigInt(Banderwagon)
      challenge1.generateChallengeScalar(tr,asBytes"simple_challenge")

      var b1 {.noInit.}: array[32, byte]
      let stat = b1.serialize_scalar(challenge1, littleEndian)
      doAssert stat == cttCodecScalar_Success, "Serialization Failure"

      # Comparing with Go-IPA implementation
      doAssert b1.toHex() == "0xc2aa02607cbdf5595f00ee0dd94a2bbff0bed6a2bf8452ada9011eadb538d003", "Incorrect Value!"

    testVec()

  test "Transcript testing with same challenge scalar to test transcript correctness":

    proc testVec1()=

      # Initializing 2 new transcript states
      var tr {.noInit.}: sha256
      var tr2 {.noInit.}: sha256

      # Generating 2 new labels into 2 separate transcripts
      tr.newTranscriptGen(asBytes"simple_protocol")
      tr2.newTranscriptGen(asBytes"simple_protocol")

      # Generating Challenge Scalar for Transcript 1
      var challenge1 {.noInit.}: matchingOrderBigInt(Banderwagon)
      challenge1.generateChallengeScalar(tr,asBytes"ethereum_challenge")

      # Generating Challenge Scalar for Transcript 2
      var challenge2 {.noInit.}: matchingOrderBigInt(Banderwagon)
      challenge2.generateChallengeScalar(tr2,asBytes"ethereum_challenge")

      # Challenge 1 should be equal to Challenge 2 as both are coming from different transcript
      # states that are being handled similarly
      doAssert (challenge1 == challenge2).bool() == true , "calling ChallengeScalar twice should yield the same challenge"

    testVec1()

  test "Transcript testing with repititive append of scalars, thereby a compound challenge scalar":
    proc testVec2()=

      # Initializing a new transcript state
      var tr {.noInit.}: sha256

      # Generating with a new label
      tr.newTranscriptGen(asBytes"simple_protocol")

      var five {.noInit.} : matchingOrderBigInt(Banderwagon)
      five.fromUint(uint64(5))

      # Appending some scalars to the transcript state
      tr.scalarAppend(asBytes"five", five)
      tr.scalarAppend(asBytes"five again", five)

      var challenge {.noInit.}: matchingOrderBigInt(Banderwagon)
      challenge.generateChallengeScalar(tr, asBytes"simple_challenge")

      var c_bytes {.noInit.}: array[32, byte]
      discard c_bytes.serialize_scalar(challenge, littleEndian)

      # Comparing with Go-IPA Implmentation
      doAssert c_bytes.toHex() == "0x498732b694a8ae1622d4a9347535be589e4aee6999ffc0181d13fe9e4d037b0b", "Some issue in Challenge Scalar"

    testVec2()

    test "Transcript testing with +1 and -1, appending them to be a compound challenge scalar":
      proc testVec3() =

        # Initializing a new transcript state
        var tr {.noInit.}: sha256

        # Generating with a new label
        tr.newTranscriptGen(asBytes"simple_protocol")

        var one {.noInit.}: matchingOrderBigInt(Banderwagon)
        var minus_one {.noInit.}: Fr[Banderwagon]
        # As scalar append and generating challenge scalars mainly deal with BigInts
        # and BigInts usually store unsigned values, this test checks if the Transcript state
        # generates the correct challenge scalar, even when a signed BigInt such as -1 is
        # appended to the transcript state.
        minus_one.setMinusOne()

        # Here first `minus_one` is set to -1 MOD (Banderwagon Curve Order)
        # and then in-place converted to BigInt while append to the transcript state.
        one.setOne()

        # Constructing a Compound Challenge Scalar
        tr.scalarAppend(asBytes"-1", minus_one.toBig())
        tr.domainSeparator(asBytes"separate me")
        tr.scalarAppend(asBytes"-1 again", minus_one.toBig())
        tr.domainSeparator(asBytes"separate me again")
        tr.scalarAppend(asBytes"now 1", one)

        var challenge {.noInit.}: matchingOrderBigInt(Banderwagon)
        challenge.generateChallengeScalar(tr, asBytes"simple_challenge")

        var c_bytes {.noInit.}: array[32, byte]
        discard c_bytes.serialize_scalar(challenge, littleEndian)

        doAssert c_bytes.toHex() == "0x14f59938e9e9b1389e74311a464f45d3d88d8ac96adf1c1129ac466de088d618", "Computed challenge is incorrect!"

      testVec3()

    test "Transcript testing with point append":
      proc testVec4()=

        # Initializing a new transcript state
        var tr {.noInit.}: sha256

        # Generating with a new label
        tr.newTranscriptGen(asBytes"simple_protocol")

        var gen {.noInit.}: EC_P
        gen.fromAffine(Banderwagon.getGenerator())

        tr.pointAppend(asBytes"generator", gen)

        var challenge {.noInit.}: matchingOrderBigInt(Banderwagon)
        challenge.generateChallengeScalar(tr, asBytes"simple_challenge")

        doAssert challenge.toHex(littleEndian) == "0x8c2dafe7c0aabfa9ed542bb2cbf0568399ae794fc44fdfd7dff6cc0e6144921c", "Issue with pointAppend"
      testVec4()

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

  test "Verify IPA Proof inside the domain by @Ignacio":
    proc testIPAProofInDomain()=

      var commitmentBytes {.noInit.} : array[32, byte]
      commitmentBytes.fromHex(IPAPedersenCommitment)

      var commitment: EC_P
      discard commitment.deserialize(commitmentBytes)

      var evalPoint: Fr[Banderwagon]
      evalPoint.fromInt(IPAEvaluationPoint)

      var evaluationResultFr: Fr[Banderwagon]
      evaluationResultFr.fromHex(IPAEvaluationResultFr)

      var serializedIPAProof: VerkleIPAProofSerialized
      serializedIPAProof.fromHex(IPASerializedProofVec)

      var proof {.noInit.}: IPAProof
      discard proof.deserializeVerkleIPAProof(serializedIPAProof)

      var ipaConfig: IPASettings
      discard ipaConfig.genIPAConfig()

      var tr {.noInit.}: sha256
      tr.newTranscriptGen(asBytes"ipa")

      var ok: bool
      var got {.noInit.}: EC_P
      ok = ipaConfig.checkIPAProof(tr, got, commitment, proof, evalPoint, evaluationResultFr)

      doAssert ok == true, "ipaConfig.checkIPAProof: Unexpected Failure!"

    testIPAProofInDomain()
  test "Test for IPA proof consistency":
    proc testIPAProofConsistency()=

      #from a shared view
      var point: Fr[Banderwagon]
      point.fromInt(2101)

      #from the prover's side
      var testVals: array[256, int] = [
        1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32,
        1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32,
        1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32,
        1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32,
        1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32,
        1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32,
        1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32,
        1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32,
      ]
      var poly: array[256, Fr[Banderwagon]]
      poly.testPoly256(testVals)

      var ipaConfig {.noInit.}: IPASettings
      discard ipaConfig.genIPAConfig()

      var prover_transcript {.noInit.}: sha256
      prover_transcript.newTranscriptGen(asBytes"test")

      var prover_comm: EC_P
      prover_comm.pedersen_commit_varbasis(ipaConfig.SRS, ipaConfig.SRS.len, poly, poly.len)

      var pcb {.noInit.}: array[32, byte]
      discard pcb.serialize(prover_comm)

      doAssert pcb.toHex() == "0x1b9dff8f5ebbac250d291dfe90e36283a227c64b113c37f1bfb9e7a743cdb128", "Issue with computing commitment"

      var ipaProof1 {.noInit.}: IPAProof
      let stat11 = ipaProof1.createIPAProof(prover_transcript, ipaConfig, prover_comm, poly, point)
      doAssert stat11 == true, "Problem creating IPA proof 1"

      var lagrange_coeffs: array[256, Fr[Banderwagon]]
      lagrange_coeffs.computeBarycentricCoefficients(ipaConfig.precompWeights, point)

      var op_point: Fr[Banderwagon]
      op_point.computeInnerProducts(lagrange_coeffs, poly)


      doAssert op_point.toHex(littleEndian) == "0x4a353e70b03c89f161de002e8713beec0d740a5e20722fd5bd68b30540a33208", "Issue with computing commitment"

    testIPAProofConsistency()

  test "Test for IPA proof equality":
    proc testIPAProofEquality()=
      var prover_transcript {.noInit.}: sha256
      prover_transcript.newTranscriptGen(asBytes"ipa")

      # from a shared view
      var point: Fr[Banderwagon]
      point.fromInt(123456789)

      # from the prover's side
      var testVals: array[14, int] = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14]
      var poly: array[256, Fr[Banderwagon]]
      poly.testPoly256(testVals)

      var ipaConfig {.noInit.}: IPASettings
      discard ipaConfig.genIPAConfig()

      var arr_byte {.noInit.}: array[256, array[32, byte]]
      discard arr_byte.serializeBatch(ipaConfig.SRS)

      doAssert arr_byte[0].toHex() == "0x01587ad1336675eb912550ec2a28eb8923b824b490dd2ba82e48f14590a298a0", "Failed to generate the 1st point!"
      doAssert arr_byte[255].toHex() == "0x3de2be346b539395b0c0de56a5ccca54a317f1b5c80107b0802af9a62276a4d8", "Failed to generate the 256th point!"

      var prover_comm: EC_P
      prover_comm.pedersen_commit_varbasis(ipaConfig.SRS, ipaConfig.SRS.len, poly, poly.len)

      var ipaProof1 {.noInit.}: IPAProof
      let stat11 = ipaProof1.createIPAProof(prover_transcript, ipaConfig, prover_comm, poly, point)
      doAssert stat11 == true, "Problem creating IPA proof 1"

      var prv1_ser {.noInit.}: VerkleIPAProofSerialized
      discard prv1_ser.serializeVerkleIPAProof(ipaProof1)

      var point2: Fr[Banderwagon]
      point2.fromInt(123456789)

      var ipaConfig2 {.noInit.}: IPASettings
      discard ipaConfig2.genIPAConfig()

      var testGeneratedPoints2: array[256, EC_P]
      testGeneratedPoints2.generate_random_points(256)

      var prover_transcript2 {.noInit.}: sha256
      prover_transcript2.newTranscriptGen(asBytes"ipa")

      var testVals2: array[14, int] = [1,2,3,4,5,6,7,8,9,10,11,12,13,14]
      var poly2: array[256, Fr[Banderwagon]]
      poly2.testPoly256(testVals2)

      var prover_comm2 {.noInit.}: EC_P
      prover_comm2.pedersen_commit_varbasis(testGeneratedPoints2,testGeneratedPoints2.len, poly2, poly2.len)

      var ipaProof2 {.noInit.}: IPAProof
      let stat22 = ipaProof2.createIPAProof(prover_transcript2, ipaConfig, prover_comm, poly, point)
      doAssert stat22 == true, "Problem creating IPA proof 2"

      var stat33 = false
      stat33 = ipaProof1.isIPAProofEqual(ipaProof2)
      doAssert stat33 == true, "IPA proofs aren't equal"

    testIPAProofEquality()

    test "Test for IPA Proof of Creation and Verification":
      proc testIPAProofCreateAndVerify()=
        var point {.noInit.}: Fr[Banderwagon]
        var ipaConfig {.noInit.}: IPASettings
        discard ipaConfig.genIPAConfig()

        var testGeneratedPoints: array[256,EC_P]
        testGeneratedPoints.generate_random_points(256)

        # from a shared view
        point.fromInt(123456789)

        # from the prover's side
        var testVals : array[9, int] = [1,2,3,4,5,6,7,8,9]
        var poly: array[256,Fr[Banderwagon]]
        poly.testPoly256(testVals)

        var prover_comm {.noInit.}: EC_P
        prover_comm.pedersen_commit_varbasis(testGeneratedPoints, testGeneratedPoints.len,  poly, poly.len)

        var prover_transcript {.noInit.}: sha256
        prover_transcript.newTranscriptGen(asBytes"ipa")

        var ipaProof: IPAProof
        let stat = ipaProof.createIPAProof(prover_transcript, ipaConfig, prover_comm, poly, point)
        doAssert stat == true, "Problem creating IPA proof"

        var precomp {.noInit.}: PrecomputedWeights

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
        var got {.noInit.}: EC_P
        ok = ipaConfig.checkIPAProof(verifier_transcript, got, verifier_comm, ipaProof, point, innerProd)

        doAssert ok == true, "Issue in checking IPA proof!"
      testIPAProofCreateAndVerify()


# ############################################################
#
#                     Test for Multiproofs
#
# ############################################################

# Note: large arrays should be heap allocated with new/ref
#       to not incur stack overflow on Windows as its stack size is 1MB per default compared to UNIXes 8MB.

suite "Multiproof Tests":
  test "IPA Config test for Multiproofs":
    proc testIPAConfigForMultiproofs()=
      var ipaConfig: IPASettings
      let stat1 = ipaConfig.genIPAConfig()
      doAssert stat1 == true, "Could not initialise new IPA config for multiproofs!"
    testIPAConfigForMultiproofs()

  test "Multiproof Creation and Verification":
    proc testMultiproofCreationAndVerification()=

      var ipaConfig {.noInit.}: IPASettings
      discard ipaConfig.genIPAConfig()

      var testVals: array[14, int] = [1,1,1,4,5,6,7,8,9,10,11,12,13,14]
      var poly: array[256, Fr[Banderwagon]]

      poly.testPoly256(testVals)

      var prover_comm: EC_P
      prover_comm.pedersen_commit_varbasis(ipaConfig.SRS, ipaConfig.SRS.len, poly, poly.len)

      # Prover's view
      var prover_transcript {.noInit.}: sha256
      prover_transcript.newTranscriptGen(asBytes"multiproof")

      var one: Fr[Banderwagon]
      one.setOne()

      var Cs: seq[EC_P]
      # Large array, need heap allocation.
      # However using a ref array here makes the test fail. TODO.
      # expecially with address-sanitizer to reliably trigger the failure.
      var Fs: array[VerkleDomain, array[VerkleDomain, Fr[Banderwagon]]]

      for i in 0 ..< VerkleDomain:
        for j in 0 ..< VerkleDomain:
          Fs[i][j].setZero()

      var Zs: seq[int]
      var Ys: seq[Fr[Banderwagon]]

      Cs.add(prover_comm)

      Fs[0] = poly

      Zs.add(0)
      Ys.add(one)

      var multiproof {.noInit.}: MultiProof
      var stat_create_mult: bool
      stat_create_mult = multiproof.createMultiProof(prover_transcript, ipaConfig, Cs, Fs, Zs)

      doAssert stat_create_mult.bool() == true, "Multiproof creation error!"

      # Verifier's view
      var verifier_transcript: sha256
      verifier_transcript.newTranscriptGen(asBytes"multiproof")

      var stat_verify_mult: bool
      stat_verify_mult = multiproof.verifyMultiproof(verifier_transcript, ipaConfig, Cs, Ys,Zs)

      doAssert stat_verify_mult.bool() == true, "Multiproof verification error!"

    testMultiproofCreationAndVerification()

  test "Verify Multiproof in all Domain and Ranges but one by @Ignacio":
    proc testVerifyMultiproofVec()=

      var commitment_bytes {.noInit.}: array[32, byte]
      commitment_bytes.fromHex(MultiProofPedersenCommitment)

      var commitment {.noInit.}: EC_P
      discard commitment.deserialize(commitment_bytes)

      var evaluationResultFr {.noInit.}: Fr[Banderwagon]
      evaluationResultFr.fromHex(MultiProofEvaluationResult)

      var serializeVerkleMultiproof: VerkleMultiproofSerialized
      serializeVerkleMultiproof.fromHex(MultiProofSerializedVec)

      var multiproof {.noInit.}: MultiProof
      discard multiproof.deserializeVerkleMultiproof(serializeVerkleMultiproof)

      var ipaConfig {.noInit.}: IPASettings
      discard ipaConfig.genIPAConfig()

      var Cs: array[VerkleDomain, EC_P]
      var Zs: array[VerkleDomain, int]
      var Ys: array[VerkleDomain, Fr[Banderwagon]]

      Cs[0] = commitment
      Ys[0] = evaluationResultFr

      for i in 0 ..< VerkleDomain:
        var tr {.noInit.}: sha256
        tr.newTranscriptGen(asBytes"multiproof")
        Zs[0] = i
        var ok: bool
        ok = multiproof.verifyMultiproof(tr, ipaConfig, Cs, Ys, Zs)

        if i == MultiProofEvaluationPoint:
          doAssert ok == true, "Issue with Multiproof!"

    testVerifyMultiproofVec()

  test "Multiproof Serialization and Deserialization (Covers IPAProof Serialization and Deserialization as well)":
    proc testMultiproofSerDe() =

      ## Pull a valid Multiproof from a valid hex test vector as used in Go-IPA https://github.com/crate-crypto/go-ipa/blob/master/multiproof_test.go#L120-L121
      var validMultiproof_bytes {.noInit.} : VerkleMultiproofSerialized
      validMultiproof_bytes.fromHex(validMultiproof)

      var multiprv {.noInit.} : MultiProof

      ## Deserialize it into the Multiproof type
      let stat1 = multiprv.deserializeVerkleMultiproof(validMultiproof_bytes)
      doAssert stat1 == true, "Failed to Serialize Multiproof"

      discard validMultiproof_bytes

      ## Serialize the Multiproof type in to a serialize Multiproof byte array
      var validMultiproof_bytes2 {.noInit} : VerkleMultiproofSerialized
      let stat2 = validMultiproof_bytes2.serializeVerkleMultiproof(multiprv)
      doAssert stat2 == true, "Failed to Deserialize Multiproof"

      ## Check the serialized Multiproof with the valid hex test vector
      doAssert validMultiproof_bytes2.toHex() == validMultiproof, "Error in the Multiproof Process!"

    testMultiproofSerDe()
