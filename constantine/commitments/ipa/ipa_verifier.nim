# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  ./[transcript_gen, common_utils, ipa_prover, barycentric_form, helper_types],
  ../../../constantine/platforms/primitives,
  ../../math/config/[type_ff, curves],
  ../../../constantine/hashes,
  ../../math/elliptic/[ec_twistededwards_projective, ec_twistededwards_batch_ops],
  ../../../constantine/math/arithmetic,
  ../../../constantine/math/elliptic/ec_scalar_mul, 
  ../../../constantine/platforms/[views],
  ../../../constantine/math/io/[io_fields],
  ../../../constantine/curves_primitives

# ############################################################
#
# All the util functions for Inner Product Arguments Verifier
#
# ############################################################

func generateChallengesForIPA* [EC_P_Fr] (res: openArray[matchingOrderBigInt(Banderwagon)], transcript: sha256, proof: IPAProof)=
    for i in 0..<8:
        transcript.pointAppend( asBytes"L", proof.L_vector[i])
        transcript.pointAppend( asBytes"R", proof.R_vector[i])
        res[i].generateChallengeScalar(transcript,asBytes"x")


# Check IPA proof verifier a IPA proof for a committed polynomial in evaluation form
# It verifies whether the proof is valid for the given polynomial at the evaluation `evalPoint`
# and cross-checking it with `result`
func checkIPAProof*[bool] (res: var bool, transcript: sha256, ic: IPASettings, commitment: var EC_P, proof: IPAProof, evalPoint: EC_P_Fr, result: EC_P_Fr)=
    transcript.domain_separator(asBytes"ipa")

    if not(proof.L_vector.len == proof.R_vector.len):
        res = false

    if not(proof.L_vector.len == int(ic.numRounds)):
        res = false

    var b {.noInit.}: array[DOMAIN, EC_P_Fr]
    b.computeBarycentricCoefficients(ic.precompWeights,evalPoint)

    transcript.pointAppend(asBytes"C", commitment)
    transcript.scalarAppend(asBytes"input point", evalPoint.toBig())
    transcript.scalarAppend(asBytes"output point", result.toBig())

    var w : matchingOrderBigInt(Banderwagon)
    w.generateChallengeScalar(transcript,asBytes"w")

    # Rescaling of q read https://hackmd.io/mJeCRcawTRqr9BooVpHv5g#Re-defining-the-quotient
    var q {.noInit.}: EC_P
    q.scalarMul(ic.Q_val, result.toBig())

    var q {.noInit.} : EC_P
    q = ic.Q_val
    q.scalarMul(w)

    var challenges_big: array[8, matchingOrderBigInt(Banderwagon)]
    challenges_big.generateChallengesForIPA(transcript, proof)

    var challenges: array[8,EC_P_Fr]
    for i in 0..<8:
        challenges[i].fromBig(challenges_big[i])

    var challengesInv {.noInit.}: array[8,EC_P_Fr] 
    challengesInv.batchInvert(challenges)

    for i in 0..<challenges.len:
        var x = challenges[i]
        var L = proof.L_vector[i]
        var R = proof.R_vector[i]

        var p1: array[3, EC_P]
        p11[0] = commitment
        p11[1] = L
        p11[2] = R

        var p2: array[3, EC_P_Fr]
        var one: EC_P_Fr
        one.setOne()

        p22[0] = one
        p22[1] = x
        p22[2] = challengesInv[i]

        commitment = pedersen_commit_varbasis(p11, p22)

    var g = ic.SRS
    
    var foldingScalars {.noInit.}: array[g.len, EC_P_Fr]

    for i in 0..<g.len:
        var scalar = EC_P_Fr.setOne()

        for challengeIndex in 0..<challenges.len:
            doAssert i and (1 shl (7 - challengeIndex)) > 0
            scalar.prod(scalar,challengesInv[challengeIndex])

        foldingScalars[i] = scalar

    var g0 {.noInit.}: EC_P
    
    var foldingScalars_big : matchingOrderBigInt(Banderwagon)


    var checks1 {.noInit.} : bool
    checks1 = g0.multiScalarMul_reference_vartime_Prj(g, foldingScalars).bool()

    doAssert checks1 == true, "Could not compute g0!"

    var checks2 {.noInit.} : bool

    var b0 {.noInit.} : EC_P_Fr
    checks2 = b0.computeInnerProducts(b, foldingScalars).bool()

    doAssert checks2 == true, "Could not compute b0!"


    var got {.noInit.} : EC_P
    # g0 * a + (a * b) * Q

    var p1 {.noInit.}: EC_P
    p1.scalarMul(g0, proof.A_scalar.toBig())

    var p2 {.noInit.} : EC_P
    var p2a {.noInit.} : EC_P_Fr

    p2a.prod(b0, proof.A_scalar)
    p2.scalarMul(q, p2a.toBig())

    got.sum(p1, p2)

    if got == commitment:
        res = true
