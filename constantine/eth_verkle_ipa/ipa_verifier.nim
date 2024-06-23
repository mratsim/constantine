# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  ./[common_utils, eth_verkle_constants, ipa_prover],
  ../platforms/primitives,
  ../math/config/[type_ff, curves],
  ../hashes,
  ../math/elliptic/[ec_multi_scalar_mul, ec_multi_scalar_mul_scheduler],
  ../math/elliptic/ec_twistededwards_projective,
  ../math/arithmetic,
  ../math/io/[io_fields, io_ec],
  ../curves_primitives

# TODO: This file is deprecated, all functionality is being replaced
# by commitments/eth_verkle_ipa

# ############################################################
#
# All the util functions for Inner Product Arguments Verifier
#
# ############################################################

func generateChallengesForIPA*(res: var openArray[matchingOrderBigInt(Banderwagon)], transcript: var CryptoHash, proof: IPAProofDeprecated) =
  for i in 0 ..< 8: # TODO 8 is hardcoded
    transcript.absorb("L", proof.L_vector[i])
    transcript.absorb("R", proof.R_vector[i])
    transcript.squeezeChallenge("x", res[i])

func checkIPAProof* (ic: IPASettings, transcript: var CryptoHash, got: var EC_P, commitment: var EC_P_Aff, proof: IPAProofDeprecated, evalPoint: Fr[Banderwagon], res: Fr[Banderwagon]) : bool =
  # Check IPA proof verifier a IPA proof for a committed polynomial in evaluation form
  # It verifies whether the proof is valid for the given polynomial at the evaluation `evalPoint`
  # and cross-checking it with `result`
  var r {.noInit.} : bool

  transcript.domain_separator("ipa")

  debug: doAssert (proof.L_vector.len == proof.R_vector.len), "Proof lengths unequal!"
  debug: doAssert (proof.L_vector.len == int(ic.numRounds)), "Proof length and num round unequal!"

  var b {.noInit.}: array[EthVerkleDomain, Fr[Banderwagon]]
  ic.domain.getLagrangeBasisPolysAt(b, evalPoint)

  transcript.absorb("C", commitment)
  transcript.absorb("input point", evalPoint)
  transcript.absorb("output point", res)

  var w : matchingOrderBigInt(Banderwagon)
  transcript.squeezeChallenge("w", w)

  # Rescaling of q read https://hackmd.io/mJeCRcawTRqr9BooVpHv5g#Re-defining-the-quotient
  var q {.noInit.}: ECP_TwEdwards_Prj[Fp[Banderwagon]]
  q.fromAffine(Banderwagon.getGenerator())
  q.scalarMul_vartime(w)

  var qy {.noInit.} = q
  qy.scalarMul_vartime(res)

  var C: EC_P
  C.madd_vartime(qy, commitment)
  var commitment {.noInit.}: EC_P_Aff
  commitment.affine(C)

  var challenges {.noInit.}: array[8,Fr[Banderwagon]]
  for i in 0 ..< 8:
    transcript.absorb("L", proof.L_vector[i])
    transcript.absorb("R", proof.R_vector[i])
    transcript.squeezeChallenge("x", challenges[i])

  var challengesInv {.noInit.}: array[8,Fr[Banderwagon]]
  challengesInv.batchInv_vartime(challenges)

  # debugEcho "-----------------------"
  # debugEcho "u⁻¹"
  # for i in 0 ..< 8:
  #   debugEcho "  0: ", challengesInv[i].toHex()
  # debugEcho "-----------------------"

  for i in 0 ..< challenges.len:
    var x = challenges[i]
    var L = proof.L_vector[i]
    var R = proof.R_vector[i]

    var p11 {.noInit.}: array[3, EC_P_Aff]
    p11[0] = commitment
    p11[1] = L
    p11[2] = R

    var p22 {.noInit.}: array[3, Fr[Banderwagon]]
    var one {.noInit.}: Fr[Banderwagon]
    one.setOne()

    p22[0] = one
    p22[1] = x
    p22[2] = challengesInv[i]

    C.multiScalarMul_reference_vartime(p22, p11)
    commitment.affine(C)

    # debugEcho "  ", i, ": "
    # debugEcho "    x:   ", challenges[i].toHex()
    # debugEcho "    L:   ", proof.L_vector[i].toHex()
    # debugEcho "    x⁻¹: ", challengesInv[i].toHex()
    # debugEcho "    R:   ", proof.R_vector[i].toHex()

  # debugEcho "----"
  # debugEcho "∑ᵢ[uᵢ]Lᵢ + C' + ∑ᵢ[uᵢ⁻¹]Rᵢ: ", commitment.toHex()
  # debugEcho "----"

  var foldingScalars {.noInit.}: array[EthVerkleDomain, Fr[Banderwagon]]

  for i in 0 ..< EthVerkleDomain:
    var scalar {.noInit.} : Fr[Banderwagon]
    scalar.setOne()

    for challengeIndex in 0 ..< challenges.len:
      let im = 1 shl (7 - challengeIndex)
      if ((i and im).int() > 0).bool() == true:
        scalar *= challengesInv[challengeIndex]

    foldingScalars[i] = scalar

  var g0 {.noInit.}: EC_P

  var foldingScalars_big {.noInit.} : array[EthVerkleDomain, matchingOrderBigInt(Banderwagon)]

  for i in 0 ..< EthVerkleDomain:
    foldingScalars_big[i] = foldingScalars[i].toBig()

  # TODO, use optimized MSM - pending fix for https://github.com/mratsim/constantine/issues/390
  g0.multiScalarMul_reference_vartime(foldingScalars_big, ic.crs)
  # debugEcho "----"
  # debugEcho "g0: ", g0.toHex()
  # debugEcho "----"

  var b0 {.noInit.} : Fr[Banderwagon]
  b0.computeInnerProducts(b, foldingScalars)
  # debugEcho "----"
  # debugEcho "b0: ", b0.toHex()
  # debugEcho "----"

  # g0 * a + (a * b) * Q

  var p1 {.noInit.}: EC_P
  p1 = g0
  p1.scalarMul_vartime(proof.A_scalar)
  # debugEcho "----"
  # debugEcho "a0g0: ", p1.toHex()
  # debugEcho "----"

  var p2 {.noInit.} : EC_P
  var p2a {.noInit.} : Fr[Banderwagon]

  p2a.prod(b0, proof.A_scalar)
  p2 = q
  p2.scalarMul_vartime(p2a)
  # debugEcho "----"
  # debugEcho "a0b0Q: ", p2.toHex()
  # debugEcho "----"

  got.sum(p1, p2)
  C.fromAffine(commitment)

  if not(got == C).bool() == true:
    r = false
    return r

  r = true
  return r
