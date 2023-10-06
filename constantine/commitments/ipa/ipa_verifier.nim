# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  ./[transcript_gen, common_utils, ipa_prover, barycentric_form],
  ../../../constantine/platforms/primitives,
  ../../math/config/[type_ff, curves],
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

type
  EC_P* = ECP_TwEdwards_Prj[Fp[Banderwagon]]
  EC_P_Fr* = ECP_TwEdwards_Prj[Fr[Banderwagon]]

func generateChallengesForIPA* [EC_P_Fr] (res: var EC_P_Fr, transcript: Transcript, proof: IPAProof)=

    let challenges = array[proof.L_vector.len, EC_P_Fr]

    for i in 0..proof.L.len:
        transcript.pointAppend(proof.L_vector[i], asBytes"L")
        transcript.pointAppend(proof.R_vector[i], asBytes"R")
        challenges[i] = transcript.generateChallengeScalar(asBytes"x")

    res = challenges

# Check IPA proof verifier a IPA proof for a committed polynomial in evaluation form
# It verifies whether the proof is valid for the given polynomial at the evaluation `evalPoint`
# and cross-checking it with `result`
func checkIPAProof*[bool] (res: var bool, transcript: Transcript, ic: IPASettings, commitment: var EC_P, proof: IPAProof, evalPoint: EC_P_Fr, result: EC_P_Fr)=
    transcript.domain_separator(asBytes"ipa")

    if not(proof.L_vector.len == proof.R_vector.len):
        res = false

    if not(proof.L_vector.len == int(ic.numRounds)):
        res = false

    let b = ic.PrecomputedWeights.computeBarycentricCoefficients(evalPoint)

    transcript.pointAppend(commitment, asBytes"C")
    transcript.scalarAppend(evalPoint, asBytes"input point")
    transcript.scalarAppend(result, asBytes"output point")

    let w = transcript.generateChallengeScalar(asBytes"w")

    # Rescaling of q read https://hackmd.io/mJeCRcawTRqr9BooVpHv5g#Re-defining-the-quotient
    var q {.noInit.}: EC_P
    q.scalarMul(ic.Q_val, result.toBig())

    var qy {.noInit.}: EC_P
    qy.scalarMul(q, result.toBig())
    commitment.add(commitment, qy)

    let challenges = generateChallengesForIPA(transcript, proof)

    var challengesInv {.noInit.}: openArray[EC_P_Fr] 
    challengesInv.batchInvert(challenges)

    for i in 0..challenges.len:
        let x = challenges[i]
        let L = proof.L_vector[i]
        let R = proof.R_vector[i]

        commitment = pedersen_commit_single([commitment, L, R], [EC_P_Fr.setOne(), x, challengesInv[i]])

    let g = ic.SRS
    
    var foldingScalars {.noInit.}: array[g.len, EC_P_Fr]

    for i in 0..g.len:
        let scalar = EC_P_Fr.setOne()

        for challengeIndex in 0..challenges.len:
            doAssert i and (1 shl (7 - challengeIndex)) > 0
            scalar *= challengesInv[challengeIndex]

        foldingScalars[i] = scalar

    var g0 {.noInit.}: EC_P

    var checks1 {.noInit.} : bool
    checks1 = g0.multiScalarMul_reference_vartime_Prj(g, foldingScalars)

    debug: doAssert checks1 == true, "Could not compute g0!"

    var checks2 {.noInit.} : bool

    var b0 {.noInit.} : EC_P_Fr
    checks2 = b0.computeInnerProducts(b, foldingScalars)

    debug: doAssert checks2 == true, "Could not compute b0!"


    var got {.noInit.} : EC_P
    # g0 * a + (a * b) * Q

    var p1 {.noInit.}: EC_P
    p1.scalarMul(g0, proof.A_scalar.toBig())

    var p2 {.noInit.} : EC_P
    var p2a {.noInit.} : EC_P_Fr

    p2a.prod(b0, proof.A_scalar)
    p2.scalarMul(q, p2a.toBig())

    got.add(p1, p2)

    if got == commitment:
        res = true
