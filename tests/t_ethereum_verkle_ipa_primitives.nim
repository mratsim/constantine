# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

# TODO
# Refactor: https://github.com/mratsim/constantine/issues/396

import
  ./t_ethereum_verkle_ipa_test_helper,
  constantine/ethereum_verkle_ipa,
  constantine/hashes,
  std/unittest,
  constantine/serialization/[codecs, codecs_banderwagon, codecs_status_codes],
  constantine/named/algebras,
  constantine/math/ec_twistededwards,
  constantine/math/io/[io_fields, io_bigints],
  constantine/math/arithmetic,
  constantine/math/polynomials/polynomials,
  constantine/named/zoo_generators,
  constantine/commitments/[
    pedersen_commitments,
    eth_verkle_ipa,
    eth_verkle_transcripts,
    protocol_quotient_check],
  ../tests/math_elliptic_curves/t_ec_template,
  constantine/platforms/abstractions


# ############################################################
#
#   Tests for Barycentric Form using Precompute Optimisation
#
# ############################################################

# Please refer to https://hackmd.io/mJeCRcawTRqr9BooVpHv5g

suite "Barycentric Form Tests":
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

      var genfp: EC_TwEdw_Prj[Fp[Banderwagon]]
      genfp.setGenerator()
      var genfr: Fr[Banderwagon]
      genfr.mapToScalarField(genfp)

      var res {.noInit.}: Fr[Banderwagon]
      res.ipaEvaluate(poly,gen_fr,2)

      doAssert res.toHex() == genfr.toHex(), "Not matching!"

    testBasicInterpolation()

  test "Testing Barycentric Precompute Coefficients":
    func innerProduct[F](r: var F, a, b: openArray[F]) =
      ## Compute the inner product ⟨a, b⟩ = ∑aᵢ.bᵢ
      doAssert a.len == b.len
      r.setZero()
      for i in 0 ..< a.len:
        var t {.noInit.}: F
        t.prod(a[i], b[i])
        r += t

    proc testBarycentricPrecomputeCoefficients()=
        var p_outside_dom : Fr[Banderwagon]
        p_outside_dom.fromInt(3400)

        var testVals: array[10, int] = [1,2,3,4,5,6,7,8,9,10]

        var lagrange_values: PolynomialEval[256, Fr[Banderwagon]]
        lagrange_values.evals.testPoly256(testVals)

        var lindom: PolyEvalLinearDomain[256, Fr[Banderwagon]]
        lindom.setupLinearEvaluationDomain()

        var bar_coeffs {.noInit.}: array[256, Fr[Banderwagon]]
        lindom.computeLagrangeBasisPolysAt(bar_coeffs, p_outside_dom)

        var expected0: Fr[Banderwagon]
        expected0.innerProduct(lagrange_values.evals, bar_coeffs)

        var expected1: Fr[Banderwagon]
        lindom.evalPolyAt(expected1, lagrange_values, p_outside_dom)

        # testing with a no-precompute optimized Lagrange Interpolation value from Go-IPA
        doAssert expected0.toHex(littleEndian) == "0x50b9c3b3c42a06347e58d8d33047a7f8868965703567100657aceaf429562d04", "Barycentric Precompute and Lagrange should NOT give different values"
        doAssert expected0.toHex(littleEndian) == expected1.toHex(littleEndian), "Issue Barycentric Precomputes"

    testBarycentricPrecomputeCoefficients()

    test "Divide on Domain using Barycentric Precomputes":

      proc testDivideOnDomain()=

        func eval_f(x: Fr[Banderwagon]): Fr[Banderwagon] =
          # f is (X-1)(X+1)(X^253)
          var tmpa {.noInit.}: Fr[Banderwagon]
          var one {.noInit.}: Fr[Banderwagon]
          one.setOne()
          tmpa.diff(x, one)

          var tmpb {.noInit.}: Fr[Banderwagon]
          tmpb.sum(x, one)

          var tmpc = one
          for i in 0 ..< 253:
            tmpc *= x

          result.prod(tmpa, tmpb)
          result *= tmpc

        var points: array[EthVerkleDomain, Coord]
        for k in 0 ..< EthVerkleDomain:
          var x: Fr[Banderwagon]
          x.fromInt(k)

          points[k].x = x
          points[k].y = eval_f(x)

        var lindom: PolyEvalLinearDomain[256, Fr[Banderwagon]]
        lindom.setupLinearEvaluationDomain()

        var evaluations: PolynomialEval[EthVerkleDomain, Fr[Banderwagon]]
        for i in 0 ..< EthVerkleDomain:
          evaluations.evals[i] = points[i].y

        var quotient: PolynomialEval[EthVerkleDomain, Fr[Banderwagon]]
        lindom.getQuotientPolyInDomain(quotient, evaluations, zIndex = 1)

        doAssert quotient.evals[255].toHex(littleEndian) == "0x616b0e203a877177e2090013a77ce4ea8726941aac613b532002f3653d54250b", "Issue with Divide on Domain using Barycentric Precomputes!"

      testDivideOnDomain()




# ############################################################
#
#      Test for Random Point Generation and CRS Consistency
#
# ############################################################

# TODO: adapt to new reimplementation

# suite "Random Elements Generation and CRS Consistency":
#   test "Test for Generating Random Points and Checking the 1st and 256th point with the Verkle Spec":

#     proc testGenPoints()=
#       var ipaConfig {.noInit.}: IPASettings
#       ipaConfig.genIPAConfig()

#       var basisPoints {.noInit.}: array[256, EC_TwEdw_Aff[Fp[Banderwagon]]]
#       basisPoints.generate_random_points()

#       var p0 {.noInit.}, p255 {.noInit.}: array[32, byte]
#       p0.serialize(ipaConfig.crs[0])
#       p255.serialize(ipaConfig.crs[255])

#       doAssert p0.toHex() == "0x01587ad1336675eb912550ec2a28eb8923b824b490dd2ba82e48f14590a298a0", "Failed to generate the 1st point!"
#       doAssert p255.toHex() == "0x3de2be346b539395b0c0de56a5ccca54a317f1b5c80107b0802af9a62276a4d8", "Failed to generate the 256th point!"

#     testGenPoints()

# ############################################################
#
#      Test for Computing the Correct Vector Commitment
#
# ############################################################
## Test vectors are in this link, as bigint strings
## https://github.com/jsign/verkle-test-vectors/blob/main/crypto/001_vector_commitment.json#L5-L261

# TODO: adapt to new reimplementation

# suite "Computing the Correct Vector Commitment":
#   test "Test for Vector Commitments from Verkle Test Vectors by @Ignacio":
#     proc testVectorComm() =
#       var ipaConfig: IPASettings
#       ipaConfig.genIPAConfig()

#       var basisPoints: PolynomialEval[256, EC_TwEdw_Aff[Fp[Banderwagon]]]
#       basisPoints.evals.generate_random_points()

#       var test_scalars {.noInit.}: PolynomialEval[256, Fr[Banderwagon]]
#       for i in 0 ..< 256:
#         test_scalars.evals[i].fromHex(testScalarsHex[i])

#       var commitment {.noInit.}: EC_TwEdw_Prj[Fp[Banderwagon]]
#       basisPoints.pedersen_commit(commitment, test_scalars)

#       var arr22 {.noInit.}: Bytes
#       arr22.serialize(commitment)

#       doAssert "0x524996a95838712c4580220bb3de453d76cffd7f732f89914d4417bc8e99b513" == arr22.toHex(), "bit string does not match expected"
#     testVectorComm()


# #######################################################################################################
#
#          Test for Deserializing a Scalar whose final size is bigger than the Scalar Field Size
#
# ########################################################################################################

suite "Deserialize a proof which contains an invalid final scalar by @Ignacio":

  test "Deserialize a proof which contains a final scalar bigger than the field size (MUST fail)":

    proc testBiggerThanFieldSizeDeserialize() =
      var test_big {.noInit.}: Fr[Banderwagon].getBigInt()

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

      var test_big {.noInit.}: array[3, Fr[Banderwagon].getBigInt()]

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
      var tr {.noInit.}: sha256
      tr.initTranscript("simple_protocol")

      # Generating Challenge Scalar
      var challenge1 {.noInit.}: Fr[Banderwagon]
      tr.squeezeChallenge("simple_challenge", challenge1)

      var b1 {.noInit.}: array[32, byte]
      b1.serialize_fr(challenge1, littleEndian)

      # Comparing with Go-IPA implementation
      doAssert b1.toHex() == "0xc2aa02607cbdf5595f00ee0dd94a2bbff0bed6a2bf8452ada9011eadb538d003", "Incorrect Value!"

    testVec()

  test "Transcript testing with same challenge scalar to test transcript correctness":

    proc testVec1()=
      # Initializing 2 new transcript states
      var tr {.noInit.}: sha256
      var tr2 {.noInit.}: sha256

      # Generating 2 new labels into 2 separate transcripts
      tr.initTranscript("simple_protocol")
      tr2.initTranscript("simple_protocol")

      # Generating Challenge Scalar for Transcript 1
      var challenge1 {.noInit.}: Fr[Banderwagon]
      tr.squeezeChallenge("ethereum_challenge", challenge1)

      # Generating Challenge Scalar for Transcript 2
      var challenge2 {.noInit.}: Fr[Banderwagon]
      tr2.squeezeChallenge("ethereum_challenge", challenge2)

      # Challenge 1 should be equal to Challenge 2 as both are coming from different transcript
      # states that are being handled similarly
      doAssert (challenge1 == challenge2).bool() == true , "calling ChallengeScalar twice should yield the same challenge"

    testVec1()

  test "Transcript testing with repetitive append of scalars, thereby a compound challenge scalar":
    proc testVec2()=
      var tr {.noInit.}: sha256
      tr.initTranscript("simple_protocol")

      var five {.noInit.} : Fr[Banderwagon]
      five.fromUint(uint64(5))

      # Appending some scalars to the transcript state
      tr.absorb("five", five)
      tr.absorb("five again", five)

      var challenge {.noInit.}: Fr[Banderwagon]
      tr.squeezeChallenge("simple_challenge", challenge)

      var c_bytes {.noInit.}: array[32, byte]
      c_bytes.serialize_fr(challenge, littleEndian)

      # Comparing with Go-IPA Implmentation
      doAssert c_bytes.toHex() == "0x498732b694a8ae1622d4a9347535be589e4aee6999ffc0181d13fe9e4d037b0b", "Some issue in Challenge Scalar"

    testVec2()

    test "Transcript testing with +1 and -1, appending them to be a compound challenge scalar":
      proc testVec3() =

        # As scalar absorb and squeeze mainly deal with BigInts
        # and BigInts store unsigned values, this test checks if the Transcript state
        # generates the correct challenge scalar, even when a signed BigInt such as -1 is
        # appended to the transcript state.

        var tr {.noInit.}: sha256
        tr.initTranscript("simple_protocol")

        var one {.noInit.}: Fr[Banderwagon]
        var minus_one {.noInit.}: Fr[Banderwagon]
        minus_one.setMinusOne()
        one.setOne()

        # Constructing a Compound Challenge Scalar
        tr.absorb("-1", minus_one)
        tr.domainSeparator("separate me")
        tr.absorb("-1 again", minus_one)
        tr.domainSeparator("separate me again")
        tr.absorb("now 1", one)

        var challenge {.noInit.}: Fr[Banderwagon].getBigInt()
        tr.squeezeChallenge("simple_challenge", challenge)

        var bytes {.noInit.}: array[32, byte]
        bytes.serialize_scalar(challenge, littleEndian)

        doAssert bytes.toHex() == "0x14f59938e9e9b1389e74311a464f45d3d88d8ac96adf1c1129ac466de088d618", "Computed challenge is incorrect!"

      testVec3()

    test "Transcript testing with point append":
      proc testVec4()=
        var tr {.noInit.}: sha256
        tr.initTranscript("simple_protocol")
        tr.absorb("generator", Banderwagon.getGenerator())

        var challenge {.noInit.}: Fr[Banderwagon]
        tr.squeezeChallenge("simple_challenge", challenge)

        doAssert challenge.toHex(littleEndian) == "0x8c2dafe7c0aabfa9ed542bb2cbf0568399ae794fc44fdfd7dff6cc0e6144921c", "Issue with pointAppend"
      testVec4()

# ############################################################
#
#                     Test for IPA Proofs
#
# ############################################################

# TODO: missing serialization proof tests

suite "IPA proof tests":

  test "Verify IPA Proof inside the domain by @Ignacio":
    proc testIPAProofInDomain()=

      var commitmentBytes {.noInit.} : array[32, byte]
      commitmentBytes.fromHex(IPAPedersenCommitment)

      var commitment: EC_TwEdw_Aff[Fp[Banderwagon]]
      discard commitment.deserialize_vartime(commitmentBytes)

      var evalPoint: Fr[Banderwagon]
      evalPoint.fromInt(IPAEvaluationPoint)

      var evaluationResultFr: Fr[Banderwagon]
      evaluationResultFr.fromHex(IPAEvaluationResultFr)

      var proof_bytes: EthVerkleIpaProofBytes
      proof_bytes.fromHex(IPASerializedProofVec)
      var proof {.noInit.}: IpaProof[8, EC_TwEdw_Aff[Fp[Banderwagon]], Fr[Banderwagon]]
      let status = proof.deserialize(proof_bytes)
      doAssert status == cttEthVerkleIpa_Success

      var CRS: PolynomialEval[EthVerkleDomain, EC_TwEdw_Aff[Fp[Banderwagon]]]
      CRS.evals.generate_random_points()

      var domain: PolyEvalLinearDomain[EthVerkleDomain, Fr[Banderwagon]]
      domain.setupLinearEvaluationDomain()

      var tr {.noInit.}: sha256
      tr.initTranscript("ipa")

      let ok = ipa_verify(
        CRS, domain,
        tr, commitment,
        evalPoint,
        evaluationResultFr,
        proof)

      doAssert ok, "ipaConfig.checkIPAProof: Unexpected Failure!"

    testIPAProofInDomain()

  test "IPAProof Serialization and Deserialization":
    proc testIPAProofSerDe() =

      ## Pull a valid IPAProof from a valid hex test vector as used in Go-IPA https://github.com/crate-crypto/go-ipa/blob/b1e8a79/ipa/ipa_test.go#L128
      var validIPAProof_bytes {.noInit.}: EthVerkleIpaProofBytes
      validIPAProof_bytes.fromHex(validIPAProof)

      # Deserialize it into the IPAProof type
      var ipa_proof {.noInit.}: IpaProof[8, EC_TwEdw_Aff[Fp[Banderwagon]], Fr[Banderwagon]]
      let s1 = ipa_proof.deserialize(validIPAProof_bytes)
      doAssert s1 == cttEthVerkleIpa_Success, "Failed to deserialize IPA Proof"

      ## Serialize the IPAProof type in to a serialize IPAProof byte array
      var validIPAproof_bytes2 {.noInit} : EthVerkleIpaProofBytes
      validIPAproof_bytes2.serialize(ipa_proof)
      doAssert validIPAproof_bytes2.toHex() == validIPAProof, "Error in the IPAProof serialization!\n" & (block:
        "  expected: " & validIPAProof & "\n" &
        "  computed: " & validIPAproof_bytes2.toHex()
      )
    testIPAProofSerDe()

  test "Test for IPA proof consistency":
    proc testIPAProofConsistency()=
      # Common setup
      var opening_challenge: Fr[Banderwagon]
      opening_challenge.fromInt(2101)

      var CRS: PolynomialEval[EthVerkleDomain, EC_TwEdw_Aff[Fp[Banderwagon]]]
      CRS.evals.generate_random_points()

      var domain: PolyEvalLinearDomain[EthVerkleDomain, Fr[Banderwagon]]
      domain.setupLinearEvaluationDomain()

      # Committer's side
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
      var poly: PolynomialEval[256, Fr[Banderwagon]]
      poly.evals.testPoly256(testVals)

      var comm: EC_TwEdw_Prj[Fp[Banderwagon]]
      CRS.pedersen_commit(comm, poly)
      var commitment: EC_TwEdw_Aff[Fp[Banderwagon]]
      commitment.affine(comm)

      var C {.noInit.}: array[32, byte]
      C.serialize(commitment)
      doAssert C.toHex() == "0x1b9dff8f5ebbac250d291dfe90e36283a227c64b113c37f1bfb9e7a743cdb128", "Issue with computing commitment"

      # Prover's side
      var prover_transcript {.noInit.}: sha256
      prover_transcript.initTranscript("test")

      var proof {.noInit.}: IpaProof[8, EC_TwEdw_Aff[Fp[Banderwagon]], Fr[Banderwagon]]
      var eval_at_challenge {.noInit.}: Fr[Banderwagon]
      CRS.ipa_prove(
        domain, prover_transcript,
        eval_at_challenge, proof,
        poly, commitment,
        opening_challenge)

      doAssert eval_at_challenge.toHex(littleEndian) == "0x4a353e70b03c89f161de002e8713beec0d740a5e20722fd5bd68b30540a33208", "Issue with computing commitment"

      var prover_challenge {.noInit.}: Fr[Banderwagon]
      prover_transcript.squeezeChallenge("state", prover_challenge)
      doAssert prover_challenge.toHex(littleEndian) == "0x0a81881cbfd7d7197a54ebd67ed6a68b5867f3c783706675b34ece43e85e7306", "Issue with squeezing prover challenge"

      # Verifier's side
      var verifier_transcript: sha256
      verifier_transcript.initTranscript("test")

      let verif = CRS.ipa_verify(
        domain, verifier_transcript,
        commitment, opening_challenge,
        eval_at_challenge, proof
      )
      doAssert verif, "Issue in checking IPA proof!"

    testIPAProofConsistency()

  test "Test for IPA Proof of Creation and Verification":
    proc testIPAProofCreateAndVerify()=
      # Common setup
      var opening_challenge: Fr[Banderwagon]
      opening_challenge.fromInt(2101)

      var CRS: PolynomialEval[EthVerkleDomain, EC_TwEdw_Aff[Fp[Banderwagon]]]
      CRS.evals.generate_random_points()

      var domain: PolyEvalLinearDomain[EthVerkleDomain, Fr[Banderwagon]]
      domain.setupLinearEvaluationDomain()

      # Committer's side
      var testVals : array[9, int] = [1,2,3,4,5,6,7,8,9]
      var poly: PolynomialEval[256, Fr[Banderwagon]]
      poly.evals.testPoly256(testVals)

      var comm: EC_TwEdw_Prj[Fp[Banderwagon]]
      CRS.pedersen_commit(comm, poly)
      var commitment: EC_TwEdw_Aff[Fp[Banderwagon]]
      commitment.affine(comm)

      # Prover's side
      var prover_transcript {.noInit.}: sha256
      prover_transcript.initTranscript("ipa")

      var proof {.noInit.}: IpaProof[8, EC_TwEdw_Aff[Fp[Banderwagon]], Fr[Banderwagon]]
      var eval_at_challenge {.noInit.}: Fr[Banderwagon]
      CRS.ipa_prove(
        domain, prover_transcript,
        eval_at_challenge, proof,
        poly, commitment,
        opening_challenge)

      # Verifier's side
      var verifier_transcript: sha256
      verifier_transcript.initTranscript("ipa")

      let verif = CRS.ipa_verify(
        domain, verifier_transcript,
        commitment, opening_challenge,
        eval_at_challenge, proof
      )
      doAssert verif, "Issue in checking IPA proof!"
    testIPAProofCreateAndVerify()


# ############################################################
#
#                     Test for Multiproofs
#
# ############################################################

# Note: large arrays should be heap allocated with new/ref
#       to not incur stack overflow on Windows as its stack size is 1MB per default compared to UNIXes 8MB.

# TODO: refactor completely the tests - https://github.com/mratsim/constantine/issues/396

suite "Multiproof Tests":
  test "Test for Multiproof Consistency":
    proc testMultiproofConsistency() =

      # Common setup
      var opening_challenges: array[2, Fr[Banderwagon]] # to be added ipa_multi_verify once ready
      opening_challenges[0].setOne()
      opening_challenges[1].fromInt(32)

      var opening_challenges_in_domain: array[2, uint8]
      opening_challenges_in_domain[0] = 0'u8
      opening_challenges_in_domain[1] = 0'u8

      var CRS: PolynomialEval[EthVerkleDomain, EC_TwEdw_Aff[Fp[Banderwagon]]]
      CRS.evals.generate_random_points()

      var domain: PolyEvalLinearDomain[EthVerkleDomain, Fr[Banderwagon]]
      domain.setupLinearEvaluationDomain()

      # Committer's side
      var testVals1: array[256, int] = [
        1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32,
        1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32,
        1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32,
        1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32,
        1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32,
        1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32,
        1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32,
        1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32,
      ]

      var testVals2: array[256, int] = [
        32, 31, 30, 29, 28, 27, 26, 25, 24, 23, 22, 21, 20, 19, 18, 17, 16, 15, 14, 13, 12, 11, 10, 9, 8, 7, 6, 5, 4, 3, 2, 1,
        32, 31, 30, 29, 28, 27, 26, 25, 24, 23, 22, 21, 20, 19, 18, 17, 16, 15, 14, 13, 12, 11, 10, 9, 8, 7, 6, 5, 4, 3, 2, 1,
        32, 31, 30, 29, 28, 27, 26, 25, 24, 23, 22, 21, 20, 19, 18, 17, 16, 15, 14, 13, 12, 11, 10, 9, 8, 7, 6, 5, 4, 3, 2, 1,
        32, 31, 30, 29, 28, 27, 26, 25, 24, 23, 22, 21, 20, 19, 18, 17, 16, 15, 14, 13, 12, 11, 10, 9, 8, 7, 6, 5, 4, 3, 2, 1,
        32, 31, 30, 29, 28, 27, 26, 25, 24, 23, 22, 21, 20, 19, 18, 17, 16, 15, 14, 13, 12, 11, 10, 9, 8, 7, 6, 5, 4, 3, 2, 1,
        32, 31, 30, 29, 28, 27, 26, 25, 24, 23, 22, 21, 20, 19, 18, 17, 16, 15, 14, 13, 12, 11, 10, 9, 8, 7, 6, 5, 4, 3, 2, 1,
        32, 31, 30, 29, 28, 27, 26, 25, 24, 23, 22, 21, 20, 19, 18, 17, 16, 15, 14, 13, 12, 11, 10, 9, 8, 7, 6, 5, 4, 3, 2, 1,
        32, 31, 30, 29, 28, 27, 26, 25, 24, 23, 22, 21, 20, 19, 18, 17, 16, 15, 14, 13, 12, 11, 10, 9, 8, 7, 6, 5, 4, 3, 2, 1,
      ]

      var polys: array[2, PolynomialEval[256, Fr[Banderwagon]]]
      polys[0].evals.testPoly256(testVals1)
      polys[1].evals.testPoly256(testVals2)

      var comm_1: EC_TwEdw_Prj[Fp[Banderwagon]]
      CRS.pedersen_commit(comm_1, polys[0])

      var comm_2: EC_TwEdw_Prj[Fp[Banderwagon]]
      CRS.pedersen_commit(comm_2, polys[1])

      var commitments: array[2, EC_TwEdw_Aff[Fp[Banderwagon]]]
      commitments[0].affine(comm_1)
      commitments[1].affine(comm_2)

      # Prover's side
      var prover_transcript {.noInit.}: sha256
      prover_transcript.initTranscript("test")

      var multiproof: IpaMultiProof[8, EC_TwEdw_Aff[Fp[Banderwagon]], Fr[Banderwagon]]

      CRS.ipa_multi_prove(
        domain, prover_transcript,
        multiproof, polys,
        commitments, opening_challenges_in_domain)

      var prover_challenge {.noInit.}: Fr[Banderwagon]
      prover_transcript.squeezeChallenge("state", prover_challenge)
      doAssert prover_challenge.toHex(littleEndian) == "0xeee8a80357ff74b766eba39db90797d022e8d6dee426ded71234241be504d519", "Issue with squeezing the prover challenge"

      testMultiproofConsistency()

  test "Multiproof Creation and Verification":
    proc testMultiproofCreationAndVerification()=

      var CRS: PolynomialEval[EthVerkleDomain, EC_TwEdw_Aff[Fp[Banderwagon]]]
      CRS.evals.generate_random_points()

      var domain: PolyEvalLinearDomain[EthVerkleDomain, Fr[Banderwagon]]
      domain.setupLinearEvaluationDomain()

      var testVals: array[14, int] = [1,1,1,4,5,6,7,8,9,10,11,12,13,14]
      var poly: PolynomialEval[256, Fr[Banderwagon]]
      poly.evals.testPoly256(testVals)

      var prover_comm: EC_TwEdw_Prj[Fp[Banderwagon]]
      CRS.pedersen_commit(prover_comm, poly)
      var C: EC_TwEdw_Aff[Fp[Banderwagon]]
      C.affine(prover_comm)

      # Prover's view
      var prover_transcript {.noInit.}: sha256
      prover_transcript.initTranscript("multiproof")

      var multiproof {.noInit.}: IpaMultiProof[8, EC_TwEdw_Aff[Fp[Banderwagon]], Fr[Banderwagon]]
      CRS.ipa_multi_prove(
        domain, prover_transcript,
        multiproof, [poly], [C], [0'u32]
      )
      
      # Verifier's view
      var verifier_transcript: sha256
      verifier_transcript.initTranscript("multiproof")

      let ok = CRS.ipa_multi_verify(domain, verifier_transcript, [C], [0'u32], [Fr[Banderwagon].fromUint(1'u32)], multiproof)

      doAssert ok, "Multiproof verification error!"

    testMultiproofCreationAndVerification()

# TODO: the following test, extracted from test011 in
#       https://github.com/jsign/verkle-test-vectors/blob/735b7d6/crypto/clients/go-ipa/crypto_test.go#L320-L326
#       is incomplete as it does not do negative testing.
#       but does seems like multiproof verification always return true.

  # test "Verify Multiproof in all Domain and Ranges but one by @Ignacio":
  #   proc testVerifyMultiproofVec()=

  #     var commitment_bytes {.noInit.}: array[32, byte]
  #     commitment_bytes.fromHex(MultiProofPedersenCommitment)

  #     var commitment {.noInit.}: EC_P
  #     discard commitment.deserialize(commitment_bytes)

  #     var evaluationResultFr {.noInit.}: Fr[Banderwagon]
  #     evaluationResultFr.fromHex(MultiProofEvaluationResult)

  #     var serializeVerkleMultiproof: VerkleMultiproofSerialized
  #     serializeVerkleMultiproof.fromHex(MultiProofSerializedVec)

  #     var multiproof {.noInit.}: MultiProof
  #     discard multiproof.deserializeVerkleMultiproof(serializeVerkleMultiproof)

  #     var ipaConfig {.noInit.}: IPASettings
  #     ipaConfig.genIPAConfig()

  #     var Cs: array[EthVerkleDomain, EC_P]
  #     var Zs: array[EthVerkleDomain, int]
  #     var Ys: array[EthVerkleDomain, Fr[Banderwagon]]

  #     Cs[0] = commitment
  #     Ys[0] = evaluationResultFr

  #     for i in 0 ..< EthVerkleDomain:
  #       var tr {.noInit.}: sha256
  #       tr.initTranscript("multiproof")
  #       Zs[0] = i
  #       var ok: bool
  #       ok = multiproof.verifyMultiproof(tr, ipaConfig, Cs, Ys, Zs)

  #       if i == MultiProofEvaluationPoint:
  #         doAssert ok == true, "Issue with Multiproof!"

  #   testVerifyMultiproofVec()

  test "Multiproof Serialization and Deserialization (Covers IPAProof Serialization and Deserialization as well)":
    proc testMultiproofSerDe() =

      ## Pull a valid Multiproof from a valid hex test vector as used in Go-IPA https://github.com/crate-crypto/go-ipa/blob/master/multiproof_test.go#L120-L121
      var validMultiproof_bytes {.noInit.}: EthVerkleIpaMultiProofBytes
      validMultiproof_bytes.fromHex(validMultiproof)

      ## Deserialize it into the Multiproof type
      var multiproof {.noInit.}: IpaMultiProof[8, EC_TwEdw_Aff[Fp[Banderwagon]], Fr[Banderwagon]]
      let s1 = multiproof.deserialize(validMultiproof_bytes)
      doAssert s1 == cttEthVerkleIpa_Success, "Failed to deserialize Multiproof"

      ## Serialize the Multiproof type in to a serialize Multiproof byte array
      var validMultiproof_bytes2 {.noInit} : EthVerkleIpaMultiProofBytes
      validMultiproof_bytes2.serialize(multiproof)
      doAssert validMultiproof_bytes2.toHex() == validMultiproof, "Error in the multiproof serialization!\n" & (block:
        "  expected: " & validMultiproof & "\n" &
        "  computed: " & validMultiproof_bytes2.toHex()
      )

    testMultiproofSerDe()

# TODO - missing tests from:
# - https://github.com/crate-crypto/verkle-trie-ref/blob/2332ab8/multiproof/multiproof_test.py
# - https://github.com/crate-crypto/go-ipa/blob/b1e8a79/multiproof_test.go
# - https://github.com/crate-crypto/rust-verkle/blob/442174e/ipa-multipoint/src/multiproof.rs
