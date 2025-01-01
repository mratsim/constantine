/** Constantine
 *  Copyright (c) 2018-2019    Status Research & Development GmbH
 *  Copyright (c) 2020-Present Mamy André-Ratsimbazafy
 *  Licensed and distributed under either of
 *    * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
 *    * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
 *  at your option. This file may not be copied, modified, or distributed except according to those terms.
 */
#ifndef __CTT_H_ETHEREUM_VERKLE_IPA__
#define __CTT_H_ETHEREUM_VERKLE_IPA__

#include "constantine/core/datatypes.h"
#include "constantine/curves/banderwagon.h"
#ifdef __cplusplus
extern "C"
{
#endif

  typedef enum __attribute__((__packed__))
  {
    cttEthVerkleIpa_Success,
    cttEthVerkleIpa_VerificationFailure,
    cttEthVerkleIpa_InputsLengthsMismatch,
    cttEthVerkleIpa_ScalarZero,
    cttEthVerkleIpa_ScalarLargerThanCurveOrder,
    cttEthVerkleIpa_EccInvalidEncoding,
    cttEthVerkleIpa_EccCoordinateGreaterThanOrEqualModulus,
    cttEthVerkleIpa_EccPointNotOnCurve,
    cttEthVerkleIpa_EccPointNotInSubGroup,
  } ctt_eth_verkle_ipa_status;

  static const char *ctt_eth_verkle_ipa_status_to_string(ctt_eth_verkle_ipa_status status)
  {
    static const char *const statuses[] = {
        "cttEthVerkleIpa_Success",
        "cttEthVerkleIpa_VerificationFailure",
        "cttEthVerkleIpa_InputsLengthsMismatch",
        "cttEthVerkleIpa_ScalarZero",
        "cttEthVerkleIpa_ScalarLargerThanCurveOrder",
        "cttEthVerkleIpa_EccInvalidEncoding",
        "cttEthVerkleIpa_EccCoordinateGreaterThanOrEqualModulus",
        "cttEthVerkleIpa_EccPointNotOnCurve",
        "cttEthVerkleIpa_EccPointNotInSubGroup",
    };
    size_t length = sizeof statuses / sizeof *statuses;
    if (0 <= status && status < length)
    {
      return statuses[status];
    }
    return "cttEthVerkleIpa_InvalidStatusCode";
  }

  typedef struct
  {
    byte raw[544];
  } ctt_eth_verkle_ipa_proof_bytes;
  typedef struct
  {
    byte raw[576];
  } ctt_eth_verkle_ipa_multi_proof_bytes;
  typedef struct
  {
    banderwagon_ec_aff l[8];
    banderwagon_ec_aff r[8];
    banderwagon_fr a0;
  } ctt_eth_verkle_ipa_proof_aff;
  typedef struct
  {
    banderwagon_ec_prj l[8];
    banderwagon_ec_prj r[8];
    banderwagon_fr a0;
  } ctt_eth_verkle_ipa_proof_prj;
  typedef struct
  {
    ctt_eth_verkle_ipa_proof_aff g2_proof;
    banderwagon_ec_aff d;
  } ctt_eth_verkle_ipa_multi_proof_aff;
  typedef struct
  {
    ctt_eth_verkle_ipa_proof_prj g2_proof;
    banderwagon_ec_prj d;
  } ctt_eth_verkle_ipa_multi_proof_prj;
  typedef struct
  {
    banderwagon_ec_aff evals[256];
  } ctt_eth_verkle_ipa_polynomial_eval_crs;
  typedef struct
  {
    banderwagon_fr evals[256];
  } ctt_eth_verkle_ipa_polynomial_eval_poly;
  typedef struct
  {
    banderwagon_fr domain[256];
    ctt_eth_verkle_ipa_polynomial_eval_poly *vanishing_deriv_poly_eval;
    ctt_eth_verkle_ipa_polynomial_eval_poly *vanishing_deriv_poly_eval_inv;
  } ctt_eth_verkle_ipa_poly_eval_domain;
  typedef struct
  {
    ctt_eth_verkle_ipa_poly_eval_domain *domain;
    banderwagon_fr domain_inverses[256];
  } ctt_eth_verkle_ipa_poly_eval_linear_domain;
  typedef struct 
  {
    size_t digest_size;
    size_t internal_block_size;

    void (*init)(void* ctx);
    void (*update)(void* ctx, const byte data[], size_t length);
    void (*finish)(void* ctx, byte data[], size_t digest_size);
    void (*clear)(void* ctx);
  } ctt_eth_verkle_ipa_transcript;

  // ctt_eth_verkle_ipa_status ctt_eth_verkle_ipa_serialize(ctt_eth_verkle_ipa_proof_bytes *dst, const ctt_eth_verkle_ipa_proof_aff *src) __attribute__((warn_unused_result));
  // ctt_eth_verkle_ipa_status ctt_eth_verkle_ipa_serialize_prj(ctt_eth_verkle_ipa_proof_bytes *dst, const ctt_eth_verkle_ipa_proof_prj *src) __attribute__((warn_unused_result));
  ctt_eth_verkle_ipa_status ctt_eth_verkle_ipa_deserialize_aff(ctt_eth_verkle_ipa_proof_aff *src, const ctt_eth_verkle_ipa_proof_bytes *dst) __attribute__((warn_unused_result));
  // ctt_eth_verkle_ipa_status ctt_eth_verkle_ipa_deserialize_prj(ctt_eth_verkle_ipa_proof_prj *src, const ctt_eth_verkle_ipa_proof_bytes *dst) __attribute__((warn_unused_result));
  // void ctt_eth_verkle_ipa_map_to_base_field_aff(banderwagon_fp *dst, const banderwagon_ec_aff *p) __attribute__((warn_unused_result));
  // void ctt_eth_verkle_ipa_map_to_base_field_prj(banderwagon_fp *dst, const banderwagon_ec_prj *p) __attribute__((warn_unused_result));
  // ctt_bool ctt_eth_verkle_ipa_map_to_scalar_field_aff(banderwagon_fr *res, const banderwagon_ec_aff *p) __attribute__((warn_unused_result));
  // ctt_bool ctt_eth_verkle_ipa_map_to_scalar_field_prj(banderwagon_fr *res, const banderwagon_ec_prj *p) __attribute__((warn_unused_result));
  // ctt_bool ctt_eth_verkle_ipa_batch_map_to_scalar_field_aff(banderwagon_fr res[], const banderwagon_ec_aff points[], size_t len) __attribute__((warn_unused_result));
  // ctt_bool ctt_eth_verkle_ipa_batch_map_to_scalar_field_prj(banderwagon_fr res[], const banderwagon_ec_prj points[], size_t len) __attribute__((warn_unused_result));
  // void ctt_eth_verkle_ipa_commit(const ctt_eth_verkle_ipa_polynomial_eval_crs *crs, banderwagon_ec_aff res, const ctt_eth_verkle_ipa_polynomial_eval_poly *poly) __attribute__((warn_unused_result));
  // void ctt_eth_verkle_ipa_commit_prj(const ctt_eth_verkle_ipa_polynomial_eval_crs *crs, banderwagon_ec_prj res, const ctt_eth_verkle_ipa_polynomial_eval_poly *poly) __attribute__((warn_unused_result));
  // void ctt_eth_verkle_ipa_prove(const ctt_eth_verkle_ipa_polynomial_eval_crs *crs, const ctt_eth_verkle_ipa_poly_eval_linear_domain *domain, ctt_eth_verkle_ipa_transcript *transcript, banderwagon_fr *eval_at_challenge, ctt_eth_verkle_ipa_proof_aff *proof, const ctt_eth_verkle_ipa_polynomial_eval_poly *poly, const banderwagon_ec_aff *commitment, const banderwagon_fr *opening_challenge) __attribute__((warn_unused_result));
  // void ctt_eth_verkle_ipa_verify(const ctt_eth_verkle_ipa_polynomial_eval_crs *crs, const ctt_eth_verkle_ipa_poly_eval_linear_domain *domain, ctt_eth_verkle_ipa_transcript *transcript, const banderwagon_ec_aff *commitment, const banderwagon_fr *opening_challenge, banderwagon_fr *eval_at_challenge, const ctt_eth_verkle_ipa_proof_aff *proof) __attribute__((warn_unused_result));
  // void ctt_eth_verkle_ipa_multi_prove(const ctt_eth_verkle_ipa_polynomial_eval_crs *crs, const ctt_eth_verkle_ipa_poly_eval_linear_domain *domain, ctt_eth_verkle_ipa_transcript *transcript, ctt_eth_verkle_ipa_multi_proof_aff *proof, const ctt_eth_verkle_ipa_polynomial_eval_poly polys[], size_t poly_len, const banderwagon_ec_aff commitments[], size_t commitment_len, const uint64_t opening_challenges_in_domain[], size_t opening_challenges_len) __attribute__((warn_unused_result));
  // void ctt_eth_verkle_ipa_multi_verify(const ctt_eth_verkle_ipa_polynomial_eval_crs *crs, const ctt_eth_verkle_ipa_poly_eval_linear_domain *domain, ctt_eth_verkle_ipa_transcript *transcript, const banderwagon_ec_aff commitments[], size_t commitments_len, const uint64_t opening_challenges_in_domain[], size_t opening_challenges_len, const banderwagon_fr evals_at_challenge[], size_t evals_len, const ctt_eth_verkle_ipa_multi_proof_aff *proof) __attribute__((warn_unused_result));

#ifdef __cplusplus
}
#endif

#endif // __CTT_H_ETHEREUM_VERKLE_IPA__