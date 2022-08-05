/*
 * Constantine
 * Copyright (c) 2018-2019    Status Research & Development GmbH
 * Copyright (c) 2020-Present Mamy André-Ratsimbazafy
 * Licensed and distributed under either of
 *   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
 *   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
 * at your option. This file may not be copied, modified, or distributed except according to those terms.
 */
#ifndef __CTT_H_BLS12381__
#define __CTT_H_BLS12381__

#ifdef __cplusplus
extern "C" {
#endif

#if defined{__SIZE_TYPE__} && defined(__PTRDIFF_TYPE__)
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

typedef size_t           secret_word;
typedef size_t           secret_bool;
typedef uint8_t          byte;

#define WordBitWidth         (sizeof(secret_word)*8)
#define words_required(bits) ((bits+WordBitWidth-1)/WordBitWidth)

typedef struct { secret_word limbs[words_required(255)]; } bls12381_fr;
typedef struct { secret_word limbs[words_required(381)]; } bls12381_fp;
typedef struct { bls12381_fp c[2]; } bls12381_fp2;
typedef struct { bls12381_fp x, y; } bls12381_ec_g1_aff;
typedef struct { bls12381_fp x, y, z; } bls12381_ec_g1_jac;
typedef struct { bls12381_fp x, y, z; } bls12381_ec_g1_prj;
typedef struct { bls12381_fp2 x, y; } bls12381_ec_g2_aff;
typedef struct { bls12381_fp2 x, y, z; } bls12381_ec_g2_jac;
typedef struct { bls12381_fp2 x, y, z; } bls12381_ec_g2_prj;


void        ctt_bls12381_fr_unmarshalBE(bls12381_fr* dst, const byte src[], ptrdiff_t src_len);
void        ctt_bls12381_fr_marshalBE(byte dst[], ptrdiff_t dst_len, const bls12381_fr* src);
secret_bool ctt_bls12381_fr_is_eq(const bls12381_fr* a, const bls12381_fr* b);
secret_bool ctt_bls12381_fr_is_zero(const bls12381_fr* a);
secret_bool ctt_bls12381_fr_is_one(const bls12381_fr* a);
secret_bool ctt_bls12381_fr_is_minus_one(const bls12381_fr* a);
void        ctt_bls12381_fr_set_zero(bls12381_fr* a);
void        ctt_bls12381_fr_set_one(bls12381_fr* a);
void        ctt_bls12381_fr_set_minus_one(bls12381_fr* a);
void        ctt_bls12381_fr_neg(bls12381_fr* a);
void        ctt_bls12381_fr_sum(bls12381_fr* r, const bls12381_fr* a, const bls12381_fr* b);
void        ctt_bls12381_fr_add_in_place(bls12381_fr* a, const bls12381_fr* b);
void        ctt_bls12381_fr_diff(bls12381_fr* r, const bls12381_fr* a, const bls12381_fr* b);
void        ctt_bls12381_fr_sub_in_place(bls12381_fr* a, const bls12381_fr* b);
void        ctt_bls12381_fr_double(bls12381_fr* r, const bls12381_fr* a);
void        ctt_bls12381_fr_double_in_place(bls12381_fr* a);

void        ctt_bls12381_fp_unmarshalBE(bls12381_fp* dst, const byte src[], ptrdiff_t src_len);
void        ctt_bls12381_fp_marshalBE(byte dst[], ptrdiff_t dst_len, const bls12381_fp* src);
secret_bool ctt_bls12381_fp_is_eq(const bls12381_fp* a, const bls12381_fp* b);
secret_bool ctt_bls12381_fp_is_zero(const bls12381_fp* a);
secret_bool ctt_bls12381_fp_is_one(const bls12381_fp* a);
secret_bool ctt_bls12381_fp_is_minus_one(const bls12381_fp* a);
void        ctt_bls12381_fp_set_zero(bls12381_fp* a);
void        ctt_bls12381_fp_set_one(bls12381_fp* a);
void        ctt_bls12381_fp_set_minus_one(bls12381_fp* a);
void        ctt_bls12381_fp_neg(bls12381_fp* a);
void        ctt_bls12381_fp_sum(bls12381_fp* r, const bls12381_fp* a, const bls12381_fp* b);
void        ctt_bls12381_fp_add_in_place(bls12381_fp* a, const bls12381_fp* b);
void        ctt_bls12381_fp_diff(bls12381_fp* r, const bls12381_fp* a, const bls12381_fp* b);
void        ctt_bls12381_fp_sub_in_place(bls12381_fp* a, const bls12381_fp* b);
void        ctt_bls12381_fp_double(bls12381_fp* r, const bls12381_fp* a);
void        ctt_bls12381_fp_double_in_place(bls12381_fp* a);

secret_bool ctt_bls12381_fp2_is_eq(const bls12381_fp2* a, const bls12381_fp2* b);
secret_bool ctt_bls12381_fp2_is_zero(const bls12381_fp2* a);
secret_bool ctt_bls12381_fp2_is_one(const bls12381_fp2* a);
secret_bool ctt_bls12381_fp2_is_minus_one(const bls12381_fp2* a);
void        ctt_bls12381_fp2_set_zero(bls12381_fp2* a);
void        ctt_bls12381_fp2_set_one(bls12381_fp2* a);
void        ctt_bls12381_fp2_set_minus_one(bls12381_fp2* a);
void        ctt_bls12381_fp2_neg(bls12381_fp2* a);
void        ctt_bls12381_fp2_sum(bls12381_fp2* r, const bls12381_fp2* a, const bls12381_fp2* b);
void        ctt_bls12381_fp2_add_in_place(bls12381_fp2* a, const bls12381_fp2* b);
void        ctt_bls12381_fp2_diff(bls12381_fp2* r, const bls12381_fp2* a, const bls12381_fp2* b);
void        ctt_bls12381_fp2_sub_in_place(bls12381_fp2* a, const bls12381_fp2* b);
void        ctt_bls12381_fp2_double(bls12381_fp2* r, const bls12381_fp2* a);
void        ctt_bls12381_fp2_double_in_place(bls12381_fp2* a);

secret_bool ctt_bls12381_ec_g1_aff_is_eq(const bls12381_ec_g1_aff* P, const bls12381_ec_g1_aff* Q);
secret_bool ctt_bls12381_ec_g1_aff_is_inf(const bls12381_ec_g1_aff* P);
void        ctt_bls12381_ec_g1_aff_set_inf(bls12381_ec_g1_aff* P);
void        ctt_bls12381_ec_g1_aff_ccopy(bls12381_ec_g1_aff* P, const bls12381_ec_g1_aff* Q, const secret_bool* ctl);
secret_bool ctt_bls12381_ec_g1_aff_is_on_curve(const bls12381_fp* x, const bls12381_fp* y);
void        ctt_bls12381_ec_g1_aff_neg(bls12381_ec_g1_aff* P, const bls12381_ec_g1_aff* Q);
void        ctt_bls12381_ec_g1_aff_neg_in_place(bls12381_ec_g1_aff* P);

secret_bool ctt_bls12381_ec_g2_aff_is_eq(const bls12381_ec_g2_aff* P, const bls12381_ec_g2_aff* Q);
secret_bool ctt_bls12381_ec_g2_aff_is_inf(const bls12381_ec_g2_aff* P);
void        ctt_bls12381_ec_g2_aff_set_inf(bls12381_ec_g2_aff* P);
void        ctt_bls12381_ec_g2_aff_ccopy(bls12381_ec_g2_aff* P, const bls12381_ec_g2_aff* Q, const secret_bool* ctl);
secret_bool ctt_bls12381_ec_g2_aff_is_on_curve(const bls12381_fp2* x, const bls12381_fp2* y);
void        ctt_bls12381_ec_g2_aff_neg(bls12381_ec_g2_aff* P, const bls12381_ec_g2_aff* Q);
void        ctt_bls12381_ec_g2_aff_neg_in_place(bls12381_ec_g2_aff* P);

/*
 * Initializes the library:
 * - the Nim runtime if heap-allocated types are used,
 *   this is the case only if Constantine is multithreaded.
 * - runtime CPU features detection
 */
void ctt_bls12381_NimMain(void);


#ifdef __cplusplus
}
#endif


#endif
