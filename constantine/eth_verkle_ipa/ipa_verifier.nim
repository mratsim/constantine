# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  ./[transcript_gen, common_utils, barycentric_form, eth_verkle_constants, ipa_prover],
  ../platforms/primitives,
  ../math/config/[type_ff, curves],
  ../hashes,
  ../math/elliptic/[ec_multi_scalar_mul, ec_multi_scalar_mul_scheduler],
  ../math/elliptic/[ec_twistededwards_projective, ec_twistededwards_batch_ops],
  ../math/arithmetic,
  ../math/elliptic/ec_scalar_mul, 
  ../math/io/[io_fields],
  ../curves_primitives

# ############################################################
#
# All the util functions for Inner Product Arguments Verifier
#
# ############################################################

func generateChallengesForIPA*(res: var openArray[matchingOrderBigInt(Banderwagon)], transcript: var CryptoHash, proof: IPAProof) =
  for i in 0 ..< 8:
    transcript.pointAppend( asBytes"L", proof.L_vector[i])
    transcript.pointAppend( asBytes"R", proof.R_vector[i])
    res[i].generateChallengeScalar(transcript,asBytes"x")

func checkIPAProof* (ic: IPASettings, got: var EC_P, transcript: var CryptoHash, commitment: var EC_P, proof: IPAProof, evalPoint: Fr[Banderwagon], res: Fr[Banderwagon]) : bool = 
  # Check IPA proof verifier a IPA proof for a committed polynomial in evaluation form
  # It verifies whether the proof is valid for the given polynomial at the evaluation `evalPoint`
  # and cross-checking it with `result`
  var r {.noInit.} : bool

  transcript.domain_separator(asBytes"ipa")

  debug: doAssert (proof.L_vector.len == proof.R_vector.len), "Proof lengths unequal!"

  debug: doAssert (proof.L_vector.len == int(ic.numRounds)), "Proof length and num round unequal!"


  var b {.noInit.}: array[VerkleDomain, Fr[Banderwagon]]
  # b.computeBarycentricCoefficients(ic.precompWeights,evalPoint)
  b.populateCoefficientVector(ic, evalPoint)

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
  commitment += qy


  var challenges_big {.noInit.}: array[8, matchingOrderBigInt(Banderwagon)]
  challenges_big.generateChallengesForIPA(transcript, proof)

  var challenges {.noInit.}: array[8,Fr[Banderwagon]]
  for i in 0 ..< 8:
    challenges[i].fromBig(challenges_big[i])

  var challengesInv {.noInit.}: array[8,Fr[Banderwagon]] 
  challengesInv.batchInvert(challenges)

  for i in 0 ..< challenges.len:
    var x = challenges[i]
    var L = proof.L_vector[i]
    var R = proof.R_vector[i]

    var p11 {.noInit.}: array[3, EC_P]
    p11[0] = commitment
    p11[1] = L
    p11[2] = R

    var p22 {.noInit.}: array[3, Fr[Banderwagon]]
    var one {.noInit.}: Fr[Banderwagon]
    one.setOne()

    p22[0] = one
    p22[1] = x
    p22[2] = challengesInv[i]

    commitment.pedersen_commit_varbasis(p11, p11.len, p22, p22.len)

  var g {.noInit.}: array[VerkleDomain, EC_P]
  g = ic.SRS

  var foldingScalars {.noInit.}: array[g.len, Fr[Banderwagon]]

  for i in 0 ..< g.len:
    var scalar {.noInit.} : Fr[Banderwagon]
    scalar.setOne()

    for challengeIndex in 0 ..< challenges.len:
      let im = 1 shl (7 - challengeIndex)
      if ((i and im).int() > 0).bool() == true:
        scalar *= challengesInv[challengeIndex]

    foldingScalars[i] = scalar

  var g0 {.noInit.}: EC_P

  var foldingScalars_big {.noInit.} : array[g.len,matchingOrderBigInt(Banderwagon)]

  for i in 0 ..< VerkleDomain:
    foldingScalars_big[i] = foldingScalars[i].toBig()

  var g_aff {.noInit.} : array[VerkleDomain, EC_P_Aff]

  for i in 0 ..< VerkleDomain:
    g_aff[i].affine(g[i])

  g0.multiScalarMul_reference_vartime(foldingScalars_big, g_aff)

  var b0 {.noInit.} : Fr[Banderwagon]
  b0.computeInnerProducts(b, foldingScalars)

  # g0 * a + (a * b) * Q

  var p1 {.noInit.}: EC_P
  p1 = g0
  p1.scalarMul(proof.A_scalar.toBig())

  var p2 {.noInit.} : EC_P
  var p2a {.noInit.} : Fr[Banderwagon]

  p2a.prod(b0, proof.A_scalar)
  p2 = q
  p2.scalarMul(p2a.toBig())

  got.sum(p1, p2)

  if not(got == commitment).bool() == true:
    r = false
    return r

  r = true
  return r