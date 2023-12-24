/** Constantine
 *  Copyright (c) 2018-2019    Status Research & Development GmbH
 *  Copyright (c) 2020-Present Mamy André-Ratsimbazafy
 *  Licensed and distributed under either of
 *    * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
 *    * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
 *  at your option. This file may not be copied, modified, or distributed except according to those terms.
 */
#ifndef __CTT_H_BLS12_381_CODECS__
#define __CTT_H_BLS12_381_CODECS__

#include "constantine/core/datatypes.h"
#include "constantine/core/serialization.h"
#include "constantine/curves/bigints.h"
#include "constantine/curves/bls12_381.h"

#ifdef __cplusplus
extern "C" {
#endif

/** Validate a scalar
 *  Regarding timing attacks, this will leak information
 *  if the scalar is 0 or larger than the curve order.
 */
ctt_codec_scalar_status ctt_bls12_381_validate_scalar(const big255* scalar)  __attribute__((warn_unused_result));

/** Validate a G1 point
 *  This is an expensive operation that can be cached
 */
ctt_codec_ecc_status ctt_bls12_381_validate_g1(const bls12_381_g1_aff* point)  __attribute__((warn_unused_result));

/** Validate a G2 point
 *  This is an expensive operation that can be cached
 */
ctt_codec_ecc_status ctt_bls12_381_validate_g2(const bls12_381_g2_aff* point)  __attribute__((warn_unused_result));

/** Serialize a scalar
 *  Returns cttCodecScalar_Success if successful
 */
ctt_codec_scalar_status ctt_bls12_381_serialize_scalar(byte dst[32], const big255* scalar) __attribute__((warn_unused_result));

/** Deserialize a scalar
 *  Also validates the scalar range
 *
 *  This is protected against side-channel unless the scalar is invalid.
 *  In that case it will leak whether it's all zeros or larger than the curve order.
 *
 *  This special-cases (and leaks) 0 scalar as this is a special-case in most protocols
 *  or completely invalid (for secret keys).
 */
ctt_codec_scalar_status ctt_bls12_381_deserialize_scalar(big255* dst, const byte src[32]) __attribute__((warn_unused_result));

/** Serialize a BLS12-381 G1 point in compressed (Zcash) format
 *
 *  Returns cttCodecEcc_Success if successful
 */
ctt_codec_ecc_status ctt_bls12_381_serialize_g1_compressed(byte dst[48], const bls12_381_g1_aff* src) __attribute__((warn_unused_result));

/** Deserialize a BLS12-381 G1 point in compressed (Zcash) format.
 *
 *  Warning ⚠:
 *    This procedure skips the very expensive subgroup checks.
 *    Not checking subgroup exposes a protocol to small subgroup attacks.
 */
ctt_codec_ecc_status ctt_bls12_381_deserialize_g1_compressed_unchecked(bls12_381_g1_aff* dst, const byte src[48]) __attribute__((warn_unused_result));

/** Deserialize a BLS12-381 G1 point in compressed (Zcash) format
 *  This also validates the G1 point
 */
ctt_codec_ecc_status ctt_bls12_381_deserialize_g1_compressed(bls12_381_g1_aff* dst, const byte src[48]) __attribute__((warn_unused_result));

/** Serialize a BLS12-381 G2 point in compressed (Zcash) format
 *
 *  Returns cttCodecEcc_Success if successful
 */
ctt_codec_ecc_status ctt_bls12_381_serialize_g2_compressed(byte dst[96], const bls12_381_g2_aff* src) __attribute__((warn_unused_result));

/** Deserialize a BLS12-381 G2 point in compressed (Zcash) format.
 *
 *  Warning ⚠:
 *    This procedure skips the very expensive subgroup checks.
 *    Not checking subgroup exposes a protocol to small subgroup attacks.
 */
ctt_codec_ecc_status ctt_bls12_381_deserialize_g2_compressed_unchecked(bls12_381_g2_aff* dst, const byte src[96]) __attribute__((warn_unused_result));

/** Deserialize a BLS12-381 G2 point in compressed (Zcash) format
 *  This also validates the G2 point
 */
ctt_codec_ecc_status ctt_bls12_381_deserialize_g2_compressed(bls12_381_g2_aff* dst, const byte src[96]) __attribute__((warn_unused_result));
#ifdef __cplusplus
}
#endif

#endif // __CTT_H_BLS12_381_CODECS__
