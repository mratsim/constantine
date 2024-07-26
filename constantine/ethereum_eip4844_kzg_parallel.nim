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
  constantine/named/algebras,
  ./math/[ec_shortweierstrass, arithmetic, extension_fields],
  ./math/polynomials/polynomials_parallel,
  ./hashes,
  ./commitments/kzg_parallel,
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

const prefix_eth_kzg4844 = "ctt_eth_kzg_"
import ./zoo_exports

proc blob_to_bigint_polynomial_parallel(
       tp: Threadpool,
       dst: ptr PolynomialEval[FIELD_ELEMENTS_PER_BLOB, Fr[BLS12_381].getBigInt()],
       blob: Blob): CttCodecScalarStatus =
  ## Convert a blob to a polynomial in evaluation form
  mixin globalStatus

  static:
    doAssert sizeof(dst[]) == sizeof(Blob)
    doAssert sizeof(array[FIELD_ELEMENTS_PER_BLOB, array[32, byte]]) == sizeof(Blob)

  let view = cast[ptr array[FIELD_ELEMENTS_PER_BLOB, array[32, byte]]](blob.unsafeAddr)

  tp.parallelFor i in 0 ..< FIELD_ELEMENTS_PER_BLOB:
    captures: {dst, view}
    reduceInto(globalStatus: Flowvar[CttCodecScalarStatus]):
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
       blob: Blob): Flowvar[CttCodecScalarStatus] =
  ## Convert a blob to a polynomial in evaluation form
  ## The result is a `Flowvar` handle and MUST be awaited with `sync`
  mixin globalStatus

  static:
    doAssert sizeof(dst[]) == sizeof(Blob)
    doAssert sizeof(array[FIELD_ELEMENTS_PER_BLOB, array[32, byte]]) == sizeof(Blob)

  let view = cast[ptr array[FIELD_ELEMENTS_PER_BLOB, array[32, byte]]](blob.unsafeAddr)

  tp.parallelFor i in 0 ..< FIELD_ELEMENTS_PER_BLOB:
    captures: {dst, view}
    reduceInto(globalStatus: Flowvar[CttCodecScalarStatus]):
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

func kzgifyStatus(status: CttCodecScalarStatus or CttCodecEccStatus): cttEthKzgStatus {.inline.} =
  checkReturn status

proc blob_to_kzg_commitment_parallel*(
       tp: Threadpool,
       ctx: ptr EthereumKZGContext,
       dst: var array[48, byte],
       blob: Blob): cttEthKzgStatus {.libPrefix: prefix_eth_kzg4844.} =
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
  ##   - and at the opening challenge z.
  ##
  ##   with proof = [(p(τ) - p(z)) / (τ-z)]₁

  let poly = allocHeapAligned(PolynomialEval[FIELD_ELEMENTS_PER_BLOB, Fr[BLS12_381].getBigInt()], 64)

  block HappyPath:
    check HappyPath, tp.blob_to_bigint_polynomial_parallel(poly, blob)

    var r {.noinit.}: EC_ShortW_Aff[Fp[BLS12_381], G1]
    tp.kzg_commit_parallel(ctx.srs_lagrange_g1, r, poly[])
    discard dst.serialize_g1_compressed(r)

    result = cttEthKzg_Success

  freeHeapAligned(poly)
  return result

proc compute_kzg_proof_parallel*(
       tp: Threadpool,
       ctx: ptr EthereumKZGContext,
       proof_bytes: var array[48, byte],
       y_bytes: var array[32, byte],
       blob: Blob,
       z_bytes: array[32, byte]): cttEthKzgStatus {.libPrefix: prefix_eth_kzg4844.} =
  ## Generate:
  ## - A proof of correct evaluation.
  ## - y = p(z), the evaluation of p at the opening challenge z, with p being the Blob interpreted as a polynomial.
  ##
  ## Mathematical description
  ##   [proof]₁ = [(p(τ) - p(z)) / (τ-z)]₁, with p(τ) being the commitment, i.e. the evaluation of p at the powers of τ
  ##   The notation [a]₁ corresponds to the scalar multiplication of a by the generator of 𝔾1
  ##
  ##   Verification can be done by verifying the relation:
  ##     proof.(τ - z) = p(τ)-p(z)
  ##   which doesn't require the full blob but only evaluations of it
  ##   - at τ, p(τ) is the commitment
  ##   - and at the opening challenge z.

  # Random or Fiat-Shamir challenge
  var z {.noInit.}: Fr[BLS12_381]
  checkReturn z.bytes_to_bls_field(z_bytes)

  let poly = allocHeapAligned(PolynomialEval[FIELD_ELEMENTS_PER_BLOB, Fr[BLS12_381]], 64)

  block HappyPath:
    # Blob -> Polynomial
    check HappyPath, sync tp.blob_to_field_polynomial_parallel_async(poly, blob)

    # KZG Prove
    var y {.noInit.}: Fr[BLS12_381]                         # y = p(z), eval at challenge z
    var proof {.noInit.}: EC_ShortW_Aff[Fp[BLS12_381], G1] # [proof]₁ = [(p(τ) - p(z)) / (τ-z)]₁

    tp.kzg_prove_parallel(
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

proc compute_blob_kzg_proof_parallel*(
       tp: Threadpool,
       ctx: ptr EthereumKZGContext,
       proof_bytes: var array[48, byte],
       blob: Blob,
       commitment_bytes: array[48, byte]): cttEthKzgStatus {.libPrefix: prefix_eth_kzg4844.} =
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
    var opening_challenge {.noInit.}: Fr[BLS12_381]
    opening_challenge.addr.fiatShamirChallenge(blob, commitment_bytes)

    # Await conversion to field polynomial
    check HappyPath, sync(convStatus)

    # KZG Prove
    var y {.noInit.}: Fr[BLS12_381]                         # y = p(z), eval at opening challenge z
    var proof {.noInit.}: EC_ShortW_Aff[Fp[BLS12_381], G1] # [proof]₁ = [(p(τ) - p(z)) / (τ-z)]₁

    tp.kzg_prove_parallel(
      ctx.srs_lagrange_g1,
      ctx.domain,
      y, proof,
      poly[],
      opening_challenge)

    proof_bytes.serialize_g1_compressed(proof)

    result = cttEthKzg_Success

  freeHeapAligned(poly)
  return result

proc verify_blob_kzg_proof_parallel*(
       tp: Threadpool,
       ctx: ptr EthereumKZGContext,
       blob: Blob,
       commitment_bytes: array[48, byte],
       proof_bytes: array[48, byte]): cttEthKzgStatus {.libPrefix: prefix_eth_kzg4844.} =
  ## Given a blob and a KZG proof, verify that the blob data corresponds to the provided commitment.

  var commitment {.noInit.}: KZGCommitment
  checkReturn commitment.bytes_to_kzg_commitment(commitment_bytes)

  var proof {.noInit.}: KZGProof
  checkReturn proof.bytes_to_kzg_proof(proof_bytes)

  let poly = allocHeapAligned(PolynomialEval[FIELD_ELEMENTS_PER_BLOB, Fr[BLS12_381]], 64)

  block HappyPath:
    # Blob -> Polynomial, spawn async on other threads
    let convStatus = tp.blob_to_field_polynomial_parallel_async(poly, blob)

    # Fiat-Shamir challenge
    var opening_challenge {.noInit.}: Fr[BLS12_381]
    var eval_at_challenge {.noInit.}: Fr[BLS12_381]
    opening_challenge.addr.fiatShamirChallenge(blob, commitment_bytes)

    # Await conversion to field polynomial
    check HappyPath, sync(convStatus)

    # Technically we could interleavethe blob_to_field_polynomial_parallel_async
    # and the first part of evalPolyAt_parallel: inverseDifferenceArray
    # but performance cost should be minimal compared to readability.
    tp.evalPolyAt_parallel(ctx.domain, eval_at_challenge, poly[], opening_challenge)

    # KZG verification
    let verif = kzg_verify(EC_ShortW_Aff[Fp[BLS12_381], G1](commitment),
                          opening_challenge.toBig(), eval_at_challenge.toBig(),
                          EC_ShortW_Aff[Fp[BLS12_381], G1](proof),
                          ctx.srs_monomial_g2.coefs[1])
    if verif:
      result =  cttEthKzg_Success
    else:
      result = cttEthKzg_VerificationFailure

  freeHeapAligned(poly)
  return result

proc verify_blob_kzg_proof_batch_parallel*(
       tp: Threadpool,
       ctx: ptr EthereumKZGContext,
       blobs: ptr UncheckedArray[Blob],
       commitments_bytes: ptr UncheckedArray[array[48, byte]],
       proof_bytes: ptr UncheckedArray[array[48, byte]],
       n: int,
       secureRandomBytes: array[32, byte]): cttEthKzgStatus {.libPrefix: prefix_eth_kzg4844.} =
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
    return cttEthKzg_VerificationFailure
  if n == 0:
    return cttEthKzg_Success

  let commitments = allocHeapArrayAligned(KZGCommitment, n, alignment = 64)
  let opening_challenges = allocHeapArrayAligned(Fr[BLS12_381], n, alignment = 64)
  let evals_at_challenges = allocHeapArrayAligned(Fr[BLS12_381].getBigInt(), n, alignment = 64)
  let proofs = allocHeapArrayAligned(KZGProof, n, alignment = 64)
  let polys = allocHeapArrayAligned(PolynomialEval[FIELD_ELEMENTS_PER_BLOB, Fr[BLS12_381]], n, alignment = 64)

  block HappyPath:
    tp.parallelFor i in 0 ..< n:
      captures: {tp, ctx,
                 commitments, commitments_bytes,
                 polys, blobs,
                 opening_challenges, evals_at_challenges,
                 proofs, proof_bytes}
      reduceInto(globalStatus: Flowvar[cttEthKzgStatus]):
        prologue:
          var workerStatus = cttEthKzg_Success
        forLoop:
          let polyStatusFut = tp.blob_to_field_polynomial_parallel_async(polys[i].addr, blobs[i])
          let challengeStatusFut = tp.spawnAwaitable opening_challenges[i].addr.fiatShamirChallenge(blobs[i], commitments_bytes[i])

          let commitmentStatus = kzgifyStatus commitments[i].bytes_to_kzg_commitment(commitments_bytes[i])
          if workerStatus == cttEthKzg_Success:
            workerStatus = commitmentStatus
          let polyStatus = kzgifyStatus sync(polyStatusFut)
          if workerStatus == cttEthKzg_Success:
            workerStatus = polyStatus
          discard sync(challengeStatusFut)

          var eval_at_challenge_fr{.noInit.}: Fr[BLS12_381]
          tp.evalPolyAt_parallel(
            ctx.domain,
            eval_at_challenge_fr,
            polys[i], opening_challenges[i]
          )
          evals_at_challenges[i].fromField(eval_at_challenge_fr)

          let proofStatus = kzgifyStatus proofs[i].bytes_to_kzg_proof(proof_bytes[i])
          if workerStatus == cttEthKzg_Success:
            workerStatus = proofStatus

        merge(remoteStatusFut: Flowvar[cttEthKzgStatus]):
          let remoteStatus = sync(remoteStatusFut)
          if workerStatus == cttEthKzg_Success:
            workerStatus = remoteStatus
        epilogue:
          return workerStatus


    result = sync(globalStatus)
    if result != cttEthKzg_Success:
      break HappyPath

    var randomBlindingFr {.noInit.}: Fr[BLS12_381]
    block blinding: # Ensure we don't multiply by 0 for blinding
      # 1. Try with the random number supplied
      for i in 0 ..< secureRandomBytes.len:
        if secureRandomBytes[i] != byte 0:
          randomBlindingFr.fromDigest(secureRandomBytes)
          break blinding
      # 2. If it's 0 (how?!), we just hash all the Fiat-Shamir opening_challenges
      var transcript: sha256
      transcript.init()
      transcript.update(RANDOM_CHALLENGE_KZG_BATCH_DOMAIN)
      transcript.update(cast[ptr UncheckedArray[byte]](opening_challenges).toOpenArray(0, n*sizeof(Fr[BLS12_381])-1))

      var blindingBytes {.noInit.}: array[32, byte]
      transcript.finish(blindingBytes)
      randomBlindingFr.fromDigest(blindingBytes)

    # TODO: use parallel prefix product for parallel powers compute
    let linearIndepRandNumbers = allocHeapArrayAligned(Fr[BLS12_381], n, alignment = 64)
    linearIndepRandNumbers.computePowers(randomBlindingFr, n)

    type EcAffArray = ptr UncheckedArray[EC_ShortW_Aff[Fp[BLS12_381], G1]]
    let verif = tp.kzg_verify_batch_parallel(
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

  freeHeapAligned(polys)
  freeHeapAligned(proofs)
  freeHeapAligned(evals_at_challenges)
  freeHeapAligned(opening_challenges)
  freeHeapAligned(commitments)

  return result
