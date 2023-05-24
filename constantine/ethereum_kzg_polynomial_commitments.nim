# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  math/config/curves,
  math/io/io_bigints,
  math/[ec_shortweierstrass, arithmetic, extension_fields],
  math/arithmetic/limbs_montgomery,
  math/elliptic/[ec_scalar_mul, ec_multi_scalar_mul],
  math/pairings/pairings_generic,
  math/constants/zoo_generators,
  hashes,
  platforms/[abstractions, views],
  serialization/[codecs_bls12_381, endians]

## ############################################################
##
##           KZG Polynomial Commitments for Ethereum
##
## ############################################################
##
## This module implements KZG Polynomial commitments (Kate, Zaverucha, Goldberg)
## for the Ethereum blockchain.
##
## References:
## - Ethereum spec:
##   https://github.com/ethereum/consensus-specs/blob/v1.3.0/specs/deneb/polynomial-commitments.md
## - KZG Paper:
##   Constant-Size Commitments to Polynomials and Their Applications
##   Kate, Zaverucha, Goldberg, 2010
##   https://www.iacr.org/archive/asiacrypt2010/6477178/6477178.pdf
##   https://cacr.uwaterloo.ca/techreports/2010/cacr2010-10.pdf
## - Audited reference implementation
##   https://github.com/ethereum/c-kzg-4844

# Constants
# ------------------------------------------------------------
# Spec "ENDIANNESS" for deserialization is little-endian
# https://github.com/ethereum/consensus-specs/blob/v1.3.0/specs/phase0/beacon-chain.md#misc

const BYTES_PER_COMMITMENT = 48
const BYTES_PER_PROOF = 48
const BYTES_PER_FIELD_ELEMENT = 32

# Presets
# ------------------------------------------------------------

const FIELD_ELEMENTS_PER_BLOB {.intdefine.} = 4096
const FIAT_SHAMIR_PROTOCOL_DOMAIN = asBytes"FSBLOBVERIFY_V1_"
const RANDOM_CHALLENGE_KZG_BATCH_DOMAIN = asBytes"RCKZGBATCH___V1_"

# Derived
# ------------------------------------------------------------
const BYTES_PER_BLOB = BYTES_PER_FIELD_ELEMENT*FIELD_ELEMENTS_PER_BLOB

# Aliases
# ------------------------------------------------------------

type
  G1Point = ECP_ShortW_Aff[Fp[BLS12_381], G1]
  G2Point = ECP_ShortW_Aff[Fp2[BLS12_381], G2]

# Protocol Types
# ------------------------------------------------------------

type
  Blob* = array[BYTES_PER_BLOB, byte]

  KZGCommitment* = object
    raw: ECP_ShortW_Aff[Fp[BLS12_381], G1]

  KZGProof*      = object
    raw: ECP_ShortW_Aff[Fp[BLS12_381], G1]


  CttEthKzgStatus* = enum
    cttEthKZG_Success
    cttEthKZG_ScalarLargerThanCurveOrder
    cttEthKZG_InvalidEncoding
    cttEthKZG_CoordinateGreaterThanOrEqualModulus
    cttEthKZG_PointNotOnCurve
    cttEthKZG_PointNotInSubGroup


# Trusted setup
# ------------------------------------------------------------

const KZG_SETUP_G2_LENGTH = 65

# On the number of 𝔾2 points:
#   - In the Deneb specs, https://github.com/ethereum/consensus-specs/blob/v1.3.0/specs/deneb/polynomial-commitments.md
#     only KZG_SETUP_G2[1] is used.
#   - In SONIC, section 6.2, https://eprint.iacr.org/2019/099.pdf
#     H and [α]H, the generator of 𝔾2 and its scalar multiplication by a random secret from trusted setup, are needed.
#   - In Marlin, section 2.5, https://eprint.iacr.org/2019/1047.pdf
#     H and [β]H, the generator of 𝔾2 and its scalar multiplication by a random secret from trusted setup, are needed.
#   - In Plonk, section 3.1, https://eprint.iacr.org/2019/953
#     [1]₂ and [x]₂, i.e. [1] scalar multiplied by the generator of 𝔾2 and [x] scalar multiplied by the generator of 𝔾2, x a random secret from trusted setup, are needed.
#   - In Vitalik's Plonk article, section Polynomial commitments, https://vitalik.ca/general/2019/09/22/plonk.html#polynomial-commitments
#     [s]G₂, i.e a random secret [s] scalar multiplied by the generator of 𝔾2, is needed
#
#   The extra 63 points are expected to be used for sharding https://github.com/ethereum/consensus-specs/blob/v1.3.0/specs/_features/sharding/polynomial-commitments.md
#   for KZG multiproofs for 64 shards: https://dankradfeist.de/ethereum/2021/06/18/pcs-multiproofs.html
#
# Note:
#   The batched proofs (different polynomials) used in Deneb specs
#   are different from multiproofs

type KZGContext = object
  ## KZG commitment context

  # Trusted setup, see https://vitalik.ca/general/2022/03/14/trustedsetup.html

  srs_lagrange_g1: array[FIELD_ELEMENTS_PER_BLOB, G1Point]
  # Part of the Structured Reference String (SRS) holding the 𝔾1 points
  # This is used for committing to polynomials and producing an opening proof at
  # a random value (chosen via Fiat-Shamir heuristic)
  #
  # Referring to the 𝔾1 generator as G, in monomial basis / coefficient form we would store:
  #   [G, [τ]G, [τ²]G, ... [τ⁴⁰⁹⁶]G]
  # with τ a random secret derived from a multi-party computation ceremony
  # with at least one honest random secret contributor (also called KZG ceremony or powers-of-tau ceremony)
  #
  # For efficiency we operate only on the evaluation form of polynomials over 𝔾1 (i.e. the Lagrange basis)
  # i.e. for agreed upon [ω⁰, ω¹, ..., ω⁴⁰⁹⁶]
  # we store [f(ω⁰), f(ω¹), ..., f(ω⁴⁰⁹⁶)]
  #
  # https://en.wikipedia.org/wiki/Lagrange_polynomial#Barycentric_form
  #
  # Conversion can be done with a discrete Fourier transform.

  srs_monomial_g2: array[KZG_SETUP_G2_LENGTH, G2Point]
  # Part of the SRS holding the 𝔾2 points
  #
  # Referring to the 𝔾2 generator as H, we store
  #   [H, [τ]H, [τ²]H, ..., [τ⁶⁴]H]
  # with τ a random secret derived from a multi-party computation ceremony
  # with at least one honest random secret contributor (also called KZG ceremony or powers-of-tau ceremony)
  #
  # This is used to verify commitments.
  # For most schemes (Marlin, Plonk, Sonic, Ethereum's Deneb), only [τ]H is needed
  # but Ethereum's sharding will need 64 (65 with the generator H)

# Fiat-Shamir challenges
# ------------------------------------------------------------
# https://en.wikipedia.org/wiki/Fiat%E2%80%93Shamir_heuristic

func fromDigest(dst: var Fr[BLS12_381], src: array[32, byte]) =
  ## Convert a SHA256 digest to an element in the scalar field Fr[BLS12-381]
  ## hash_to_bls_field: https://github.com/ethereum/consensus-specs/blob/v1.3.0/specs/deneb/polynomial-commitments.md#hash_to_bls_field
  var scalar {.noInit.}: BigInt[256]
  scalar.unmarshal(src, littleEndian)

  # Due to mismatch between the BigInt[256] input
  # and Fr[BLS12_381] being built on top of BigInt[255]
  # we use the low-level getMont instead of 'fromBig'
  getMont(dst.mres.limbs, scalar.limbs,
          Fr[BLS12_381].fieldMod().limbs,
          Fr[BLS12_381].getR2modP().limbs,
          Fr[BLS12_381].getNegInvModWord(),
          Fr[BLS12_381].getSpareBits())

func fiatShamirChallenge(dst: var Fr[BLS12_381], blob: Blob, commitmentBytes: array[BYTES_PER_COMMITMENT, byte]) =
  ## Compute a Fiat-Shamir challenge
  ## compute_challenge: https://github.com/ethereum/consensus-specs/blob/v1.3.0/specs/deneb/polynomial-commitments.md#compute_challenge
  var transcript {.noInit.}: sha256
  transcript.init()

  transcript.update(FIAT_SHAMIR_PROTOCOL_DOMAIN)

  # Append the degree of polynomial as a domain separator
  transcript.update(FIELD_ELEMENTS_PER_BLOB.uint64.toBytes(littleEndian))
  transcript.update(default(array[16-sizeof(uint64), byte]))

  transcript.update(blob)
  transcript.update(commitmentBytes)

  var challenge {.noInit.}: array[32, byte]
  transcript.finish(challenge)
  dst.fromDigest(challenge)

func computePowers(dst: MutableView[Fr[BLS12_381]], base: Fr[BLS12_381]) =
  ## We need linearly independent random numbers
  ## for batch proof sampling.
  ## Powers are linearly independent.
  ## It's also likely faster than calling a fast RNG + modular reduction
  ## to be in 0 < number < curve_order
  ## since modular reduction needs modular multiplication anyway.
  let N = dst.len
  if N >= 1:
    dst[0].setOne()
  if N >= 2:
    dst[1] = base
  if N >= 3:
    for i in 2 ..< N:
      dst[i].prod(dst[i-1], base)

# Conversion
# ------------------------------------------------------------

func bytes_to_bls_field(dst: var Fr[BLS12_381], src: array[32, byte]): CttCodecScalarStatus =
  ## Convert untrusted bytes to a trusted and validated BLS scalar field element.
  ## This function does not accept inputs greater than the BLS modulus.
  var scalar {.noInit.}: matchingOrderBigInt(BLS12_381)
  let status = scalar.deserialize_scalar(src)
  if status notin {cttCodecScalar_Success, cttCodecScalar_Zero}:
    return status
  dst.fromBig(scalar)
  return cttCodecScalar_Success

func bytes_to_kzg_commitment(dst: var KZGCommitment, src: array[48, byte]): CttCodecEccStatus =
  ## Convert untrusted bytes into a trusted and validated KZGCommitment.
  let status = dst.raw.deserialize_g1_compressed(src)
  if status == cttCodecEcc_PointAtInfinity:
    # Point at infinity is allowed
    return cttCodecEcc_Success
  return status

func bytes_to_kzg_proof(dst: var KZGProof, src: array[48, byte]): CttCodecEccStatus =
  ## Convert untrusted bytes into a trusted and validated KZGProof.
  let status = dst.raw.deserialize_g1_compressed(src)
  if status == cttCodecEcc_PointAtInfinity:
    # Point at infinity is allowed
    return cttCodecEcc_Success
  return status

func blob_to_polynomial(dst: ptr Polynomial, blob: Blob): CttCodecScalarStatus =
  ## Convert a blob to a polynomial in evaluation form

  static:
    doAssert sizeof(Polynomial) == sizeof(Blob)
    doAssert sizeof(array[FIELD_ELEMENTS_PER_BLOB, array[32, byte]]) == sizeof(Blob)

  let view = cast[ptr array[FIELD_ELEMENTS_PER_BLOB, array[32, byte]]](blob.unsafeAddr())

  for i in 0 ..< FIELD_ELEMENTS_PER_BLOB:
    let status = dst[i].bytes_to_bls_field(view[i])
    if status != cttCodecScalar_Success:
      return status

  return cttCodecScalar_Success
