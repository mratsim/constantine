/*
 * Constantine
 * Copyright (c) 2018-2019    Status Research & Development GmbH
 * Copyright (c) 2020-Present Mamy André-Ratsimbazafy
 * Licensed and distributed under either of
 *   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
 *   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
 * at your option. This file may not be copied, modified, or distributed except according to those terms.
 */
#ifndef __CTT_H_BLSSIGPOP_BLS12381G2__
#define __CTT_H_BLSSIGPOP_BLS12381G2__

#ifdef __cplusplus
extern "C" {
#endif

#if defined(__SIZE_TYPE__) && defined(__PTRDIFF_TYPE__)
typedef __SIZE_TYPE__    size_t;
typedef __PTRDIFF_TYPE__ ptrdiff_t;
#else
#include <stddef.h>
#endif

#if defined(__UINT8_TYPE__) && defined(__UINT32_TYPE__) && defined(__UINT64_TYPE__)
typedef __UINT8_TYPE__   uint8_t;
typedef __UINT32_TYPE__  uint32_t;
typedef __UINT64_TYPE__  uint64_t;
#else
#include <stdint.h>
#endif

// https://github.com/nim-lang/Nim/blob/v1.6.12/lib/nimbase.h#L318
#if defined(__STDC_VERSION__) && __STDC_VERSION__>=199901
# define bool _Bool
#else
# define bool unsigned char

typedef uint8_t          byte;

typedef struct ctt_blssigpop_bls12381g2_seckey ctt_blssigpop_bls12381g2_seckey;
typedef struct ctt_blssigpop_bls12381g2_pubkey ctt_blssigpop_bls12381g2_pubkey;
typedef struct ctt_blssigpop_bls12381g2_signature ctt_blssigpop_bls12381g2_signature;
typedef enum __attribute__((__packed__)) {
    cttBLS_Success,
    cttBLS_VerificationFailure,
    cttBLS_InvalidEncoding,
    cttBLS_CoordinateGreaterOrEqualThanModulus,
    cttBLS_PointAtInfinity,
    cttBLS_PointNotOnCurve,
    cttBLS_PointNotInSubgroup,
    cttBLS_ZeroSecretKey,
    cttBLS_SecretKeyLargerThanCurveOrder,
    cttBLS_ZeroLengthAggregation,
    cttBLS_InconsistentLengthsOfInputs,
} ctt_blssigpop_bls12381g2_status;

// TODO __declspec(noalias) for MSVC
#ifdef __GNUC__
#define ctt_pure __attribute__((pure))
#else
#define ctt_pure
#endif

/*
 * Initializes the library:
 * - detect CPU features like ADX instructions support (MULX, ADCX, ADOX)
 */
void ctt_blssigpop_bls12381g2_init_NimMain(void);

// Comparisons
// ------------------------------------------------------------------------------------------------

bool ctt_blssigpop_bls12381g2_pubkey_is_zero(const ctt_blssigpop_bls12381g2_pubkey* pubkey) ctt_pure;
bool ctt_blssigpop_bls12381g2_signature_is_zero(const ctt_blssigpop_bls12381g2_pubkey* signature) ctt_pure;

bool ctt_blssigpop_bls12381g2_pubkeys_are_equal(const ctt_blssigpop_bls12381g2_pubkey* a,
                                                const ctt_blssigpop_bls12381g2_pubkey* b) ctt_pure;
bool ctt_blssigpop_bls12381g2_signatures_are_equal(const ctt_blssigpop_bls12381g2_signature* a,
                                                   const ctt_blssigpop_bls12381g2_signature* b) ctt_pure;

// Input validation
// ------------------------------------------------------------------------------------------------

/*
 * Validate the secret key.
 * Regarding timing attacks, this will leak timing information only if the key is invalid.
 * Namely, the secret key is 0 or the secret key is too large.
 */
ctt_blssigpop_bls12381g2_status ctt_blssigpop_bls12381g2_validate_seckey(const ctt_blssigpop_bls12381g2_seckey* seckey) ctt_pure;

/*
 * Validate the public key.
 * This is an expensive operation that can be cached.
 */
ctt_blssigpop_bls12381g2_status ctt_blssigpop_bls12381g2_validate_pubkey(const ctt_blssigpop_bls12381g2_pubkey* pubkey) ctt_pure;

/*
 * Validate the signature.
 * This is an expensive operation that can be cached.
 */
ctt_blssigpop_bls12381g2_status ctt_blssigpop_bls12381g2_validate_signature(const ctt_blssigpop_bls12381g2_signature* pubkey) ctt_pure;

// Codecs
// ------------------------------------------------------------------------------------------------
/*
 * Serialize a secret key
 * Returns cttBLS_Success if successful
 */
ctt_blssigpop_bls12381g2_status ctt_blssigpop_bls12381g2_serialize_seckey(byte dst[32], const ctt_blssigpop_bls12381g2_seckey* seckey);

/*
 * Serialize a public key in compressed (Zcash) format
 * Returns cttBLS_Success if successful
 */
ctt_blssigpop_bls12381g2_status ctt_blssigpop_bls12381g2_serialize_pubkey_compressed(byte dst[48], const ctt_blssigpop_bls12381g2_pubkey* pubkey);

/*
 * Serialize a signature in compressed (Zcash) format
 * Returns cttBLS_Success if successful
 */
ctt_blssigpop_bls12381g2_status ctt_blssigpop_bls12381g2_serialize_signature_compressed(byte dst[96], const ctt_blssigpop_bls12381g2_signature* signature);

/*
 * Deserialize a secret key
 * This also validates the secret key.
 *
 * This is protected against side-channel unless your key is invalid.
 * In that case it will like whether it's all zeros or larger than the curve order.
 */
ctt_blssigpop_bls12381g2_status ctt_blssigpop_bls12381g2_deserialize_seckey(ctt_blssigpop_bls12381g2_seckey* seckey, const byte src[32]);

/*
 * Deserialize a public key in compressed (Zcash) format.
 * This does not validate the public key.
 * It is intended for cases where public keys are stored in a trusted location
 * and validation can be cached.
 *
 * Warning ⚠:
 *   This procedure skips the very expensive subgroup checks.
 *   Not checking subgroup exposes a protocol to small subgroup attacks.
 *
 * Returns cttBLS_Success if successful
 */
ctt_blssigpop_bls12381g2_status ctt_blssigpop_bls12381g2_deserialize_pubkey_compressed_unchecked(ctt_blssigpop_bls12381g2_pubkey* pubkey, const byte src[48]);

/*
 * Deserialize a public_key in compressed (Zcash) format.
 * This also validates the public key.
 *
 * Returns cttBLS_Success if successful
 */
ctt_blssigpop_bls12381g2_status ctt_blssigpop_bls12381g2_deserialize_pubkey_compressed(ctt_blssigpop_bls12381g2_pubkey* pubkey, const byte src[48]);

/*
 * Deserialize a signature in compressed (Zcash) format.
 * This does not validate the signature.
 * It is intended for cases where public keys are stored in a trusted location
 * and validation can be cached.
 *
 * Warning ⚠:
 *   This procedure skips the very expensive subgroup checks.
 *   Not checking subgroup exposes a protocol to small subgroup attacks.
 *
 * Returns cttBLS_Success if successful
 */
ctt_blssigpop_bls12381g2_status ctt_blssigpop_bls12381g2_deserialize_signature_compressed_unchecked(ctt_blssigpop_bls12381g2_signature* signature, const byte src[96]);

/*
 * Deserialize a signature in compressed (Zcash) format.
 * This also validates the signature.
 *
 * Returns cttBLS_Success if successful
 */
ctt_blssigpop_bls12381g2_status ctt_blssigpop_bls12381g2_deserialize_signature_compressed(ctt_blssigpop_bls12381g2_signature* signature, const byte src[96]);

// BLS signatures
// ------------------------------------------------------------------------------------------------

/*
 * Derive the public key matching with a secret key
 *
 * Secret protection:
 * - A valid secret key will only leak that it is valid.
 * - An invalid secret key will leak whether it's all zero or larger than the curve order.
 */
ctt_blssigpop_bls12381g2_status ctt_blssigpop_bls12381g2_derive_pubkey(ctt_blssigpop_bls12381g2_pubkey* pubkey, const ctt_blssigpop_bls12381g2_seckey* seckey);

/*
 * Produce a signature for the message under the specified secret key
 * Signature is on BLS12-381 G2 (and public key on G1)
 *
 * For message domain separation purpose, the tag is `BLS_SIG_BLS12381G2_XMD:SHA-256_SSWU_RO_POP_`
 *
 * Input:
 * - A secret key
 * - A message
 *
 * Output:
 * - `signature` is overwritten with `message` signed with `secretKey`
 *   with the scheme
 * - A status code indicating success or if the secret key is invalid.
 *
 * Secret protection:
 * - A valid secret key will only leak that it is valid.
 * - An invalid secret key will leak whether it's all zero or larger than the curve order.
 */
ctt_blssigpop_bls12381g2_status ctt_blssigpop_bls12381g2_sign(ctt_blssigpop_bls12381g2_signature* signature,
                                                              const ctt_blssigpop_bls12381g2_seckey* seckey,
                                                              const byte* message, ptrdiff_t message_len)

/*
 * Check that a signature is valid for a message
 * under the provided public key.
 * returns `true` if the signature is valid, `false` otherwise.
 *
 * For message domain separation purpose, the tag is `BLS_SIG_BLS12381G2_XMD:SHA-256_SSWU_RO_POP_`
 *
 * Input:
 * - A public key initialized by one of the key derivation or deserialization procedure.
 *   Or validated via validate_pubkey
 * - A message
 * - A signature initialized by one of the key derivation or deserialization procedure.
 *   Or validated via validate_signature
 *
 * Output:
 * - a status code with verification success if signature is valid
 *   or indicating verification failure
 *
 * In particular, the public key and signature are assumed to be on curve and subgroup-checked.
 */
ctt_blssigpop_bls12381g2_status ctt_blssigpop_bls12381g2_verify(const ctt_blssigpop_bls12381g2_pubkey* pubkey,
                                                                const byte* message, ptrdiff_t message_len,
                                                                const ctt_blssigpop_bls12381g2_signature* signature) ctt_pure;

// TODO: API for pubkeys and signature aggregation. Return a bool or a status code or nothing?

/*
 * Check that a signature is valid for a message
 * under the aggregate of provided public keys.
 * returns `true` if the signature is valid, `false` otherwise.
 *
 * For message domain separation purpose, the tag is `BLS_SIG_BLS12381G2_XMD:SHA-256_SSWU_RO_POP_`
 *
 * Input:
 * - Public keys initialized by one of the key derivation or deserialization procedure.
 *   Or validated via validate_pubkey
 * - A message
 * - A signature initialized by one of the key derivation or deserialization procedure.
 *   Or validated via validate_signature
 *
 * In particular, the public keys and signature are assumed to be on curve subgroup checked.
 */
ctt_blssigpop_bls12381g2_status ctt_blssigpop_bls12381g2_fast_aggregate_verify(const ctt_blssigpop_bls12381g2_pubkey pubkeys[],
                                                                               const byte* message, ptrdiff_t message_len,
                                                                               const ctt_blssigpop_bls12381g2_signature* signature) ctt_pure;

#ifdef __cplusplus
}
#endif

#endif
