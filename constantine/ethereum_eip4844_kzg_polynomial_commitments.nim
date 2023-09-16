# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  ./math/config/curves,
  ./math/io/[io_bigints, io_fields],
  ./math/[ec_shortweierstrass, arithmetic, extension_fields],
  ./math/arithmetic/limbs_montgomery,
  ./math/elliptic/ec_multi_scalar_mul,
  ./math/polynomials/polynomials,
  ./commitments/kzg_polynomial_commitments,
  ./hashes,
  ./platforms/[abstractions, views, allocs],
  ./serialization/[codecs_status_codes, codecs_bls12_381, endians],
  ./trusted_setups/ethereum_kzg_srs

export loadTrustedSetup, TrustedSetupStatus, EthereumKZGContext

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
    cttEthKZG_VerificationFailure
    cttEthKZG_ScalarZero
    cttEthKZG_ScalarLargerThanCurveOrder
    cttEthKZG_EccInvalidEncoding
    cttEthKZG_EccCoordinateGreaterThanOrEqualModulus
    cttEthKZG_EccPointNotOnCurve
    cttEthKZG_EccPointNotInSubGroup

# Fiat-Shamir challenges
# ------------------------------------------------------------
# https://en.wikipedia.org/wiki/Fiat%E2%80%93Shamir_heuristic

func fromDigest(dst: var Fr[BLS12_381], src: array[32, byte]) =
  ## Convert a SHA256 digest to an element in the scalar field Fr[BLS12-381]
  ## hash_to_bls_field: https://github.com/ethereum/consensus-specs/blob/v1.4.0-beta.1/specs/deneb/polynomial-commitments.md#hash_to_bls_field
  var scalar {.noInit.}: BigInt[256]
  scalar.unmarshal(src, bigEndian)

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

  # Append the degree of polynomial as 16-byte big-endian integer as a domain separator
  transcript.update(default(array[16-sizeof(uint64), byte]))
  transcript.update(FIELD_ELEMENTS_PER_BLOB.uint64.toBytes(bigEndian))

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

func bytes_to_bls_bigint(dst: var matchingOrderBigInt(BLS12_381), src: array[32, byte]): CttCodecScalarStatus =
  ## Convert untrusted bytes to a trusted and validated BLS scalar field element.
  ## This function does not accept inputs greater than the BLS modulus.
  let status = dst.deserialize_scalar(src)
  if status notin {cttCodecScalar_Success, cttCodecScalar_Zero}:
    return status
  return cttCodecScalar_Success

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

func blob_to_bigint_polynomial(
       dst: ptr PolynomialEval[FIELD_ELEMENTS_PER_BLOB, matchingOrderBigInt(BLS12_381)],
       blob: ptr Blob): CttCodecScalarStatus =
  ## Convert a blob to a polynomial in evaluation form

  static:
    doAssert sizeof(dst[]) == sizeof(Blob)
    doAssert sizeof(array[FIELD_ELEMENTS_PER_BLOB, array[32, byte]]) == sizeof(Blob)

  let view = cast[ptr array[FIELD_ELEMENTS_PER_BLOB, array[32, byte]]](blob)

  for i in 0 ..< FIELD_ELEMENTS_PER_BLOB:
    let status = dst.evals[i].bytes_to_bls_bigint(view[i])
    if status != cttCodecScalar_Success:
      return status

  return cttCodecScalar_Success

func blob_to_field_polynomial(
       dst: ptr PolynomialEval[FIELD_ELEMENTS_PER_BLOB, Fr[BLS12_381]],
       blob: ptr Blob): CttCodecScalarStatus =
  ## Convert a blob to a polynomial in evaluation form

  static:
    doAssert sizeof(dst[]) == sizeof(Blob)
    doAssert sizeof(array[FIELD_ELEMENTS_PER_BLOB, array[32, byte]]) == sizeof(Blob)

  let view = cast[ptr array[FIELD_ELEMENTS_PER_BLOB, array[32, byte]]](blob)

  for i in 0 ..< FIELD_ELEMENTS_PER_BLOB:
    let status = dst.evals[i].bytes_to_bls_field(view[i])
    if status != cttCodecScalar_Success:
      return status

  return cttCodecScalar_Success

# Ethereum KZG public API
# ------------------------------------------------------------

template check(evalExpr: CttCodecScalarStatus): untyped =
  # Translate codec status code to KZG status code
  # Beware of resource cleanup like heap allocation, this can early exit the caller.
  block:
    let status = evalExpr # Ensure single evaluation
    case status
    of cttCodecScalar_Success:                          discard
    of cttCodecScalar_Zero:                             discard
    of cttCodecScalar_ScalarLargerThanCurveOrder:       return cttEthKZG_ScalarLargerThanCurveOrder

template check(evalExpr: CttCodecEccStatus): untyped =
  # Translate codec status code to KZG status code
  # Beware of resource cleanup like heap allocation, this can early exit the caller.
  block:
    let status = evalExpr # Ensure single evaluation
    case status
    of cttCodecEcc_Success:                             discard
    of cttCodecEcc_InvalidEncoding:                     return cttEthKZG_EccInvalidEncoding
    of cttCodecEcc_CoordinateGreaterThanOrEqualModulus: return cttEthKZG_EccCoordinateGreaterThanOrEqualModulus
    of cttCodecEcc_PointNotOnCurve:                     return cttEthKZG_EccPointNotOnCurve
    of cttCodecEcc_PointNotInSubgroup:                  return cttEthKZG_EccPointNotInSubGroup
    of cttCodecEcc_PointAtInfinity:                     discard

func blob_to_kzg_commitment*(
       ctx: ptr EthereumKZGContext,
       dst: var array[48, byte],
       blob: ptr Blob): CttEthKzgStatus =
  ## Compute a commitment to the `blob`.
  ## The commitment can be verified without needing the full `blob`
  ##
  ## Mathematical description
  ##   commitment = [p(τ)]₁
  ##
  ##   The blob data is used as a polynomial,
  ##   the polynomial is evaluated at powers of tau τ, a trusted setup.
  ##
  ##   Verification can be done by verifying the relation:
  ##     proof.(τ - z) = p(τ)-p(z)
  ##   which doesn't require the full blob but only evaluations of it
  ##   - at τ, p(τ) is the commitment
  ##   - and at the verification challenge z.
  ##
  ##   with proof = [(p(τ) - p(z)) / (τ-z)]₁
  let poly = allocHeapAligned(PolynomialEval[FIELD_ELEMENTS_PER_BLOB, matchingOrderBigInt(BLS12_381)], 64)
  let status = poly.blob_to_bigint_polynomial(blob)
  if status == cttCodecScalar_ScalarLargerThanCurveOrder:
    freeHeapAligned(poly)
    return cttEthKZG_ScalarLargerThanCurveOrder
  elif status != cttCodecScalar_Success:
    debugEcho "Unreachable status in blob_to_kzg_commitment: ", status
    debugEcho "Panicking ..."
    quit 1

  var r {.noinit.}: ECP_ShortW_Aff[Fp[BLS12_381], G1]
  kzg_commit(r, poly.evals, ctx.srs_lagrange_g1) # symbol resolution need explicit generics
  discard dst.serialize_g1_compressed(r)

  freeHeapAligned(poly)
  return cttEthKZG_Success

func compute_kzg_proof*(
       ctx: ptr EthereumKZGContext,
       proof_bytes: var array[48, byte],
       y_bytes: var array[32, byte],
       blob: ptr Blob,
       z_bytes: array[32, byte]): CttEthKzgStatus {.tags:[Alloca, HeapAlloc, Vartime].} =
  ## Generate:
  ## - y = p(z), the evaluation of p at the challenge z, with p being the Blob interpreted as a polynomial.
  ## - A zero-knowledge proof of correct evaluation.
  ##
  ## Mathematical description
  ##   [proof]₁ = [(p(τ) - p(z)) / (τ-z)]₁, with p(τ) being the commitment, i.e. the evaluation of p at the powers of τ
  ##   The notation [a]₁ corresponds to the scalar multiplication of a by the generator of 𝔾1
  ##
  ##   Verification can be done by verifying the relation:
  ##     proof.(τ - z) = p(τ)-p(z)
  ##   which doesn't require the full blob but only evaluations of it
  ##   - at τ, p(τ) is the commitment
  ##   - and at the verification challenge z.

  # Random or Fiat-Shamir challenge
  var z {.noInit.}: Fr[BLS12_381]
  var status = bytes_to_bls_field(z, z_bytes)
  if status != cttCodecScalar_Success:
    # cttCodecScalar_Zero is not possible
    return cttEthKZG_ScalarLargerThanCurveOrder

  # Blob -> Polynomial
  let poly = allocHeapAligned(PolynomialEval[FIELD_ELEMENTS_PER_BLOB, Fr[BLS12_381]], 64)
  status = poly.blob_to_field_polynomial(blob)
  if status == cttCodecScalar_ScalarLargerThanCurveOrder:
    freeHeapAligned(poly)
    return cttEthKZG_ScalarLargerThanCurveOrder
  elif status != cttCodecScalar_Success:
    debugEcho "Unreachable status in compute_kzg_proof: ", status
    debugEcho "Panicking ..."
    quit 1

  var y {.noInit.}: Fr[BLS12_381]                         # y = p(z), eval at challenge z
  var proof {.noInit.}: ECP_ShortW_Aff[Fp[BLS12_381], G1] # [proof]₁ = [(p(τ) - p(z)) / (τ-z)]₁

  kzg_prove(
    proof, y,
    poly[], ctx.domain,
    z, ctx.srs_lagrange_g1,
    isBitReversedDomain = true)

  discard proof_bytes.serialize_g1_compressed(proof) # cannot fail
  y_bytes.marshal(y, bigEndian) # cannot fail

  freeHeapAligned(poly)
  return cttEthKZG_Success

func verify_kzg_proof*(
       ctx: ptr EthereumKZGContext,
       commitment_bytes: array[48, byte],
       z_bytes: array[32, byte],
       y_bytes: array[32, byte],
       proof_bytes: array[48, byte]): CttEthKzgStatus {.tags:[Alloca, Vartime].} =
  ## Verify KZG proof that p(z) == y where p(z) is the polynomial represented by "polynomial_kzg"

  var commitment {.noInit.}: KZGCommitment
  check commitment.bytes_to_kzg_commitment(commitment_bytes)

  var challenge {.noInit.}: matchingOrderBigInt(BLS12_381)
  check challenge.bytes_to_bls_bigint(z_bytes)

  var eval_at_challenge {.noInit.}: matchingOrderBigInt(BLS12_381)
  check eval_at_challenge.bytes_to_bls_bigint(y_bytes)

  var proof {.noInit.}: KZGProof
  check proof.bytes_to_kzg_proof(proof_bytes)

  let verif = kzg_verify(commitment.raw, challenge, eval_at_challenge, proof.raw, ctx.srs_monomial_g2.coefs[1])
  if verif:
    return cttEthKZG_Success
  else:
    return cttEthKZG_VerificationFailure

func compute_blob_kzg_proof*(
       ctx: ptr EthereumKZGContext,
       proof_bytes: var array[48, byte],
       blob: ptr Blob,
       commitment_bytes: array[48, byte]): CttEthKzgStatus {.tags:[Alloca, HeapAlloc, Vartime].} =
  ## Given a blob, return the KZG proof that is used to verify it against the commitment.
  ## This method does not verify that the commitment is correct with respect to `blob`.

  var commitment {.noInit.}: KZGCommitment
  check commitment.bytes_to_kzg_commitment(commitment_bytes)

  # Blob -> Polynomial
  let poly = allocHeapAligned(PolynomialEval[FIELD_ELEMENTS_PER_BLOB, Fr[BLS12_381]], 64)
  var status = poly.blob_to_field_polynomial(blob)
  if status == cttCodecScalar_ScalarLargerThanCurveOrder:
    freeHeapAligned(poly)
    return cttEthKZG_ScalarLargerThanCurveOrder
  elif status != cttCodecScalar_Success:
    debugEcho "Unreachable status in compute_kzg_proof: ", status
    debugEcho "Panicking ..."
    quit 1

  var challenge {.noInit.}: Fr[BLS12_381]
  challenge.fiatShamirChallenge(blob[], commitment_bytes)

  var y {.noInit.}: Fr[BLS12_381]                         # y = p(z), eval at challenge z
  var proof {.noInit.}: ECP_ShortW_Aff[Fp[BLS12_381], G1] # [proof]₁ = [(p(τ) - p(z)) / (τ-z)]₁

  kzg_prove(
    proof, y,
    poly[], ctx.domain,
    challenge, ctx.srs_lagrange_g1,
    isBitReversedDomain = true)

  discard proof_bytes.serialize_g1_compressed(proof) # cannot fail

  freeHeapAligned(poly)
  return cttEthKZG_Success

func verify_blob_kzg_proof*(
       ctx: ptr EthereumKZGContext,
       blob: ptr Blob,
       commitment_bytes: array[48, byte],
       proof_bytes: array[48, byte]): CttEthKzgStatus {.tags:[Alloca, HeapAlloc, Vartime].} =
  ## Given a blob and a KZG proof, verify that the blob data corresponds to the provided commitment.

  var commitment {.noInit.}: KZGCommitment
  check commitment.bytes_to_kzg_commitment(commitment_bytes)

  var proof {.noInit.}: KZGProof
  check proof.bytes_to_kzg_proof(proof_bytes)

  # Blob -> Polynomial
  let poly = allocHeapAligned(PolynomialEval[FIELD_ELEMENTS_PER_BLOB, Fr[BLS12_381]], 64)
  var status = poly.blob_to_field_polynomial(blob)
  if status == cttCodecScalar_ScalarLargerThanCurveOrder:
    freeHeapAligned(poly)
    return cttEthKZG_ScalarLargerThanCurveOrder
  elif status != cttCodecScalar_Success:
    debugEcho "Unreachable status in compute_kzg_proof: ", status
    debugEcho "Panicking ..."
    quit 1

  var challengeFr {.noInit.}: Fr[BLS12_381]
  challengeFr.fiatShamirChallenge(blob[], commitment_bytes)

  var challenge, eval_at_challenge {.noInit.}: matchingOrderBigInt(BLS12_381)
  challenge.fromField(challengeFr)

  let invRootsMinusZ = allocHeapAligned(array[FIELD_ELEMENTS_PER_BLOB, Fr[BLS12_381]], alignment = 64)

  # Compute 1/(ωⁱ - z) with ω a root of unity, i in [0, N).
  # zIndex = i if ωⁱ - z == 0 (it is the i-th root of unity) and -1 otherwise.
  let zIndex = invRootsMinusZ[].inverseRootsMinusZ_vartime(
                                  ctx.domain, challengeFr,
                                  earlyReturnOnZero = true)

  if zIndex == -1:
    var eval_at_challenge_fr{.noInit.}: Fr[BLS12_381]
    eval_at_challenge_fr.evalPolyAt(
      poly[], challengeFr,
      invRootsMinusZ[],
      ctx.domain)
    eval_at_challenge.fromField(eval_at_challenge_fr)
  else:
    eval_at_challenge.fromField(poly.evals[zIndex])

  freeHeapAligned(invRootsMinusZ)
  freeHeapAligned(poly)

  let verif = kzg_verify(commitment.raw, challenge, eval_at_challenge, proof.raw, ctx.srs_monomial_g2.coefs[1])
  if verif:
    return cttEthKZG_Success
  else:
    return cttEthKZG_VerificationFailure

# Ethereum Trusted Setup
# ------------------------------------------------------------

# Temporary workaround, hardcoding the testing trusted setups

# To be removed, no modules that use heap allocation are used at runtime
import std/[os, strutils]

const TrustedSetupMainnet =
  currentSourcePath.rsplit(DirSep, 1)[0] /
  "trusted_setups" /
  "trusted_setup_ethereum_kzg_test_mainnet.tsif"

proc load_ethereum_kzg_test_trusted_setup_mainnet*(): ptr EthereumKZGContext =
  ## This is a convenience function for the Ethereum mainnet testing trusted setups.
  ## It is insecure and will be replaced once the KZG ceremony is done.

  let ctx = allocHeapAligned(EthereumKZGContext, alignment = 64)

  let tsStatus = ctx.loadTrustedSetup(TrustedSetupMainnet)
  doAssert tsStatus == tsSuccess, "\n[Trusted Setup Error] " & $tsStatus

  echo "Trusted Setup loaded successfully"
  return ctx

proc delete*(ctx: ptr EthereumKZGContext) =
  freeHeapAligned(ctx)