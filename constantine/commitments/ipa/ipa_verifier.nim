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
  ../../../constantine/math/elliptic/[ec_multi_scalar_mul, ec_multi_scalar_mul_scheduler],
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

func generateChallengesForIPA*(res: var openArray[matchingOrderBigInt(Banderwagon)], transcript: var sha256, proof: IPAProof)=
    for i in 0..<8:
        transcript.pointAppend( asBytes"L", proof.L_vector[i])
        transcript.pointAppend( asBytes"R", proof.R_vector[i])
        res[i].generateChallengeScalar(transcript,asBytes"x")


# Check IPA proof verifier a IPA proof for a committed polynomial in evaluation form
# It verifies whether the proof is valid for the given polynomial at the evaluation `evalPoint`
# and cross-checking it with `result`
func checkIPAProof*(r: var bool,transcript: var sha256, ic: IPASettings, commitment: var EC_P, proof: IPAProof, evalPoint: EC_P_Fr, res: EC_P_Fr) =

    transcript.domain_separator(asBytes"ipa")

    doAssert (proof.L_vector.len == proof.R_vector.len), "Proof lengths unequal!"

    doAssert (proof.L_vector.len == int(ic.numRounds)), "Proof length and num round unequal!"


    var b {.noInit.}: array[DOMAIN, EC_P_Fr]
    b.computeBarycentricCoefficients(ic.precompWeights,evalPoint)

    transcript.pointAppend(asBytes"C", commitment)
    transcript.scalarAppend(asBytes"input point", evalPoint.toBig())
    transcript.scalarAppend(asBytes"output point", res.toBig())

    var w : matchingOrderBigInt(Banderwagon)
    w.generateChallengeScalar(transcript,asBytes"w")

    # Rescaling of q read https://hackmd.io/mJeCRcawTRqr9BooVpHv5g#Re-defining-the-quotient
    var q {.noInit.}: EC_P
    q = ic.Q_val
    q.scalarMul(w)

    var qy {.noInit.}: EC_P
    qy = q
    qy.scalarMul(res.toBig())
    commitment.sum(commitment, qy)


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

        var p11: array[3, EC_P]
        p11[0] = commitment
        p11[1] = L
        p11[2] = R

        var p22: array[3, EC_P_Fr]
        var one: EC_P_Fr
        one.setOne()

        p22[0] = one
        p22[1] = x
        p22[2] = challengesInv[i]

        commitment.pedersen_commit_varbasis(p11, p11.len, p22, p22.len)

    var g {.noInit.}: array[DOMAIN, EC_P]
    g = ic.SRS
    
    var foldingScalars {.noInit.}: array[g.len, EC_P_Fr]

    for i in 0..<g.len:
        var scalar {.noInit.} : EC_P_Fr
        scalar.setOne()

        for challengeIndex in 0..<challenges.len:
            let im = 1 shl (7 - challengeIndex)
            if ((i and im).int() > 0).bool() == true:
                scalar.prod(scalar,challengesInv[challengeIndex])

        foldingScalars[i] = scalar

    var g0 {.noInit.}: EC_P
    
    var foldingScalars_big {.noInit.} : array[g.len,matchingOrderBigInt(Banderwagon)]
    
    for i in 0..<DOMAIN:
        foldingScalars_big[i] = foldingScalars[i].toBig()

    var g_aff {.noInit.} : array[DOMAIN, EC_P_Aff]

    for i in 0..<DOMAIN:
        g_aff[i].affine(g[i])
 
    g0.multiScalarMul_reference_vartime(foldingScalars_big, g_aff)

    var b0 {.noInit.} : EC_P_Fr
    b0.computeInnerProducts(b, foldingScalars)

    var got {.noInit.} : EC_P
    # g0 * a + (a * b) * Q

    var p1 {.noInit.}: EC_P
    p1 = g0
    p1.scalarMul(proof.A_scalar.toBig())

    var p2 {.noInit.} : EC_P
    var p2a {.noInit.} : EC_P_Fr

    p2a.prod(b0, proof.A_scalar)
    p2 = q
    p2.scalarMul(p2a.toBig())

    got.sum(p1, p2)

    if not(got == commitment).bool() == true:
        r = false
    
    r = true

    

        
