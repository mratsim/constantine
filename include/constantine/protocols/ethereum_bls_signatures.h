/** Constantine
 *  Copyright (c) 2018-2019    Status Research & Development GmbH
 *  Copyright (c) 2020-Present Mamy André-Ratsimbazafy
 *  Licensed and distributed under either of
 *    * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
 *    * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
 *  at your option. This file may not be copied, modified, or distributed except according to those terms.
 */
#ifndef __CTT_H_ETHEREUM_BLS_SIGNATURES__
#define __CTT_H_ETHEREUM_BLS_SIGNATURES__

#include "constantine/core/datatypes.h"
#include "constantine/core/serialization.h"
#include "constantine/hashes/sha256.h"

#ifdef __cplusplus
extern "C" {
#endif

// BLS signature types
// ------------------------------------------------------------------------------------------------

struct ctt_eth_bls_fp { byte raw[48]; };
struct ctt_eth_bls_fp2 { struct ctt_eth_bls_fp coords[2]; };

typedef struct { byte raw[32]; } ctt_eth_bls_seckey;
typedef struct { struct ctt_eth_bls_fp  x, y; } ctt_eth_bls_pubkey;
typedef struct { struct ctt_eth_bls_fp2 x, y; } ctt_eth_bls_signature;

typedef enum __attribute__((__packed__)) {
    cttBLS_Success,
    cttBLS_VerificationFailure,
    cttBLS_PointAtInfinity,
    cttBLS_ZeroLengthAggregation,
    cttBLS_InconsistentLengthsOfInputs,
} ctt_eth_bls_status;

static const char* ctt_eth_bls_status_to_string(ctt_eth_bls_status status) {
  static const char* const statuses[] = {
    "cttBLS_Success",
    "cttBLS_VerificationFailure",
    "cttBLS_PointAtInfinity",
    "cttBLS_ZeroLengthAggregation",
    "cttBLS_InconsistentLengthsOfInputs",
  };
  size_t length = sizeof statuses / sizeof *statuses;
  if (0 <= status && status < length) {
    return statuses[status];
  }
  return "cttBLS_InvalidStatusCode";
}

// Comparisons
// ------------------------------------------------------------------------------------------------

ctt_bool ctt_eth_bls_pubkey_is_zero(const ctt_eth_bls_pubkey* pubkey) __attribute__((warn_unused_result));
ctt_bool ctt_eth_bls_signature_is_zero(const ctt_eth_bls_signature* sig) __attribute__((warn_unused_result));

ctt_bool ctt_eth_bls_pubkeys_are_equal(const ctt_eth_bls_pubkey* a,
                                       const ctt_eth_bls_pubkey* b) __attribute__((warn_unused_result));
ctt_bool ctt_eth_bls_signatures_are_equal(const ctt_eth_bls_signature* a,
                                          const ctt_eth_bls_signature* b) __attribute__((warn_unused_result));

// Input validation
// ------------------------------------------------------------------------------------------------

/** Validate the secret key.
 *
 *  Regarding timing attacks, this will leak timing information only if the key is invalid.
 *  Namely, the secret key is 0 or the secret key is too large.
 */
ctt_codec_scalar_status ctt_eth_bls_validate_seckey(const ctt_eth_bls_seckey* seckey) __attribute__((warn_unused_result));

/** Validate the public key.
 *
 *  This is an expensive operation that can be cached.
 */
ctt_codec_ecc_status ctt_eth_bls_validate_pubkey(const ctt_eth_bls_pubkey* pubkey) __attribute__((warn_unused_result));

/** Validate the signature.
 *
 *  This is an expensive operation that can be cached.
 */
ctt_codec_ecc_status ctt_eth_bls_validate_signature(const ctt_eth_bls_signature* pubkey) __attribute__((warn_unused_result));

// Codecs
// ------------------------------------------------------------------------------------------------
/** Serialize a secret key
 *
 *  Returns cttCodecScalar_Success if successful
 */
ctt_codec_scalar_status ctt_eth_bls_serialize_seckey(byte dst[32], const ctt_eth_bls_seckey* seckey) __attribute__((warn_unused_result));

/** Serialize a public key in compressed (Zcash) format
 *
 *  Returns cttCodecEcc_Success if successful
 */
ctt_codec_ecc_status ctt_eth_bls_serialize_pubkey_compressed(byte dst[48], const ctt_eth_bls_pubkey* pubkey) __attribute__((warn_unused_result));

/** Serialize a signature in compressed (Zcash) format
 *
 *  Returns cttCodecEcc_Success if successful
 */
ctt_codec_ecc_status ctt_eth_bls_serialize_signature_compressed(byte dst[96], const ctt_eth_bls_signature* sig) __attribute__((warn_unused_result));

/** Deserialize a secret key
 *  This also validates the secret key.
 *
 *  This is protected against side-channel unless your key is invalid.
 *  In that case it will like whether it's all zeros or larger than the curve order.
 */
ctt_codec_scalar_status ctt_eth_bls_deserialize_seckey(ctt_eth_bls_seckey* seckey, const byte src[32]) __attribute__((warn_unused_result));

/** Deserialize a public key in compressed (Zcash) format.
 *  This does not validate the public key.
 *  It is intended for cases where public keys are stored in a trusted location
 *  and validation can be cached.
 *
 *  Warning ⚠:
 *    This procedure skips the very expensive subgroup checks.
 *    Not checking subgroup exposes a protocol to small subgroup attacks.
 *
 *  Returns cttCodecEcc_Success if successful
 */
ctt_codec_ecc_status ctt_eth_bls_deserialize_pubkey_compressed_unchecked(ctt_eth_bls_pubkey* pubkey, const byte src[48]) __attribute__((warn_unused_result));

/** Deserialize a public_key in compressed (Zcash) format.
 *  This also validates the public key.
 *
 *  Returns cttCodecEcc_Success if successful
 */
ctt_codec_ecc_status ctt_eth_bls_deserialize_pubkey_compressed(ctt_eth_bls_pubkey* pubkey, const byte src[48]) __attribute__((warn_unused_result));

/** Deserialize a signature in compressed (Zcash) format.
 *  This does not validate the signature.
 *  It is intended for cases where public keys are stored in a trusted location
 *  and validation can be cached.
 *
 *  Warning ⚠:
 *    This procedure skips the very expensive subgroup checks.
 *    Not checking subgroup exposes a protocol to small subgroup attacks.
 *
 *  Returns cttCodecEcc_Success if successful
 */
ctt_codec_ecc_status ctt_eth_bls_deserialize_signature_compressed_unchecked(ctt_eth_bls_signature* sig, const byte src[96]) __attribute__((warn_unused_result));

/** Deserialize a signature in compressed (Zcash) format.
 *  This also validates the signature.
 *
 *  Returns cttCodecEcc_Success if successful
 */
ctt_codec_ecc_status ctt_eth_bls_deserialize_signature_compressed(ctt_eth_bls_signature* sig, const byte src[96]) __attribute__((warn_unused_result));

// BLS signatures
// ------------------------------------------------------------------------------------------------

/** Derive the public key matching with a secret key
 *
 *  Secret protection:
 *  - A valid secret key will only leak that it is valid.
 *  - An invalid secret key will leak whether it's all zero or larger than the curve order.
 */
void ctt_eth_bls_derive_pubkey(ctt_eth_bls_pubkey* pubkey, const ctt_eth_bls_seckey* seckey);

/** Produce a signature for the message under the specified secret key
 *  Signature is on BLS12-381 G2 (and public key on G1)
 *
 *  For message domain separation purpose, the tag is `BLS_SIG_BLS12381G2_XMD:SHA-256_SSWU_RO_POP_`
 *
 *  Input:
 *  - A secret key
 *  - A message
 *
 *  Output:
 *  - `signature` is overwritten with `message` signed with `secretKey`
 *    with the scheme
 *  - A status code indicating success or if the secret key is invalid.
 *
 *  Secret protection:
 *  - A valid secret key will only leak that it is valid.
 *  - An invalid secret key will leak whether it's all zero or larger than the curve order.
 */
void ctt_eth_bls_sign(ctt_eth_bls_signature* sig,
                      const ctt_eth_bls_seckey* seckey,
                      const byte* message, ptrdiff_t message_len);

/** Check that a signature is valid for a message
 *  under the provided public key.
 *  returns `true` if the signature is valid, `false` otherwise.
 *
 *  For message domain separation purpose, the tag is `BLS_SIG_BLS12381G2_XMD:SHA-256_SSWU_RO_POP_`
 *
 *  Input:
 *  - A public key initialized by one of the key derivation or deserialization procedure.
 *    Or validated via validate_pubkey
 *  - A message
 *  - A signature initialized by one of the key derivation or deserialization procedure.
 *    Or validated via validate_signature
 *
 *  Output:
 *  - a status code with verification success if signature is valid
 *    or indicating verification failure
 *
 *  In particular, the public key and signature are assumed to be on curve and subgroup-checked.
 */
ctt_eth_bls_status ctt_eth_bls_verify(const ctt_eth_bls_pubkey* pubkey,
                                      const byte* message, ptrdiff_t message_len,
                                      const ctt_eth_bls_signature* sig) __attribute__((warn_unused_result));

// TODO: API for pubkeys and signature aggregation. Return a bool or a status code or nothing?

/** Check that a signature is valid for a message
 *  under the aggregate of provided public keys.
 *  returns `true` if the signature is valid, `false` otherwise.
 *
 *  For message domain separation purpose, the tag is `BLS_SIG_BLS12381G2_XMD:SHA-256_SSWU_RO_POP_`
 *
 *  Input:
 *  - Public keys initialized by one of the key derivation or deserialization procedure.
 *    Or validated via validate_pubkey
 *  - A message
 *  - A signature initialized by one of the key derivation or deserialization procedure.
 *    Or validated via validate_signature
 *
 *  In particular, the public keys and signature are assumed to be on curve subgroup checked.
 */
ctt_eth_bls_status ctt_eth_bls_fast_aggregate_verify(const ctt_eth_bls_pubkey pubkeys[], ptrdiff_t pubkeys_len,
                                                     const byte* message, ptrdiff_t message_len,
                                                     const ctt_eth_bls_signature* aggregate_sig) __attribute__((warn_unused_result));

#ifdef __cplusplus
}
#endif

#endif