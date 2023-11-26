
/** Constantine
 *  Copyright (c) 2018-2019    Status Research & Development GmbH
 *  Copyright (c) 2020-Present Mamy André-Ratsimbazafy
 *  Licensed and distributed under either of
 *    * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
 *    * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
 *  at your option. This file may not be copied, modified, or distributed except according to those terms.
 */
#ifndef __CTT_H_ETHEREUM_KZG_4844__
#define __CTT_H_ETHEREUM_KZG_4844__

#include "constantine/core/datatypes.h"

#ifdef __cplusplus
extern "C" {
#endif

// Ethereum EIP-4844 KZG types
// ------------------------------------------------------------------------------------------------

#define BYTES_PER_COMMITMENT 48
#define BYTES_PER_PROOF 48
#define BYTES_PER_FIELD_ELEMENT 32
#define FIELD_ELEMENTS_PER_BLOB 4096
#define BYTES_PER_BLOB (FIELD_ELEMENTS_PER_BLOB * BYTES_PER_FIELD_ELEMENT)

typedef struct ctt_eth_kzg4844_commitment        { byte raw[BYTES_PER_COMMITMENT]; }    ctt_eth_kzg4844_commitment;
typedef struct ctt_eth_kzg4844_proof             { byte raw[BYTES_PER_PROOF]; }         ctt_eth_kzg4844_proof;
typedef struct ctt_eth_kzg4844_blob              { byte raw[BYTES_PER_BLOB]; }          ctt_eth_kzg4844_blob;
typedef struct ctt_eth_kzg4844_challenge         { byte raw[BYTES_PER_FIELD_ELEMENT]; } ctt_eth_kzg4844_challenge;
typedef struct ctt_eth_kzg4844_eval_at_challenge { byte raw[BYTES_PER_FIELD_ELEMENT]; } ctt_eth_kzg4844_eval_at_challenge;

typedef enum __attribute__((__packed__)) {
    cttEthKzg_Success,
    cttEthKzg_VerificationFailure,
    cttEthKzg_ScalarZero,
    cttEthKzg_ScalarLargerThanCurveOrder,
    cttEthKzg_EccInvalidEncoding,
    cttEthKzg_EccCoordinateGreaterThanOrEqualModulus,
    cttEthKzg_EccPointNotOnCurve,
    cttEthKzg_EccPointNotInSubgroup,
} ctt_eth_kzg4844_status;

static const char* ctt_eth_kzg4844_status_to_string(ctt_eth_kzg4844_status status) {
  static const char* const statuses[] = {
    "cttEthKzg_Success",
    "cttEthKzg_VerificationFailure",
    "cttEthKzg_ScalarZero",
    "cttEthKzg_ScalarLargerThanCurveOrder",
    "cttEthKzg_EccInvalidEncoding",
    "cttEthKzg_EccCoordinateGreaterThanOrEqualModulus",
    "cttEthKzg_EccPointNotOnCurve",
    "cttEthKzg_EccPointNotInSubgroup",
  };
  size_t length = sizeof statuses / sizeof *statuses;
  if (0 <= status && status < length) {
    return statuses[status];
  }
  return "cttEthKzg_InvalidStatusCode";
}

typedef struct ctt_eth_kzg4844_context_struct ctt_eth_kzg4844_context;


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
 *    - and at the verification challenge z.
 */
ctt_eth_kzg4844_status ctt_eth_kzg4844_blob_to_kzg_commitment(
        const ctt_eth_kzg4844_context* ctx,
        ctt_eth_kzg4844_commitment* dst,
        const ctt_eth_kzg4844_blob* blob
);

/** Generate:
 *  - A proof of correct evaluation.
 *  - y = p(z), the evaluation of p at the challenge z, with p being the Blob interpreted as a polynomial.
 *
 *  Mathematical description
 *    [proof]₁ = [(p(τ) - p(z)) / (τ-z)]₁, with p(τ) being the commitment, i.e. the evaluation of p at the powers of τ
 *    The notation [a]₁ corresponds to the scalar multiplication of a by the generator of 𝔾1
 *
 *    Verification can be done by verifying the relation:
 *      proof.(τ - z) = p(τ)-p(z)
 *    which doesn't require the full blob but only evaluations of it
 *    - at τ, p(τ) is the commitment
 */
ctt_eth_kzg4844_status ctt_eth_kzg4844_compute_kzg_proof(
        const ctt_eth_kzg4844_context* ctx,
        ctt_eth_kzg4844_proof* proof,
        ctt_eth_kzg4844_eval_at_challenge* y,
        const ctt_eth_kzg4844_blob* blob,
        const ctt_eth_kzg4844_challenge* z
);

/** Verify KZG proof
 *  that p(z) == y where
 *    - z is a random challenge
 *    - y is the evaluation of the "KZG polynomial" p at z
 *    - commitment is p(τ), the evaluation of p at the trusted setup τ,
 *    - [proof]₁ = [(p(τ) - p(z)) / (τ-z)]₁, ensure that p(z) evaluation was correct
 *      without needing access to the polynomial p itself.
 */
ctt_eth_kzg4844_status ctt_eth_kzg4844_verify_kzg_proof(
        const ctt_eth_kzg4844_context* ctx,
        const ctt_eth_kzg4844_commitment* commitment,
        const ctt_eth_kzg4844_challenge* z,
        const ctt_eth_kzg4844_eval_at_challenge* y,
        const ctt_eth_kzg4844_proof* proof
);

/** Given a blob, return the KZG proof that is used to verify it against the commitment.
 *  This method does not verify that the commitment is correct with respect to `blob`.
 */
ctt_eth_kzg4844_status ctt_eth_kzg4844_compute_blob_kzg_proof(
        const ctt_eth_kzg4844_context* ctx,
        ctt_eth_kzg4844_proof* proof,
        const ctt_eth_kzg4844_blob* blob,
        const ctt_eth_kzg4844_commitment* commitment
);

/** Given a blob and a KZG proof, verify that the blob data corresponds to the provided commitment.
 */
ctt_eth_kzg4844_status ctt_eth_kzg4844_verify_blob_kzg_proof(
        const ctt_eth_kzg4844_context* ctx,
        const ctt_eth_kzg4844_blob* blob,
        const ctt_eth_kzg4844_commitment* commitment,
        const ctt_eth_kzg4844_proof* proof
);

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
ctt_eth_kzg4844_status ctt_eth_kzg4844_verify_blob_kzg_proof_batch(
        const ctt_eth_kzg4844_context* ctx,
        const ctt_eth_kzg4844_blob blobs[],
        const ctt_eth_kzg4844_commitment commitments[],
        const ctt_eth_kzg4844_proof proofs[],
        size_t n,
        byte secure_random_bytes[32]
);



#ifdef __cplusplus
}
#endif

#endif
