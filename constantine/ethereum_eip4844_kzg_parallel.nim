# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import ethereum_eip4844_kzg {.all.}
export ethereum_eip4844_kzg

import
  ./math/config/curves,
  ./math/[ec_shortweierstrass, arithmetic, extension_fields],
  ./math/polynomials/polynomials_parallel,
  ./hashes,
  ./commitments/kzg_polynomial_commitments_parallel,
  ./serialization/[codecs_status_codes, codecs_bls12_381],
  ./math/io/io_fields,
  ./platforms/[abstractions, allocs],
  ./threadpool/threadpool

## ############################################################
##
##           KZG Polynomial Commitments for Ethereum
##                    Parallel Edition
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

proc blob_to_bigint_polynomial_parallel(
       tp: Threadpool,
       dst: ptr PolynomialEval[FIELD_ELEMENTS_PER_BLOB, matchingOrderBigInt(BLS12_381)],
       blob: ptr Blob): CttCodecScalarStatus =
  ## Convert a blob to a polynomial in evaluation form
  mixin globalStatus

  static:
    doAssert sizeof(dst[]) == sizeof(Blob)
    doAssert sizeof(array[FIELD_ELEMENTS_PER_BLOB, array[32, byte]]) == sizeof(Blob)

  let view = cast[ptr array[FIELD_ELEMENTS_PER_BLOB, array[32, byte]]](blob)

  tp.parallelFor i in 0 ..< FIELD_ELEMENTS_PER_BLOB:
    captures: {dst, view}
    reduceInto(globalStatus: CttCodecScalarStatus):
      prologue:
        var workerStatus = cttCodecScalar_Success
      forLoop:
        let iterStatus = dst.evals[i].bytes_to_bls_bigint(view[i])
        if workerStatus == cttCodecScalar_Success:
          # Propagate errors, if any it comes from current iteration
          workerStatus = iterStatus
      merge(remoteFutureStatus: Flowvar[CttCodecScalarStatus]):
        let remoteStatus = sync(remoteFutureStatus)
        if workerStatus == cttCodecScalar_Success:
          # Propagate errors, if any it comes from remote worker
          workerStatus = remoteStatus
      epilogue:
        return workerStatus

  return sync(globalStatus)

proc blob_to_field_polynomial_parallel_async(
       tp: Threadpool,
       dst: ptr PolynomialEval[FIELD_ELEMENTS_PER_BLOB, Fr[BLS12_381]],
       blob: ptr Blob): Flowvar[CttCodecScalarStatus] =
  ## Convert a blob to a polynomial in evaluation form
  ## The result is a `Flowvar` handle and MUST be awaited with `sync`
  mixin globalStatus

  static:
    doAssert sizeof(dst[]) == sizeof(Blob)
    doAssert sizeof(array[FIELD_ELEMENTS_PER_BLOB, array[32, byte]]) == sizeof(Blob)

  let view = cast[ptr array[FIELD_ELEMENTS_PER_BLOB, array[32, byte]]](blob)

  tp.parallelFor i in 0 ..< FIELD_ELEMENTS_PER_BLOB:
    captures: {dst, view}
    reduceInto(globalStatus: CttCodecScalarStatus):
      prologue:
        var workerStatus = cttCodecScalar_Success
      forLoop:
        let iterStatus = dst.evals[i].bytes_to_bls_field(view[i])
        if workerStatus == cttCodecScalar_Success:
          # Propagate errors, if any it comes from current iteration
          workerStatus = iterStatus
      merge(remoteFutureStatus: Flowvar[CttCodecScalarStatus]):
        let remoteStatus = sync(remoteFutureStatus)
        if workerStatus == cttCodecScalar_Success:
          # Propagate errors, if any it comes from remote worker
          workerStatus = remoteStatus
      epilogue:
        return workerStatus

  return globalStatus

# Ethereum KZG public API
# ------------------------------------------------------------
#
# We use a simple goto state machine to handle errors and cleanup (if allocs were done)
# and have 2 different checks:
# - Either we are in "HappyPath" section that shortcuts to resource cleanup on error
# - or there are no resources to clean and we can early return from a function.

func kzgifyStatus(status: CttCodecScalarStatus or CttCodecEccStatus): CttEthKzgStatus {.inline.} =
  checkReturn status

proc blob_to_kzg_commitment_parallel*(
       tp: Threadpool,
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

  block HappyPath:
    check HappyPath, tp.blob_to_bigint_polynomial_parallel(poly, blob)

    var r {.noinit.}: ECP_ShortW_Aff[Fp[BLS12_381], G1]
    tp.kzg_commit_parallel(r, poly.evals, ctx.srs_lagrange_g1)
    discard dst.serialize_g1_compressed(r)

    result = cttEthKZG_Success

  freeHeapAligned(poly)
  return result

proc compute_kzg_proof_parallel*(
       tp: Threadpool,
       ctx: ptr EthereumKZGContext,
       proof_bytes: var array[48, byte],
       y_bytes: var array[32, byte],
       blob: ptr Blob,
       z_bytes: array[32, byte]): CttEthKzgStatus =
  ## Generate:
  ## - A proof of correct evaluation.
  ## - y = p(z), the evaluation of p at the challenge z, with p being the Blob interpreted as a polynomial.
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
  checkReturn z.bytes_to_bls_field(z_bytes)

  let poly = allocHeapAligned(PolynomialEval[FIELD_ELEMENTS_PER_BLOB, Fr[BLS12_381]], 64)

  block HappyPath:
    # Blob -> Polynomial
    check HappyPath, sync tp.blob_to_field_polynomial_parallel_async(poly, blob)

    # KZG Prove
    var y {.noInit.}: Fr[BLS12_381]                         # y = p(z), eval at challenge z
    var proof {.noInit.}: ECP_ShortW_Aff[Fp[BLS12_381], G1] # [proof]₁ = [(p(τ) - p(z)) / (τ-z)]₁

    tp.kzg_prove_parallel(
      proof, y,
      poly, ctx.domain.addr,
      z.addr, ctx.srs_lagrange_g1,
      isBitReversedDomain = true)

    discard proof_bytes.serialize_g1_compressed(proof) # cannot fail
    y_bytes.marshal(y, bigEndian) # cannot fail
    result = cttEthKZG_Success

  freeHeapAligned(poly)
  return result

proc compute_blob_kzg_proof_parallel*(
       tp: Threadpool,
       ctx: ptr EthereumKZGContext,
       proof_bytes: var array[48, byte],
       blob: ptr Blob,
       commitment_bytes: array[48, byte]): CttEthKzgStatus =
  ## Given a blob, return the KZG proof that is used to verify it against the commitment.
  ## This method does not verify that the commitment is correct with respect to `blob`.

  var commitment {.noInit.}: KZGCommitment
  checkReturn commitment.bytes_to_kzg_commitment(commitment_bytes)

  # Blob -> Polynomial
  let poly = allocHeapAligned(PolynomialEval[FIELD_ELEMENTS_PER_BLOB, Fr[BLS12_381]], 64)

  block HappyPath:
    # Blob -> Polynomial, spawn async on other threads
    let convStatus = tp.blob_to_field_polynomial_parallel_async(poly, blob)

    # Fiat-Shamir challenge
    var challenge {.noInit.}: Fr[BLS12_381]
    challenge.addr.fiatShamirChallenge(blob, commitment_bytes.unsafeAddr)

    # Await conversion to field polynomial
    check HappyPath, sync(convStatus)

    # KZG Prove
    var y {.noInit.}: Fr[BLS12_381]                         # y = p(z), eval at challenge z
    var proof {.noInit.}: ECP_ShortW_Aff[Fp[BLS12_381], G1] # [proof]₁ = [(p(τ) - p(z)) / (τ-z)]₁

    tp.kzg_prove_parallel(
      proof, y,
      poly, ctx.domain.addr,
      challenge.addr, ctx.srs_lagrange_g1,
      isBitReversedDomain = true)

    discard proof_bytes.serialize_g1_compressed(proof) # cannot fail

    result = cttEthKZG_Success

  freeHeapAligned(poly)
  return result

proc verify_blob_kzg_proof_parallel*(
       tp: Threadpool,
       ctx: ptr EthereumKZGContext,
       blob: ptr Blob,
       commitment_bytes: array[48, byte],
       proof_bytes: array[48, byte]): CttEthKzgStatus =
  ## Given a blob and a KZG proof, verify that the blob data corresponds to the provided commitment.

  var commitment {.noInit.}: KZGCommitment
  checkReturn commitment.bytes_to_kzg_commitment(commitment_bytes)

  var proof {.noInit.}: KZGProof
  checkReturn proof.bytes_to_kzg_proof(proof_bytes)

  let poly = allocHeapAligned(PolynomialEval[FIELD_ELEMENTS_PER_BLOB, Fr[BLS12_381]], 64)
  let invRootsMinusZ = allocHeapAligned(array[FIELD_ELEMENTS_PER_BLOB, Fr[BLS12_381]], alignment = 64)

  block HappyPath:
    # Blob -> Polynomial, spawn async on other threads
    let convStatus = tp.blob_to_field_polynomial_parallel_async(poly, blob)

    # Fiat-Shamir challenge
    var challengeFr {.noInit.}: Fr[BLS12_381]
    challengeFr.addr.fiatShamirChallenge(blob, commitment_bytes.unsafeAddr)

    var challenge, eval_at_challenge {.noInit.}: matchingOrderBigInt(BLS12_381)
    challenge.fromField(challengeFr)

    # Lagrange Polynomial evaluation
    # ------------------------------
    # 1. Compute 1/(ωⁱ - z) with ω a root of unity, i in [0, N).
    #    zIndex = i if ωⁱ - z == 0 (it is the i-th root of unity) and -1 otherwise.
    let zIndex = invRootsMinusZ[].inverseRootsMinusZ_vartime(
                                    ctx.domain, challengeFr,
                                    earlyReturnOnZero = true)

    # Await conversion to field polynomial
    check HappyPath, sync(convStatus)

    # 2. Actual evaluation
    if zIndex == -1:
      var eval_at_challenge_fr{.noInit.}: Fr[BLS12_381]
      tp.evalPolyAt_parallel(
        eval_at_challenge_fr,
        poly, challengeFr.addr,
        invRootsMinusZ,
        ctx.domain.addr)
      eval_at_challenge.fromField(eval_at_challenge_fr)
    else:
      eval_at_challenge.fromField(poly.evals[zIndex])

    # KZG verification
    let verif = kzg_verify(ECP_ShortW_Aff[Fp[BLS12_381], G1](commitment),
                          challenge, eval_at_challenge,
                          ECP_ShortW_Aff[Fp[BLS12_381], G1](proof),
                          ctx.srs_monomial_g2.coefs[1])
    if verif:
      result =  cttEthKZG_Success
    else:
      result = cttEthKZG_VerificationFailure

  freeHeapAligned(invRootsMinusZ)
  freeHeapAligned(poly)
  return result

proc verify_blob_kzg_proof_batch_parallel*(
       tp: Threadpool,
       ctx: ptr EthereumKZGContext,
       blobs: ptr UncheckedArray[Blob],
       commitments_bytes: ptr UncheckedArray[array[48, byte]],
       proof_bytes: ptr UncheckedArray[array[48, byte]],
       n: int,
       secureRandomBytes: array[32, byte]): CttEthKzgStatus =
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

  mixin globalStatus

  if n < 0:
    return cttEthKZG_VerificationFailure
  if n == 0:
    return cttEthKZG_Success

  let commitments = allocHeapArrayAligned(KZGCommitment, n, alignment = 64)
  let challenges = allocHeapArrayAligned(Fr[BLS12_381], n, alignment = 64)
  let evals_at_challenges = allocHeapArrayAligned(matchingOrderBigInt(BLS12_381), n, alignment = 64)
  let proofs = allocHeapArrayAligned(KZGProof, n, alignment = 64)

  let polys = allocHeapArrayAligned(PolynomialEval[FIELD_ELEMENTS_PER_BLOB, Fr[BLS12_381]], n, alignment = 64)
  let invRootsMinusZs = allocHeapArrayAligned(array[FIELD_ELEMENTS_PER_BLOB, Fr[BLS12_381]], n, alignment = 64)

  block HappyPath:
    tp.parallelFor i in 0 ..< n:
      captures: {tp, ctx,
                 commitments, commitments_bytes,
                 polys, blobs,
                 challenges, evals_at_challenges,
                 proofs, proof_bytes,
                 invRootsMinusZs}
      reduceInto(globalStatus: CttEthKzgStatus):
        prologue:
          var workerStatus = cttEthKZG_Success
        forLoop:
          let polyStatusFut = tp.blob_to_field_polynomial_parallel_async(polys[i].addr, blobs[i].addr)
          let challengeStatusFut = tp.spawnAwaitable challenges[i].addr.fiatShamirChallenge(blobs[i].addr, commitments_bytes[i].addr)

          let commitmentStatus = kzgifyStatus commitments[i].bytes_to_kzg_commitment(commitments_bytes[i])
          if workerStatus == cttEthKZG_Success:
            workerStatus = commitmentStatus
          let polyStatus = kzgifyStatus sync(polyStatusFut)
          if workerStatus == cttEthKZG_Success:
            workerStatus = polyStatus
          discard sync(challengeStatusFut)

          # Lagrange Polynomial evaluation
          # ------------------------------
          # 1. Compute 1/(ωⁱ - z) with ω a root of unity, i in [0, N).
          #    zIndex = i if ωⁱ - z == 0 (it is the i-th root of unity) and -1 otherwise.
          let zIndex = invRootsMinusZs[i].inverseRootsMinusZ_vartime(
                                          ctx.domain, challenges[i],
                                          earlyReturnOnZero = true)
          # 2. Actual evaluation
          if zIndex == -1:
            var eval_at_challenge_fr{.noInit.}: Fr[BLS12_381]
            tp.evalPolyAt_parallel(
              eval_at_challenge_fr,
              polys[i].addr, challenges[i].addr,
              invRootsMinusZs[i].addr,
              ctx.domain.addr)
            evals_at_challenges[i].fromField(eval_at_challenge_fr)
          else:
            evals_at_challenges[i].fromField(polys[i].evals[zIndex])

          let proofStatus = kzgifyStatus proofs[i].bytes_to_kzg_proof(proof_bytes[i])
          if workerStatus == cttEthKZG_Success:
            workerStatus = proofStatus

        merge(remoteStatusFut: Flowvar[CttEthKzgStatus]):
          let remoteStatus = sync(remoteStatusFut)
          if workerStatus == cttEthKZG_Success:
            workerStatus = remoteStatus
        epilogue:
          return workerStatus


    result = sync(globalStatus)
    if result != cttEthKZG_Success:
      break HappyPath

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
      transcript.update(cast[ptr UncheckedArray[byte]](challenges).toOpenArray(0, n*sizeof(Fr[BLS12_381])-1))

      var blindingBytes {.noInit.}: array[32, byte]
      transcript.finish(blindingBytes)
      randomBlindingFr.fromDigest(blindingBytes)

    # TODO: use parallel prefix product for parallel powers compute
    let linearIndepRandNumbers = allocHeapArrayAligned(Fr[BLS12_381], n, alignment = 64)
    linearIndepRandNumbers.computePowers(n, randomBlindingFr)

    type EcAffArray = ptr UncheckedArray[ECP_ShortW_Aff[Fp[BLS12_381], G1]]
    let verif = kzg_verify_batch(
                  cast[EcAffArray](commitments),
                  challenges,
                  evals_at_challenges,
                  cast[EcAffArray](proofs),
                  linearIndepRandNumbers,
                  n,
                  ctx.srs_monomial_g2.coefs[1])
    if verif:
      result =  cttEthKZG_Success
    else:
      result = cttEthKZG_VerificationFailure

    freeHeapAligned(linearIndepRandNumbers)

  freeHeapAligned(invRootsMinusZs)
  freeHeapAligned(polys)
  freeHeapAligned(proofs)
  freeHeapAligned(evals_at_challenges)
  freeHeapAligned(challenges)
  freeHeapAligned(commitments)

  return result
