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
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef enum __attribute__((__packed__)) {
    cttEthVerkleIpa_Success,
    cttEthVerkleIpa_VerificationFailure,
    cttEthVerkleIpa_InputsLengthsMismatch,
    cttEthVerkleIpa_ScalarZero,
    cttEthVerkleIpa_ScalarLargerThanCurveOrder,
    cttEthVerkleIpa_EccInvalidEncoding,
    cttEthVerkleIpa_EccCoordinateGreaterThanOrEqualModulus,
    cttEthVerkleIpa_EccPointNotOnCurve,
    cttEthVerkleIpa_EccPointNotInSubGroup
} ctt_eth_verkle_ipa_status;

static const char* ctt_eth_verkle_ipa_status_to_string(ctt_eth_verkle_ipa_status status) {
  static const char* const statuses[] = {
    "cttEthVerkleIpa_Success",
    "cttEthVerkleIpa_VerificationFailure",
    "cttEthVerkleIpa_InputsLengthsMismatch",
    "cttEthVerkleIpa_ScalarZero",
    "cttEthVerkleIpa_ScalarLargerThanCurveOrder",
    "cttEthVerkleIpa_EccInvalidEncoding",
    "cttEthVerkleIpa_EccCoordinateGreaterThanOrEqualModulus",
    "cttEthVerkleIpa_EccPointNotOnCurve",
    "cttEthVerkleIpa_EccPointNotInSubGroup"
  };
  size_t length = sizeof statuses / sizeof *statuses;
  if (0 <= status && status < length) {
    return statuses[status];
  }
  return "cttEthVerkleIpa_InvalidStatusCode";
}

// Opaque types for Nim-defined types
typedef struct Fr Fr;
typedef struct Banderwagon Banderwagon;
typedef struct EC_TwEdw EC_TwEdw;
typedef struct Fp Fp;

typedef union {
    uint8_t u8;
    uint16_t u16;
    uint32_t u32;
    uint64_t u64;
    unsigned int u;
} SomeUnsignedInt;

typedef struct {
    SomeUnsignedInt* values;  
    size_t length;
} SomeUnsignedInt_Array;

// Define types for openArray
typedef struct {
    Fr* data;    
    size_t len;   
} Fr_BanderWagon_OpenArray;

typedef struct {
    EC_TwEdw* data;    
    size_t len;         
} EC_TwEdw_Fp_Banderwagon_OpenArray;

typedef struct {
    byte value[32];  // 32-byte array for field element
} Fp_Banderwagon;

typedef struct {
    byte value[32];  // 32-byte array for field element
} Fr_Banderwagon;

typedef struct {
    byte x[32];  // 32-byte x-coordinate
    byte y[32];  // 32-byte y-coordinate
} EC_TwEdw_Fp_Banderwagon;

typedef struct {
    byte x[32];  // 32-byte x-coordinate
    byte y[32];  // 32-byte y-coordinate
} EC;

typedef struct {
    EC* points;  
    size_t length;  
} PolynomialEval_EC;

typedef struct {
    Fr* points;  
    size_t length;  
} PolynomialEval_Fr;

typedef struct {
    EC* points;  
    size_t length;  
} PolynomialEval_EcAff;

typedef struct {
    Fr* domain_values;  
    size_t length; 
} PolyEvalLinearDomain_Fr;

typedef struct {
    EC* ec_points;  
    Fr* field_elements;      
    size_t logN;                         
} IpaProof_EcAff_Fr;

typedef struct {
    EC* ec_points;  
    Fr* field_elements;      
    size_t logN;                         
} IpaMultiProof_EcAff_Fr;

typedef struct {
    EC* ec_points;  
    size_t length;                       
} EcAffArray;

typedef struct EthVerkleIpaProof EthVerkleIpaProof;
typedef struct EthVerkleIpaMultiProof EthVerkleIpaMultiProof;
typedef struct IpaProof IpaProof;
typedef struct IpaMultiProof IpaMultiProof;
typedef struct EthVerkleTranscript EthVerkleTranscript;

typedef byte EthVerkleIpaProofBytes[544];       // Array of 544 bytes
typedef byte EthVerkleIpaMultiProofBytes[576]; 


ctt_eth_verkle_ipa_status ctt_eth_verkle_serialize(
    EthVerkleIpaProofBytes* dst, 
    const IpaProof* src
    ) __attribute__((warn_unused_result));

ctt_eth_verkle_ipa_status ctt_eth_verkle_serialize(
    EthVerkleIpaMultiProofBytes* dst,
    const IpaMultiProof* src
    ) __attribute__((warn_unused_result));

ctt_eth_verkle_ipa_status ctt_eth_verkle_deserialize(
    const EthVerkleIpaProof* dst, 
    EthVerkleIpaProofBytes* src
    ) __attribute__((warn_unused_result));

ctt_eth_verkle_ipa_status ctt_eth_verkle_deserialize(
    const EthVerkleIpaMultiProof* dst,
    EthVerkleIpaMultiProofBytes* src
    ) __attribute__((warn_unused_result));

ctt_eth_verkle_ipa_status ctt_eth_verkle_mapToBaseField(
    Fp_Banderwagon* dst, const EC_TwEdw_Fp_Banderwagon* p
    ) __attribute__((warn_unused_result));

ctt_eth_verkle_ipa_status ctt_eth_verkle_mapToScalarField(
    Fr_Banderwagon* res, const EC_TwEdw_Fp_Banderwagon* p
    ) __attribute__((warn_unused_result));

ctt_eth_verkle_ipa_status ctt_eth_verkle_batchMapToScalarField(
    Fr_BanderWagon_OpenArray* res, const EC_TwEdw_Fp_Banderwagon_OpenArray* p
    ) __attribute__((warn_unused_result));

ctt_eth_verkle_ipa_status ctt_eth_verkle_ipa_commit(
    const PolynomialEval_EC* crs,  
    EC* r,    
    const PolynomialEval_Fr* poly 
    ) __attribute__((warn_unused_result));

ctt_eth_verkle_ipa_status ctt_eth_verkle_ipa_prove(
    const PolynomialEval_EcAff* crs,
    const PolyEvalLinearDomain_Fr* domain,
    EthVerkleTranscript* transcript,
    Fr* eval_at_challenge,
    IpaProof_EcAff_Fr* proof,
    const PolynomialEval_Fr* poly,
    const EC* commitment,
    const Fr* opening_challenge
    ) __attribute__((warn_unused_result));

ctt_eth_verkle_ipa_status ctt_eth_verkle_ipa_verify(
    const PolynomialEval_EcAff* crs,
    const PolyEvalLinearDomain_Fr* domain,
    EthVerkleTranscript* transcript,
    const EC* commitment,
    const Fr* opening_challenge,
    Fr* eval_at_challenge,
    IpaProof_EcAff_Fr* proof
    ) __attribute__((warn_unused_result));

ctt_eth_verkle_ipa_status ctt_eth_verkle_ipa_multi_prove(
    const PolynomialEval_EcAff* crs,
    const PolyEvalLinearDomain_Fr* domain,
    EthVerkleTranscript* transcript,
    IpaMultiProof_EcAff_Fr* proof,
    const PolynomialEval_Fr* polys,
    const EC_TwEdw_Fp_Banderwagon_OpenArray* commitments,
    const Fr_BanderWagon_OpenArray* opening_challenges_in_domain
    ) __attribute__((warn_unused_result));

ctt_eth_verkle_ipa_status ctt_eth_verkle_ipa_multi_verify(
    const PolynomialEval_EcAff* crs,
    const PolyEvalLinearDomain_Fr* domain,
    EthVerkleTranscript* transcript,
    const EC_TwEdw_Fp_Banderwagon_OpenArray* commitments,
    const Fr_BanderWagon_OpenArray* opening_challenges_in_domain,
    Fr_BanderWagon_OpenArray* evals_at_challenges,
    IpaMultiProof_EcAff_Fr* proof
    ) __attribute__((warn_unused_result));

#ifdef __cplusplus
}
#endif

#endif // __CTT_H_ETHEREUM_EVM_PRECOMPILES__
