# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  ../hashes,
  ../serialization/[endians, codecs_banderwagon],
  ../math/[arithmetic, ec_twistededwards],
  constantine/named/algebras,
  ../math/io/io_bigints,
  ../math_arbitrary_precision/arithmetic/limbs_divmod_vartime,
  ../platforms/primitives

# ############################################################
#
#                      Transcripts
#
# ############################################################

# The implementation of the Ethereum Verkle Transcripts
# is akin to a cryptographic sponge with a duplex construction.
#
#  - https://github.com/crate-crypto/verkle-trie-ref/blob/master/ipa/transcript.py
#  - https://keccak.team/sponge_duplex.html
#
# Hence we use the absorb/squeeze names for the API.
#
# Otherwise, it seems like the industry is converging towards Merlin (like Jolt)
# - https://merlin.cool/
#   https://github.com/dalek-cryptography/merlin
# and Plonky3 DuplexChallenger (like SP1)
# - https://github.com/Plonky3/Plonky3/blob/33b94a8/challenger/src/duplex_challenger.rs
#
# Practical implementations for IPA
# - https://github.com/crate-crypto/verkle-trie-ref/blob/master/ipa/transcript.py
# - https://github.com/zcash/halo2/blob/halo2_proofs-0.3.0/halo2_proofs/src/transcript.rs
# - https://github.com/arkworks-rs/poly-commit/blob/12f5529/poly-commit/src/ipa_pc/mod.rs#L34-L44
#
# Unfortunately, while the cryptographic sponge-like API to absorb_entropy / squeeze_challenge
# is shared, the actual usage differs significantly:
# - Ethereum verkle trie uses polynomial labels for domain separation
# - Halo2 has no labels
# - arkworks has no labels and does not absorb commitments
#   https://github.com/arkworks-rs/poly-commit/issues/140
#   which likely exposes it to Weak Fiat-Shamir attacks.
#
# Weak-Fiat Shamir attacks are described in depth in
# - https://eprint.iacr.org/2023/691

type EthVerkleTranscript* = CryptoHash

func initTranscript*(ctx: var EthVerkleTranscript, label: openArray[char]) =
  ctx.init()
  ctx.update(label)

func domainSeparator*(ctx: var EthVerkleTranscript, label: openArray[char]) =
  # A domain separator is used to:
  # - Separate between adding elements to the transcript and squeezing elements out
  # - Separate sub-protocols
  ctx.update(label)

func absorb*(ctx: var EthVerkleTranscript, label: openArray[char], message: openArray[byte]) =
  ctx.update(label)
  ctx.update(message)

func absorb*(ctx: var EthVerkleTranscript, label: openArray[char], v: uint64) =
  ctx.update(label)
  ctx.update(v.toBytes(bigEndian))

func absorb*(ctx: var EthVerkleTranscript, label: openArray[char], point: EC_TwEdw[Fp[Banderwagon]]) =
  var bytes {.noInit.}: array[32, byte]
  bytes.serialize(point)
  ctx.absorb(label, bytes)

func absorb*(ctx: var EthVerkleTranscript, label: openArray[char], scalar: Fr[Banderwagon]) =
  var bytes {.noInit.}: array[32, byte]
  bytes.serialize_fr(scalar, littleEndian)
  ctx.absorb(label, bytes)

func absorb(ctx: var EthVerkleTranscript, label: openArray[char], scalar: Fr[Banderwagon].getBigInt()) =
  var bytes {.noInit.}: array[32, byte]
  bytes.serialize_scalar(scalar, littleEndian)
  ctx.absorb(label, bytes)

func squeezeChallenge*(ctx: var EthVerkleTranscript, label: openArray[char], challenge: var Fr[Banderwagon].getBigInt()) =
  ## Generating a challenge based on the Fiat-Shamir transform
  ctx.domainSeparator(label)

  # Finalise the transcript state into a hash
  var digest {.noInit.}: array[32, byte]
  ctx.finish(digest)

  var big {.noInit.}: BigInt[32*8]
  big.unmarshal(digest, littleEndian)
  discard challenge.reduce_vartime(big, Fr[Banderwagon].getModulus())

  # Reset the Transcript state & absorb the freshly generated challenge
  ctx.init()
  ctx.absorb(label, challenge)

func squeezeChallenge*(ctx: var EthVerkleTranscript, label: openArray[char], challenge: var Fr[Banderwagon]) =
  ## Generating a challenge based on the Fiat-Shamir transform
  var big {.noInit.}: Fr[Banderwagon].getBigInt()
  ctx.squeezeChallenge(label, big)
  challenge.fromBig(big)
