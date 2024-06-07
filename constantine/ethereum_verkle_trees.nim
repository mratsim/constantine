# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
 ./eth_verkle_ipa/[
    eth_verkle_constants,
    barycentric_form,
    common_utils,
    ipa_prover,
    ipa_verifier,
    multiproof,
    transcript_gen
 ]
# ############################################################
#
#           Generator for low-level Verkle Trees API
#
# ############################################################

# Ethereum Verkle Constants
# ------------------------------------------------------------
export
  eth_verkle_constants.EC_P,
  eth_verkle_constants.Point,
  eth_verkle_constants.Field,
  eth_verkle_constants.EC_P_Aff,
  eth_verkle_constants.IPAProof,
  eth_verkle_constants.MultiProof,
  eth_verkle_constants.VerkleDomain,
  eth_verkle_constants.PrecomputedWeights,
  eth_verkle_constants.IPASettings,
  eth_verkle_constants.VerkleSeed,
  eth_verkle_constants.Bytes,
  eth_verkle_constants.VerkleIPAProofSerialized,
  eth_verkle_constants.VerkleMultiproofSerialized,
  eth_verkle_constants.IpaTranscript,
  eth_verkle_constants.Coord,
  eth_verkle_constants.generator

# Barycentric Formula for Verkle
# ------------------------------------------------------------
export
  barycentric_form.newPrecomputedWeights,
  barycentric_form.computeBarycentricWeights,
  barycentric_form.computeBarycentricCoefficients,
  barycentric_form.getInvertedElement,
  barycentric_form.getWeightRatios,
  barycentric_form.getBarycentricInverseWeight,
  barycentric_form.divisionOnDomain

# Common Math Utils for Verkle
# ------------------------------------------------------------
export
  common_utils.generate_random_points,
  common_utils.computeInnerProducts,
  common_utils.computeInnerProducts,
  common_utils.foldScalars,
  common_utils.foldPoints,
  common_utils.computeNumRounds,
  common_utils.pedersen_commit_varbasis

# IPA Prover for Verkle
# ------------------------------------------------------------
export
  ipa_prover.genIPAConfig,
  ipa_prover.createIPAProof,
  ipa_prover.serializeVerkleIPAProof,
  ipa_prover.deserializeVerkleIPAProof,
  ipa_prover.isIPAProofEqual

# IPA Verifier for Verkle
# ------------------------------------------------------------
export
  ipa_verifier.generateChallengesForIPA,
  ipa_verifier.checkIPAProof

# Multiproof for Verkle
# ------------------------------------------------------------
export
  multiproof.domainToFrElem,
  multiproof.domainToFrElem,
  multiproof.computePowersOfElem,
  multiproof.createMultiProof,
  multiproof.verifyMultiProof,
  multiproof.serializeVerkleMultiproof,
  multiproof.deserializeVerkleMultiproof


# Transcript Utils for Verkle
# ------------------------------------------------------------
export
  transcript_gen.newTranscriptGen,
  transcript_gen.messageAppend,
  transcript_gen.messageAppend_u64,
  transcript_gen.domainSeparator,
  transcript_gen.pointAppend,
  transcript_gen.scalarAppend,
  transcript_gen.generateChallengeScalar
