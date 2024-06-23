/** Constantine
 *  Copyright (c) 2018-2019    Status Research & Development GmbH
 *  Copyright (c) 2020-Present Mamy André-Ratsimbazafy
 *  Licensed and distributed under either of
 *    * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
 *    * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
 *  at your option. This file may not be copied, modified, or distributed except according to those terms.
 */
#ifndef __CTT_H_ETHEREUM_EIP4844_KZG_PARALLEL__
#define __CTT_H_ETHEREUM_EIP4844_KZG_PARALLEL__

#include "constantine/core/datatypes.h"
#include "constantine/core/threadpool.h"
#include "constantine/protocols/ethereum_eip4844_kzg.h"

#ifdef __cplusplus
extern "C" {
#endif

// Ethereum EIP-4844 KZG Interface
// ------------------------------------------------------------------------------------------------

/** Compute a commitment to the `blob`.
 *  The commitment can be verified without needing the full `blob`
 *
 *  Mathematical description
 *    commitment = [p(τ)]₁
 *
 *    The blob data is used as a polynomial,
 *    the polynomial is evaluated at powers of tau τ, a trusted setup.
 *
 *    Verification can be done by verifying the relation:
 *      proof.(τ - z) = p(τ)-p(z)
 *    which doesn't require the full blob but only evaluations of it
 *    - at τ, p(τ) is the commitment
 *    - and at the verification opening_challenge z.
 *
 *    with proof = [(p(τ) - p(z)) / (τ-z)]₁
 */
ctt_eth_kzg_status ctt_eth_kzg_blob_to_kzg_commitment_parallel(
        const ctt_threadpool* tp,
        const ctt_eth_kzg_context* ctx,
        ctt_eth_kzg_commitment* dst,
        const ctt_eth_kzg_blob* blob
) __attribute__((warn_unused_result));

/** Generate:
 *  - A proof of correct evaluation.
 *  - y = p(z), the evaluation of p at the opening_challenge z, with p being the Blob interpreted as a polynomial.
 *
 *  Mathematical description
 *    [proof]₁ = [(p(τ) - p(z)) / (τ-z)]₁, with p(τ) being the commitment, i.e. the evaluation of p at the powers of τ
 *    The notation [a]₁ corresponds to the scalar multiplication of a by the generator of 𝔾1
 *
 *    Verification can be done by verifying the relation:
 *      proof.(τ - z) = p(τ)-p(z)
 *    which doesn't require the full blob but only evaluations of it
 *    - at τ, p(τ) is the commitment
 *    - and at the verification opening_challenge z.
 */
ctt_eth_kzg_status ctt_eth_kzg_compute_kzg_proof_parallel(
        const ctt_threadpool* tp,
        const ctt_eth_kzg_context* ctx,
        ctt_eth_kzg_proof* proof,
        ctt_eth_kzg_eval_at_challenge* y,
        const ctt_eth_kzg_blob* blob,
        const ctt_eth_kzg_opening_challenge* z
) __attribute__((warn_unused_result));

/** Given a blob, return the KZG proof that is used to verify it against the commitment.
 *  This method does not verify that the commitment is correct with respect to `blob`.
 */
ctt_eth_kzg_status ctt_eth_kzg_compute_blob_kzg_proof_parallel(
        const ctt_threadpool* tp,
        const ctt_eth_kzg_context* ctx,
        ctt_eth_kzg_proof* proof,
        const ctt_eth_kzg_blob* blob,
        const ctt_eth_kzg_commitment* commitment
) __attribute__((__warn_unused_result__));

/** Given a blob and a KZG proof, verify that the blob data corresponds to the provided commitment.
 */
ctt_eth_kzg_status ctt_eth_kzg_verify_blob_kzg_proof_parallel(
        const ctt_threadpool* tp,
        const ctt_eth_kzg_context* ctx,
        const ctt_eth_kzg_blob* blob,
        const ctt_eth_kzg_commitment* commitment,
        const ctt_eth_kzg_proof* proof
) __attribute__((__warn_unused_result__));

/** Verify `n` (blob, commitment, proof) sets efficiently
 *
 *  `n` is the number of verifications set
 *  - if n is negative, this procedure returns verification failure
 *  - if n is zero, this procedure returns verification success
 *
 *  `secure_random_bytes` random bytes must come from a cryptographically secure RNG
 *  or computed through the Fiat-Shamir heuristic.
 *  It serves as a random number
 *  that is not in the control of a potential attacker to prevent potential
 *  rogue commitments attacks due to homomorphic properties of pairings,
 *  i.e. commitments that are linear combination of others and sum would be zero.
 */
ctt_eth_kzg_status ctt_eth_kzg_verify_blob_kzg_proof_batch_parallel(
        const ctt_threadpool* tp,
        const ctt_eth_kzg_context* ctx,
        const ctt_eth_kzg_blob blobs[],
        const ctt_eth_kzg_commitment commitments[],
        const ctt_eth_kzg_proof proofs[],
        size_t n,
        const byte secure_random_bytes[32]
) __attribute__((__warn_unused_result__));

#ifdef __cplusplus
}
#endif

#endif // __CTT_H_ETHEREUM_EIP4844_KZG_PARALLEL__
