/** Constantine
 *  Copyright (c) 2018-2019    Status Research & Development GmbH
 *  Copyright (c) 2020-Present Mamy André-Ratsimbazafy
 *  Licensed and distributed under either of
 *    * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
 *    * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
 *  at your option. This file may not be copied, modified, or distributed except according to those terms.
 */
#ifndef __CTT_H_ETHEREUM_EIP4844_KZG__
#define __CTT_H_ETHEREUM_EIP4844_KZG__

#include "constantine/core/datatypes.h"
#include "constantine/core/serialization.h"

#ifdef __cplusplus
extern "C" {
#endif

// EIP4844 KZG sizes
// ------------------------------------------------------------------------------------------------

/** The number of bytes in a KZG commitment. */
#define BYTES_PER_COMMITMENT 48

/** The number of bytes in a KZG proof. */
#define BYTES_PER_PROOF 48

/** The number of bytes in a BLS scalar field element. */
#define BYTES_PER_FIELD_ELEMENT 32

/** The number of field elements in a blob. */
#define FIELD_ELEMENTS_PER_BLOB 4096

/** The number of bytes in a blob. */
#define BYTES_PER_BLOB (FIELD_ELEMENTS_PER_BLOB * BYTES_PER_FIELD_ELEMENT)

// EIP4844 KZG commitment types
// ------------------------------------------------------------------------------------------------

typedef struct ctt_eth_kzg_context ctt_eth_kzg_context;

struct ctt_eth_kzg_fp { byte raw[48]; };

typedef struct { struct ctt_eth_kzg_fp  x, y; } ctt_eth_kzg_commitment;
typedef struct { struct ctt_eth_kzg_fp  x, y; } ctt_eth_kzg_proof;

typedef enum __attribute__((__packed__)) {
    cttEthKzg_Success,
    cttEthKzg_VerificationFailure,
    cttEthKzg_ScalarZero,
    cttEthKzg_ScalarLargerThanCurveOrder,
    cttEthKzg_EccInvalidEncoding,
    cttEthKzg_EccCoordinateGreaterThanOrEqualModulus,
    cttEthKzg_EccPointNotOnCurve,
    cttEthKzg_EccPointNotInSubGroup,
} ctt_eth_kzg_status;

static const char* ctt_eth_kzg_status_to_string(ctt_eth_kzg_status status) {
  static const char* const statuses[] = {
    "cttEthKzg_Success",
    "cttEthKzg_VerificationFailure",
    "cttEthKzg_ScalarZero",
    "cttEthKzg_ScalarLargerThanCurveOrder",
    "cttEthKzg_EccInvalidEncoding",
    "cttEthKzg_EccCoordinateGreaterThanOrEqualModulus",
    "cttEthKzg_EccPointNotOnCurve",
    "cttEthKzg_EccPointNotInSubGroup",
  };
  size_t length = sizeof statuses / sizeof *statuses;
  if (0 <= status && status < length) {
    return statuses[status];
  }
  return "cttEthKzg_InvalidStatusCode";
}

typedef enum __attribute__((__packed__)) {
    cttEthTS_Success,
    cttEthTS_MissingOrInaccessibleFile,
    cttEthTS_InvalidFile
} ctt_eth_trusted_setup_status;

static const char* ctt_eth_trusted_setup_status_to_string(ctt_eth_trusted_setup_status status) {
  static const char* const statuses[] = {
    "cttEthTS_Success",
    "cttEthTS_MissingOrInaccessibleFile",
    "cttEthTS_InvalidFile",
  };
  size_t length = sizeof statuses / sizeof *statuses;
  if (0 <= status && status < length) {
    return statuses[status];
  }
  return "cttEthTS_InvalidFileStatusCode";
}

typedef enum __attribute__((__packed__)) {
    cttEthTSFormat_ckzg4844,
} ctt_eth_trusted_setup_format;

// EIP4844 KZG API
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
 *
 *    with proof = [(p(τ) - p(z)) / (τ-z)]₁
 */
ctt_eth_kzg_status ctt_eth_kzg_blob_to_kzg_commitment(
    const ctt_eth_kzg_context* ctx,
    byte dst[BYTES_PER_COMMITMENT],
    byte blob[BYTES_PER_BLOB]
) __attribute__((warn_unused_result));

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
 *    - and at the verification challenge z.
 */
ctt_eth_kzg_status ctt_eth_kzg_compute_kzg_proof(
    const ctt_eth_kzg_context* ctx,
    byte proof[BYTES_PER_PROOF],
    byte y[BYTES_PER_FIELD_ELEMENT],
    byte blob[BYTES_PER_BLOB],
    byte z[BYTES_PER_FIELD_ELEMENT]
) __attribute__((warn_unused_result));

/** Verify a short KZG proof that p(z) == y
 *  where p is the blob polynomial used for the commitment.
 */
ctt_eth_kzg_status ctt_eth_kzg_verify_kzg_proof(
    const ctt_eth_kzg_context* ctx,
    byte commitment[BYTES_PER_COMMITMENT],
    byte z[BYTES_PER_FIELD_ELEMENT],
    byte y[BYTES_PER_FIELD_ELEMENT],
    byte proof[BYTES_PER_PROOF]
) __attribute__((__warn_unused_result__));

/** Given a blob, return the KZG proof that is used to verify it against the commitment.
 *  This method does not verify that the commitment is correct with respect to `blob`.
 */
ctt_eth_kzg_status ctt_eth_kzg_compute_blob_kzg_proof(
    const ctt_eth_kzg_context* ctx,
    byte proof[BYTES_PER_PROOF],
    byte blob[BYTES_PER_BLOB],
    byte commitment[BYTES_PER_COMMITMENT]
) __attribute__((__warn_unused_result__));

/** Given a blob and a KZG proof, verify that the blob data corresponds to the provided commitment.
 */
ctt_eth_kzg_status ctt_eth_kzg_verify_blob_kzg_proof(
    const ctt_eth_kzg_context* ctx,
    byte blob[BYTES_PER_BLOB],
    byte commitment[BYTES_PER_COMMITMENT],
    byte proof[BYTES_PER_PROOF]
) __attribute__((__warn_unused_result__));

/** Verify `n` (blob, commitment, proof) sets efficiently
 *
 * `n` is the number of verifications set
 * - if n is negative, this procedure returns verification failure
 * - if n is zero, this procedure returns verification success
 *
 * `secure_random_bytes` random byte must come from a cryptographically secure RNG
 * or computed through the Fiat-Shamir heuristic.
 * It serves as a random number
 * that is not in the control of a potential attacker to prevent potential
 * rogue commitments attacks due to homomorphic properties of pairings,
 * i.e. commitments that are linear combination of others and sum would be zero.
 */
ctt_eth_kzg_status ctt_eth_kzg_verify_blob_kzg_proof_batch(
    const ctt_eth_kzg_context* ctx,
    byte blob[][BYTES_PER_BLOB],
    byte commitments[][BYTES_PER_COMMITMENT],
    byte proofs[][BYTES_PER_PROOF],
    size_t n,
    byte secure_random_bytes[32]
) __attribute__((__warn_unused_result__));

// EIP4844 KZG Trusted setup
// ------------------------------------------------------------------------------------------------

/** Load trusted setup from path
 *  Currently the only format supported `cttEthTSFormat_ckzg4844`
 *  is from the reference implementation c-kzg-4844 text file
 */
ctt_eth_trusted_setup_status ctt_eth_trusted_setup_load(
    ctt_eth_kzg_context** ctx,
    const char* filepath,
    ctt_eth_trusted_setup_format format
) __attribute__((__warn_unused_result__));

/** Destroy a trusted setup
 */
void ctt_eth_trusted_setup_delete(ctt_eth_kzg_context* ctx);

#ifdef __cplusplus
}
#endif

#endif // __CTT_H_ETHEREUM_EIP4844_KZG__