/** Constantine
 *  Copyright (c) 2018-2019    Status Research & Development GmbH
 *  Copyright (c) 2020-Present Mamy André-Ratsimbazafy
 *  Licensed and distributed under either of
 *    * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
 *    * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
 *  at your option. This file may not be copied, modified, or distributed except according to those terms.
 */
#ifndef __CTT_H_BIGINTS__
#define __CTT_H_BIGINTS__

#include "constantine/core/datatypes.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef struct { secret_word limbs[CTT_WORDS_REQUIRED(381)]; } big381;
typedef struct { secret_word limbs[CTT_WORDS_REQUIRED(255)]; } big255;
typedef struct { secret_word limbs[CTT_WORDS_REQUIRED(254)]; } big254;
typedef struct { secret_word limbs[CTT_WORDS_REQUIRED(253)]; } big253;

ctt_bool    ctt_big254_unmarshalBE(big254* dst, const byte src[], size_t src_len) __attribute__((warn_unused_result));
ctt_bool    ctt_big254_marshalBE(byte dst[], size_t dst_len, const big254* src) __attribute__((warn_unused_result));
ctt_bool    ctt_big255_unmarshalBE(big255* dst, const byte src[], size_t src_len) __attribute__((warn_unused_result));
ctt_bool    ctt_big255_marshalBE(byte dst[], size_t dst_len, const big255* src) __attribute__((warn_unused_result));
ctt_bool    ctt_big381_unmarshalBE(big381* dst, const byte src[], size_t src_len) __attribute__((warn_unused_result));
ctt_bool    ctt_big381_marshalBE(byte dst[], size_t dst_len, const big381* src) __attribute__((warn_unused_result));
ctt_bool    ctt_big253_unmarshalBE(big253* dst, const byte src[], size_t src_len) __attribute__((warn_unused_result));
ctt_bool    ctt_big253_marshalBE(byte dst[], size_t dst_len, const big253* src) __attribute__((warn_unused_result));

#ifdef __cplusplus
}
#endif

#endif // __CTT_H_BIGINTS__
