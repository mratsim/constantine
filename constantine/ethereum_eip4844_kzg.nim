# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  std/typetraits,

  constantine/named/algebras,
  ./math/io/[io_bigints, io_fields],
  ./math/[ec_shortweierstrass, arithmetic, extension_fields],
  ./math/arithmetic/limbs_montgomery,
  ./math/polynomials/polynomials,
  ./math/arithmetic/bigints,
  ./commitments/kzg,
  ./hashes,
  ./platforms/[abstractions, allocs],
  ./serialization/[codecs_status_codes, codecs_bls12_381, endians],
  ./commitments_setups/ethereum_kzg_srs

export trusted_setup_load, trusted_setup_delete, TrustedSetupFormat, TrustedSetupStatus, EthereumKZGContext

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

const prefix_eth_kzg4844 = "ctt_eth_kzg_"
import ./zoo_exports

# Constants
# ------------------------------------------------------------
# Spec "ENDIANNESS" for deserialization is little-endian
# https://github.com/ethereum/consensus-specs/blob/v1.3.0/specs/phase0/beacon-chain.md#misc

const BYTES_PER_COMMITMENT = 48
# const BYTES_PER_PROOF = 48
const BYTES_PER_FIELD_ELEMENT* = 32

# Presets
# ------------------------------------------------------------

const FIELD_ELEMENTS_PER_BLOB* = 4096
const FIAT_SHAMIR_PROTOCOL_DOMAIN = asBytes"FSBLOBVERIFY_V1_"
const RANDOM_CHALLENGE_KZG_BATCH_DOMAIN = asBytes"RCKZGBATCH___V1_"

# Derived
# ------------------------------------------------------------
const BYTES_PER_BLOB = BYTES_PER_FIELD_ELEMENT*FIELD_ELEMENTS_PER_BLOB

# Protocol Types
# ------------------------------------------------------------

type
  Blob* = array[BYTES_PER_BLOB, byte]
    # C API note: an array will be passed by reference in C
    # while an object would be by value unless tagged {.byref.}
    # Hence we don't need to explicitly use ptr Blob
    # to avoid a 4096 byte copy on {.exportc.} procs.

  KZGCommitment* = distinct EC_ShortW_Aff[Fp[BLS12_381], G1]

  KZGProof*      = distinct EC_ShortW_Aff[Fp[BLS12_381], G1]

  cttEthKzgStatus* = enum
    cttEthKzg_Success
    cttEthKzg_VerificationFailure
    cttEthKzg_InputsLengthsMismatch
    cttEthKzg_ScalarZero
    cttEthKzg_ScalarLargerThanCurveOrder
    cttEthKzg_EccInvalidEncoding
    cttEthKzg_EccCoordinateGreaterThanOrEqualModulus
    cttEthKzg_EccPointNotOnCurve
    cttEthKzg_EccPointNotInSubGroup

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
          Fr[BLS12_381].getModulus().limbs,
          Fr[BLS12_381].getR2modP().limbs,
          Fr[BLS12_381].getNegInvModWord(),
          Fr[BLS12_381].getSpareBits())

func fromDigest(dst: var Fr[BLS12_381].getBigInt(), src: array[32, byte]) =
  ## Convert a SHA256 digest to an element in the scalar field Fr[BLS12-381]
  ## hash_to_bls_field: https://github.com/ethereum/consensus-specs/blob/v1.4.0-beta.1/specs/deneb/polynomial-commitments.md#hash_to_bls_field
  var scalar {.noInit.}: BigInt[256]
  scalar.unmarshal(src, bigEndian)

  discard dst.reduce_vartime(scalar, Fr[BLS12_381].getModulus())

func fiatShamirChallenge(
      dst: ptr (Fr[BLS12_381] or Fr[BLS12_381].getBigInt()),
      blob: Blob,
      commitmentBytes: array[BYTES_PER_COMMITMENT, byte]) =
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

  var opening_challenge {.noInit.}: array[32, byte]
  transcript.finish(opening_challenge)
  dst[].fromDigest(opening_challenge)

# Conversion
# ------------------------------------------------------------

func bytes_to_bls_bigint(dst: var Fr[BLS12_381].getBigInt(), src: array[32, byte]): CttCodecScalarStatus =
  ## Convert untrusted bytes to a trusted and validated BLS scalar field element.
  ## This function does not accept inputs greater than the BLS modulus.
  let status = dst.deserialize_scalar(src)
  if status notin {cttCodecScalar_Success, cttCodecScalar_Zero}:
    return status
  return cttCodecScalar_Success

func bytes_to_bls_field(dst: var Fr[BLS12_381], src: array[32, byte]): CttCodecScalarStatus =
  ## Convert untrusted bytes to a trusted and validated BLS scalar field element.
  ## This function does not accept inputs greater than the BLS modulus.
  var scalar {.noInit.}: Fr[BLS12_381].getBigInt()
  let status = scalar.deserialize_scalar(src)
  if status notin {cttCodecScalar_Success, cttCodecScalar_Zero}:
    return status
  dst.fromBig(scalar)
  return cttCodecScalar_Success

func bytes_to_kzg_commitment(dst: var KZGCommitment, src: array[48, byte]): CttCodecEccStatus =
  ## Convert untrusted bytes into a trusted and validated KZGCommitment.
  let status = dst.distinctBase().deserialize_g1_compressed(src)
  if status == cttCodecEcc_PointAtInfinity:
    # Point at infinity is allowed
    return cttCodecEcc_Success
  return status

func bytes_to_kzg_proof(dst: var KZGProof, src: array[48, byte]): CttCodecEccStatus =
  ## Convert untrusted bytes into a trusted and validated KZGProof.
  let status = dst.distinctBase().deserialize_g1_compressed(src)
  if status == cttCodecEcc_PointAtInfinity:
    # Point at infinity is allowed
    return cttCodecEcc_Success
  return status

func blob_to_bigint_polynomial(
       dst: ptr PolynomialEval[FIELD_ELEMENTS_PER_BLOB, Fr[BLS12_381].getBigInt()],
       blob: Blob): CttCodecScalarStatus =
  ## Convert a blob to a polynomial in evaluation form

  static:
    doAssert sizeof(dst[]) == sizeof(Blob)
    doAssert sizeof(array[FIELD_ELEMENTS_PER_BLOB, array[32, byte]]) == sizeof(Blob)

  let view = cast[ptr array[FIELD_ELEMENTS_PER_BLOB, array[32, byte]]](blob.unsafeAddr)

  for i in 0 ..< FIELD_ELEMENTS_PER_BLOB:
    let status = dst.evals[i].bytes_to_bls_bigint(view[i])
    if status != cttCodecScalar_Success:
      return status

  return cttCodecScalar_Success

func blob_to_field_polynomial(
       dst: ptr PolynomialEval[FIELD_ELEMENTS_PER_BLOB, Fr[BLS12_381]],
       blob: Blob): CttCodecScalarStatus =
  ## Convert a blob to a polynomial in evaluation form

  static:
    doAssert sizeof(dst[]) == sizeof(Blob)
    doAssert sizeof(array[FIELD_ELEMENTS_PER_BLOB, array[32, byte]]) == sizeof(Blob)

  let view = cast[ptr array[FIELD_ELEMENTS_PER_BLOB, array[32, byte]]](blob.unsafeAddr)

  for i in 0 ..< FIELD_ELEMENTS_PER_BLOB:
    let status = dst.evals[i].bytes_to_bls_field(view[i])
    if status != cttCodecScalar_Success:
      return status

  return cttCodecScalar_Success

# Ethereum KZG public API
# ------------------------------------------------------------
#
# We use a simple goto state machine to handle errors and cleanup (if allocs were done)
# and have 2 different checks:
# - Either we are in "HappyPath" section that shortcuts to resource cleanup on error
# - or there are no resources to clean and we can early return from a function.

template checkReturn(evalExpr: CttCodecScalarStatus): untyped {.dirty.} =
  # Translate codec status code to KZG status code
  # Beware of resource cleanup like heap allocation, this can early exit the caller.
  block:
    let status = evalExpr # Ensure single evaluation
    case status
    of cttCodecScalar_Success:                          discard
    of cttCodecScalar_Zero:                             discard
    of cttCodecScalar_ScalarLargerThanCurveOrder:       return cttEthKzg_ScalarLargerThanCurveOrder

template checkReturn(evalExpr: CttCodecEccStatus): untyped {.dirty.} =
  # Translate codec status code to KZG status code
  # Beware of resource cleanup like heap allocation, this can early exit the caller.
  block:
    let status = evalExpr # Ensure single evaluation
    case status
    of cttCodecEcc_Success:                             discard
    of cttCodecEcc_InvalidEncoding:                     return cttEthKzg_EccInvalidEncoding
    of cttCodecEcc_CoordinateGreaterThanOrEqualModulus: return cttEthKzg_EccCoordinateGreaterThanOrEqualModulus
    of cttCodecEcc_PointNotOnCurve:                     return cttEthKzg_EccPointNotOnCurve
    of cttCodecEcc_PointNotInSubgroup:                  return cttEthKzg_EccPointNotInSubGroup
    of cttCodecEcc_PointAtInfinity:                     discard

template check(Section: untyped, evalExpr: CttCodecScalarStatus): untyped {.dirty.} =
  # Translate codec status code to KZG status code
  # Exit current code block
  block:
    let status = evalExpr # Ensure single evaluation
    case status
    of cttCodecScalar_Success:                          discard
    of cttCodecScalar_Zero:                             discard
    of cttCodecScalar_ScalarLargerThanCurveOrder:       result = cttEthKzg_ScalarLargerThanCurveOrder; break Section

template check(Section: untyped, evalExpr: CttCodecEccStatus): untyped {.dirty.} =
  # Translate codec status code to KZG status code
  # Exit current code block
  block:
    let status = evalExpr # Ensure single evaluation
    case status
    of cttCodecEcc_Success:                             discard
    of cttCodecEcc_InvalidEncoding:                     result = cttEthKzg_EccInvalidEncoding; break Section
    of cttCodecEcc_CoordinateGreaterThanOrEqualModulus: result = cttEthKzg_EccCoordinateGreaterThanOrEqualModulus; break Section
    of cttCodecEcc_PointNotOnCurve:                     result = cttEthKzg_EccPointNotOnCurve; break Section
    of cttCodecEcc_PointNotInSubgroup:                  result = cttEthKzg_EccPointNotInSubGroup; break Section
    of cttCodecEcc_PointAtInfinity:                     discard

func blob_to_kzg_commitment*(
       ctx: ptr EthereumKZGContext,
       dst: var array[48, byte],
       blob: Blob): cttEthKzgStatus {.libPrefix: prefix_eth_kzg4844, tags:[Alloca, HeapAlloc, Vartime].} =
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
  ##   - and at the verification opening_challenge z.
  ##
  ##   with proof = [(p(τ) - p(z)) / (τ-z)]₁

  let poly = allocHeapAligned(PolynomialEval[FIELD_ELEMENTS_PER_BLOB, Fr[BLS12_381].getBigInt()], 64)

  block HappyPath:
    check HappyPath, poly.blob_to_bigint_polynomial(blob)

    var r {.noinit.}: EC_ShortW_Aff[Fp[BLS12_381], G1]
    kzg_commit(ctx.srs_lagrange_g1, r, poly[])
    discard dst.serialize_g1_compressed(r)

    result = cttEthKzg_Success

  freeHeapAligned(poly)
  return result

func compute_kzg_proof*(
       ctx: ptr EthereumKZGContext,
       proof_bytes: var array[48, byte],
       y_bytes: var array[32, byte],
       blob: Blob,
       z_bytes: array[32, byte]): cttEthKzgStatus {.libPrefix: prefix_eth_kzg4844, tags:[Alloca, HeapAlloc, Vartime].} =
  ## Generate:
  ## - A proof of correct evaluation.
  ## - y = p(z), the evaluation of p at the opening_challenge z, with p being the Blob interpreted as a polynomial.
  ##
  ## Mathematical description
  ##   [proof]₁ = [(p(τ) - p(z)) / (τ-z)]₁, with p(τ) being the commitment, i.e. the evaluation of p at the powers of τ
  ##   The notation [a]₁ corresponds to the scalar multiplication of a by the generator of 𝔾1
  ##
  ##   Verification can be done by verifying the relation:
  ##     proof.(τ - z) = p(τ)-p(z)
  ##   which doesn't require the full blob but only evaluations of it
  ##   - at τ, p(τ) is the commitment
  ##   - and at the verification opening_challenge z.

  # Random or Fiat-Shamir challenge
  var z {.noInit.}: Fr[BLS12_381]
  checkReturn z.bytes_to_bls_field(z_bytes)

  let poly = allocHeapAligned(PolynomialEval[FIELD_ELEMENTS_PER_BLOB, Fr[BLS12_381]], 64)

  block HappyPath:
    # Blob -> Polynomial
    check HappyPath, poly.blob_to_field_polynomial(blob)

    # KZG Prove
    var y {.noInit.}: Fr[BLS12_381]                         # y = p(z), eval at opening_challenge z
    var proof {.noInit.}: EC_ShortW_Aff[Fp[BLS12_381], G1] # [proof]₁ = [(p(τ) - p(z)) / (τ-z)]₁

    kzg_prove(
      ctx.srs_lagrange_g1,
      ctx.domain,
      y, proof,
      poly[],
      z)

    discard proof_bytes.serialize_g1_compressed(proof) # cannot fail
    y_bytes.marshal(y, bigEndian) # cannot fail
    result = cttEthKzg_Success

  freeHeapAligned(poly)
  return result

func verify_kzg_proof*(
       ctx: ptr EthereumKZGContext,
       commitment_bytes: array[48, byte],
       z_bytes: array[32, byte],
       y_bytes: array[32, byte],
       proof_bytes: array[48, byte]): cttEthKzgStatus {.libPrefix: prefix_eth_kzg4844, tags:[Alloca, Vartime].} =
  ## Verify KZG proof that p(z) == y where p(z) is the polynomial represented by "polynomial_kzg"

  var commitment {.noInit.}: KZGCommitment
  checkReturn commitment.bytes_to_kzg_commitment(commitment_bytes)

  var opening_challenge {.noInit.}: Fr[BLS12_381].getBigInt()
  checkReturn opening_challenge.bytes_to_bls_bigint(z_bytes)

  var eval_at_challenge {.noInit.}: Fr[BLS12_381].getBigInt()
  checkReturn eval_at_challenge.bytes_to_bls_bigint(y_bytes)

  var proof {.noInit.}: KZGProof
  checkReturn proof.bytes_to_kzg_proof(proof_bytes)

  let verif = kzg_verify(EC_ShortW_Aff[Fp[BLS12_381], G1](commitment),
                         opening_challenge, eval_at_challenge,
                         EC_ShortW_Aff[Fp[BLS12_381], G1](proof),
                         ctx.srs_monomial_g2.coefs[1])
  if verif:
    return cttEthKzg_Success
  else:
    return cttEthKzg_VerificationFailure

func compute_blob_kzg_proof*(
       ctx: ptr EthereumKZGContext,
       proof_bytes: var array[48, byte],
       blob: Blob,
       commitment_bytes: array[48, byte]): cttEthKzgStatus {.libPrefix: prefix_eth_kzg4844, tags:[Alloca, HeapAlloc, Vartime].} =
  ## Given a blob, return the KZG proof that is used to verify it against the commitment.
  ## This method does not verify that the commitment is correct with respect to `blob`.

  var commitment {.noInit.}: KZGCommitment
  checkReturn commitment.bytes_to_kzg_commitment(commitment_bytes)

  # Blob -> Polynomial
  let poly = allocHeapAligned(PolynomialEval[FIELD_ELEMENTS_PER_BLOB, Fr[BLS12_381]], 64)

  block HappyPath:
    # Blob -> Polynomial
    check HappyPath, poly.blob_to_field_polynomial(blob)

    # Fiat-Shamir opening_challenge
    var opening_challenge {.noInit.}: Fr[BLS12_381]
    opening_challenge.addr.fiatShamirChallenge(blob, commitment_bytes)

    # KZG Prove
    var y {.noInit.}: Fr[BLS12_381]                         # y = p(z), eval at opening_challenge z
    var proof {.noInit.}: EC_ShortW_Aff[Fp[BLS12_381], G1] # [proof]₁ = [(p(τ) - p(z)) / (τ-z)]₁

    kzg_prove(
      ctx.srs_lagrange_g1,
      ctx.domain,
      y, proof,
      poly[],
      opening_challenge)

    discard proof_bytes.serialize_g1_compressed(proof) # cannot fail

    result = cttEthKzg_Success

  freeHeapAligned(poly)
  return result

func verify_blob_kzg_proof*(
       ctx: ptr EthereumKZGContext,
       blob: Blob,
       commitment_bytes: array[48, byte],
       proof_bytes: array[48, byte]): cttEthKzgStatus {.libPrefix: prefix_eth_kzg4844, tags:[Alloca, HeapAlloc, Vartime].} =
  ## Given a blob and a KZG proof, verify that the blob data corresponds to the provided commitment.

  var commitment {.noInit.}: KZGCommitment
  checkReturn commitment.bytes_to_kzg_commitment(commitment_bytes)

  var proof {.noInit.}: KZGProof
  checkReturn proof.bytes_to_kzg_proof(proof_bytes)

  let poly = allocHeapAligned(PolynomialEval[FIELD_ELEMENTS_PER_BLOB, Fr[BLS12_381]], 64)

  block HappyPath:
    # Blob -> Polynomial
    check HappyPath, poly.blob_to_field_polynomial(blob)

    # Fiat-Shamir challenge
    var opening_challenge {.noInit.}: Fr[BLS12_381]
    var eval_at_challenge {.noInit.}: Fr[BLS12_381]
    opening_challenge.addr.fiatShamirChallenge(blob, commitment_bytes)
    ctx.domain.evalPolyAt(eval_at_challenge, poly[], opening_challenge)

    # KZG verification
    let verif = kzg_verify(EC_ShortW_Aff[Fp[BLS12_381], G1](commitment),
                          opening_challenge.toBig(), eval_at_challenge.toBig(),
                          EC_ShortW_Aff[Fp[BLS12_381], G1](proof),
                          ctx.srs_monomial_g2.coefs[1])
    if verif:
      result = cttEthKzg_Success
    else:
      result = cttEthKzg_VerificationFailure

  freeHeapAligned(poly)
  return result

func verify_blob_kzg_proof_batch*(
       ctx: ptr EthereumKZGContext,
       blobs: ptr UncheckedArray[Blob],
       commitments_bytes: ptr UncheckedArray[array[48, byte]],
       proof_bytes: ptr UncheckedArray[array[48, byte]],
       n: int,
       secureRandomBytes: array[32, byte]): cttEthKzgStatus {.libPrefix: prefix_eth_kzg4844, tags:[Alloca, HeapAlloc, Vartime].} =
  ## Verify `n` (blob, commitment, proof) sets efficiently
  ##
  ## `n` is the number of verifications set
  ## - if n is negative, this procedure returns verification failure
  ## - if n is zero, this procedure returns verification success
  ##
  ## `secureRandomBytes` random byte must come from a cryptographically secure RNG
  ## or computed through the Fiat-Shamir heuristic.
  ## It serves as a random number
  ## that is not in the control of a potential attacker to prevent potential
  ## rogue commitments attacks due to homomorphic properties of pairings,
  ## i.e. commitments that are linear combination of others and sum would be zero.

  if n < 0:
    return cttEthKzg_VerificationFailure
  if n == 0:
    return cttEthKzg_Success

  let commitments = allocHeapArrayAligned(KZGCommitment, n, alignment = 64)
  let opening_challenges = allocHeapArrayAligned(Fr[BLS12_381], n, alignment = 64)
  let evals_at_challenges = allocHeapArrayAligned(Fr[BLS12_381].getBigInt(), n, alignment = 64)
  let proofs = allocHeapArrayAligned(KZGProof, n, alignment = 64)
  let poly = allocHeapAligned(PolynomialEval[FIELD_ELEMENTS_PER_BLOB, Fr[BLS12_381]], alignment = 64)

  block HappyPath:
    for i in 0 ..< n:
      check HappyPath, commitments[i].bytes_to_kzg_commitment(commitments_bytes[i])
      check HappyPath, poly.blob_to_field_polynomial(blobs[i])
      opening_challenges[i].addr.fiatShamirChallenge(blobs[i], commitments_bytes[i])

      var eval_at_challenge_fr {.noInit.}: Fr[BLS12_381]
      ctx.domain.evalPolyAt(
        eval_at_challenge_fr,
        poly[], opening_challenges[i]
      )
      evals_at_challenges[i].fromField(eval_at_challenge_fr)

      check HappyPath, proofs[i].bytes_to_kzg_proof(proof_bytes[i])

    var randomBlindingFr {.noInit.}: Fr[BLS12_381]
    block blinding: # Ensure we don't multiply by 0 for blinding
      # 1. Try with the random number supplied
      for i in 0 ..< secureRandomBytes.len:
        if secureRandomBytes[i] != byte 0:
          randomBlindingFr.fromDigest(secureRandomBytes)
          break blinding
      # 2. If it's 0 (how?!), we just hash all the Fiat-Shamir challenges
      var transcript: sha256
      transcript.init()
      transcript.update(RANDOM_CHALLENGE_KZG_BATCH_DOMAIN)
      transcript.update(cast[ptr UncheckedArray[byte]](opening_challenges).toOpenArray(0, n*sizeof(Fr[BLS12_381])-1))

      var blindingBytes {.noInit.}: array[32, byte]
      transcript.finish(blindingBytes)
      randomBlindingFr.fromDigest(blindingBytes)

    let linearIndepRandNumbers = allocHeapArrayAligned(Fr[BLS12_381], n, alignment = 64)
    linearIndepRandNumbers.computePowers(randomBlindingFr, n)

    type EcAffArray = ptr UncheckedArray[EC_ShortW_Aff[Fp[BLS12_381], G1]]
    let verif = kzg_verify_batch(
                  cast[EcAffArray](commitments),
                  opening_challenges,
                  evals_at_challenges,
                  cast[EcAffArray](proofs),
                  linearIndepRandNumbers,
                  n,
                  ctx.srs_monomial_g2.coefs[1])
    if verif:
      result =  cttEthKzg_Success
    else:
      result = cttEthKzg_VerificationFailure

    freeHeapAligned(linearIndepRandNumbers)

  freeHeapAligned(poly)
  freeHeapAligned(proofs)
  freeHeapAligned(evals_at_challenges)
  freeHeapAligned(opening_challenges)
  freeHeapAligned(commitments)

  return result
