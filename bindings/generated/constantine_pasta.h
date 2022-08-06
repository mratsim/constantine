/*
 * Constantine
 * Copyright (c) 2018-2019    Status Research & Development GmbH
 * Copyright (c) 2020-Present Mamy André-Ratsimbazafy
 * Licensed and distributed under either of
 *   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
 *   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
 * at your option. This file may not be copied, modified, or distributed except according to those terms.
 */
#ifndef __CTT_H_PASTA__
#define __CTT_H_PASTA__

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

typedef struct { secret_word limbs[words_required(255)]; } pallas_fr;
typedef struct { secret_word limbs[words_required(255)]; } pallas_fp;
typedef struct { secret_word limbs[words_required(255)]; } vesta_fr;
typedef struct { secret_word limbs[words_required(255)]; } vesta_fp;
typedef struct { pallas_fp x, y; } pallas_ec_aff;
typedef struct { pallas_fp x, y, z; } pallas_ec_jac;
typedef struct { pallas_fp x, y, z; } pallas_ec_prj;
typedef struct { vesta_fp x, y; } vesta_ec_aff;
typedef struct { vesta_fp x, y, z; } vesta_ec_jac;
typedef struct { vesta_fp x, y, z; } vesta_ec_prj;


void        ctt_pallas_fr_unmarshalBE(pallas_fr* dst, const byte src[], ptrdiff_t src_len);
void        ctt_pallas_fr_marshalBE(byte dst[], ptrdiff_t dst_len, const pallas_fr* src);
secret_bool ctt_pallas_fr_is_eq(const pallas_fr* a, const pallas_fr* b);
secret_bool ctt_pallas_fr_is_zero(const pallas_fr* a);
secret_bool ctt_pallas_fr_is_one(const pallas_fr* a);
secret_bool ctt_pallas_fr_is_minus_one(const pallas_fr* a);
void        ctt_pallas_fr_set_zero(pallas_fr* a);
void        ctt_pallas_fr_set_one(pallas_fr* a);
void        ctt_pallas_fr_set_minus_one(pallas_fr* a);
void        ctt_pallas_fr_neg(pallas_fr* a);
void        ctt_pallas_fr_sum(pallas_fr* r, const pallas_fr* a, const pallas_fr* b);
void        ctt_pallas_fr_add_in_place(pallas_fr* a, const pallas_fr* b);
void        ctt_pallas_fr_diff(pallas_fr* r, const pallas_fr* a, const pallas_fr* b);
void        ctt_pallas_fr_sub_in_place(pallas_fr* a, const pallas_fr* b);
void        ctt_pallas_fr_double(pallas_fr* r, const pallas_fr* a);
void        ctt_pallas_fr_double_in_place(pallas_fr* a);
void        ctt_pallas_fr_prod(pallas_fr* r, const pallas_fr* a, const pallas_fr* b);
void        ctt_pallas_fr_mul_in_place(pallas_fr* a, const pallas_fr* b);
void        ctt_pallas_fr_square(pallas_fr* r, const pallas_fr* a);
void        ctt_pallas_fr_square_in_place(pallas_fr* a);
void        ctt_pallas_fr_div2(pallas_fr* a);
void        ctt_pallas_fr_inv(pallas_fr* r, const pallas_fr* a);
void        ctt_pallas_fr_inv_in_place(pallas_fr* a);
void        ctt_pallas_fr_csetZero(pallas_fr* a, const secret_bool ctl);
void        ctt_pallas_fr_csetOne(pallas_fr* a, const secret_bool ctl);
void        ctt_pallas_fr_cneg_in_place(pallas_fr* a, const secret_bool ctl);
void        ctt_pallas_fr_cadd_in_place(pallas_fr* a, const pallas_fr* b, const secret_bool ctl);
void        ctt_pallas_fr_csub_in_place(pallas_fr* a, const pallas_fr* b, const secret_bool ctl);

void        ctt_pallas_fp_unmarshalBE(pallas_fp* dst, const byte src[], ptrdiff_t src_len);
void        ctt_pallas_fp_marshalBE(byte dst[], ptrdiff_t dst_len, const pallas_fp* src);
secret_bool ctt_pallas_fp_is_eq(const pallas_fp* a, const pallas_fp* b);
secret_bool ctt_pallas_fp_is_zero(const pallas_fp* a);
secret_bool ctt_pallas_fp_is_one(const pallas_fp* a);
secret_bool ctt_pallas_fp_is_minus_one(const pallas_fp* a);
void        ctt_pallas_fp_set_zero(pallas_fp* a);
void        ctt_pallas_fp_set_one(pallas_fp* a);
void        ctt_pallas_fp_set_minus_one(pallas_fp* a);
void        ctt_pallas_fp_neg(pallas_fp* a);
void        ctt_pallas_fp_sum(pallas_fp* r, const pallas_fp* a, const pallas_fp* b);
void        ctt_pallas_fp_add_in_place(pallas_fp* a, const pallas_fp* b);
void        ctt_pallas_fp_diff(pallas_fp* r, const pallas_fp* a, const pallas_fp* b);
void        ctt_pallas_fp_sub_in_place(pallas_fp* a, const pallas_fp* b);
void        ctt_pallas_fp_double(pallas_fp* r, const pallas_fp* a);
void        ctt_pallas_fp_double_in_place(pallas_fp* a);
void        ctt_pallas_fp_prod(pallas_fp* r, const pallas_fp* a, const pallas_fp* b);
void        ctt_pallas_fp_mul_in_place(pallas_fp* a, const pallas_fp* b);
void        ctt_pallas_fp_square(pallas_fp* r, const pallas_fp* a);
void        ctt_pallas_fp_square_in_place(pallas_fp* a);
void        ctt_pallas_fp_div2(pallas_fp* a);
void        ctt_pallas_fp_inv(pallas_fp* r, const pallas_fp* a);
void        ctt_pallas_fp_inv_in_place(pallas_fp* a);
void        ctt_pallas_fp_csetZero(pallas_fp* a, const secret_bool ctl);
void        ctt_pallas_fp_csetOne(pallas_fp* a, const secret_bool ctl);
void        ctt_pallas_fp_cneg_in_place(pallas_fp* a, const secret_bool ctl);
void        ctt_pallas_fp_cadd_in_place(pallas_fp* a, const pallas_fp* b, const secret_bool ctl);
void        ctt_pallas_fp_csub_in_place(pallas_fp* a, const pallas_fp* b, const secret_bool ctl);

secret_bool ctt_pallas_fp_is_square(const pallas_fp* a);
void        ctt_pallas_fp_invsqrt(pallas_fp* r, const pallas_fp* a);
secret_bool ctt_pallas_fp_invsqrt_in_place(pallas_fp* r, const pallas_fp* a);
void        ctt_pallas_fp_sqrt_in_place(pallas_fp* a);
secret_bool ctt_pallas_fp_sqrt_if_square_in_place(pallas_fp* a);
void        ctt_pallas_fp_sqrt_invsqrt(pallas_fp* sqrt, pallas_fp* invsqrt, const pallas_fp* a);
secret_bool ctt_pallas_fp_sqrt_invsqrt_if_square(pallas_fp* sqrt, pallas_fp* invsqrt, const pallas_fp* a);
secret_bool ctt_pallas_fp_sqrt_ratio_if_square(pallas_fp* r, const pallas_fp* u, const pallas_fp* v);

void        ctt_vesta_fr_unmarshalBE(vesta_fr* dst, const byte src[], ptrdiff_t src_len);
void        ctt_vesta_fr_marshalBE(byte dst[], ptrdiff_t dst_len, const vesta_fr* src);
secret_bool ctt_vesta_fr_is_eq(const vesta_fr* a, const vesta_fr* b);
secret_bool ctt_vesta_fr_is_zero(const vesta_fr* a);
secret_bool ctt_vesta_fr_is_one(const vesta_fr* a);
secret_bool ctt_vesta_fr_is_minus_one(const vesta_fr* a);
void        ctt_vesta_fr_set_zero(vesta_fr* a);
void        ctt_vesta_fr_set_one(vesta_fr* a);
void        ctt_vesta_fr_set_minus_one(vesta_fr* a);
void        ctt_vesta_fr_neg(vesta_fr* a);
void        ctt_vesta_fr_sum(vesta_fr* r, const vesta_fr* a, const vesta_fr* b);
void        ctt_vesta_fr_add_in_place(vesta_fr* a, const vesta_fr* b);
void        ctt_vesta_fr_diff(vesta_fr* r, const vesta_fr* a, const vesta_fr* b);
void        ctt_vesta_fr_sub_in_place(vesta_fr* a, const vesta_fr* b);
void        ctt_vesta_fr_double(vesta_fr* r, const vesta_fr* a);
void        ctt_vesta_fr_double_in_place(vesta_fr* a);
void        ctt_vesta_fr_prod(vesta_fr* r, const vesta_fr* a, const vesta_fr* b);
void        ctt_vesta_fr_mul_in_place(vesta_fr* a, const vesta_fr* b);
void        ctt_vesta_fr_square(vesta_fr* r, const vesta_fr* a);
void        ctt_vesta_fr_square_in_place(vesta_fr* a);
void        ctt_vesta_fr_div2(vesta_fr* a);
void        ctt_vesta_fr_inv(vesta_fr* r, const vesta_fr* a);
void        ctt_vesta_fr_inv_in_place(vesta_fr* a);
void        ctt_vesta_fr_csetZero(vesta_fr* a, const secret_bool ctl);
void        ctt_vesta_fr_csetOne(vesta_fr* a, const secret_bool ctl);
void        ctt_vesta_fr_cneg_in_place(vesta_fr* a, const secret_bool ctl);
void        ctt_vesta_fr_cadd_in_place(vesta_fr* a, const vesta_fr* b, const secret_bool ctl);
void        ctt_vesta_fr_csub_in_place(vesta_fr* a, const vesta_fr* b, const secret_bool ctl);

void        ctt_vesta_fp_unmarshalBE(vesta_fp* dst, const byte src[], ptrdiff_t src_len);
void        ctt_vesta_fp_marshalBE(byte dst[], ptrdiff_t dst_len, const vesta_fp* src);
secret_bool ctt_vesta_fp_is_eq(const vesta_fp* a, const vesta_fp* b);
secret_bool ctt_vesta_fp_is_zero(const vesta_fp* a);
secret_bool ctt_vesta_fp_is_one(const vesta_fp* a);
secret_bool ctt_vesta_fp_is_minus_one(const vesta_fp* a);
void        ctt_vesta_fp_set_zero(vesta_fp* a);
void        ctt_vesta_fp_set_one(vesta_fp* a);
void        ctt_vesta_fp_set_minus_one(vesta_fp* a);
void        ctt_vesta_fp_neg(vesta_fp* a);
void        ctt_vesta_fp_sum(vesta_fp* r, const vesta_fp* a, const vesta_fp* b);
void        ctt_vesta_fp_add_in_place(vesta_fp* a, const vesta_fp* b);
void        ctt_vesta_fp_diff(vesta_fp* r, const vesta_fp* a, const vesta_fp* b);
void        ctt_vesta_fp_sub_in_place(vesta_fp* a, const vesta_fp* b);
void        ctt_vesta_fp_double(vesta_fp* r, const vesta_fp* a);
void        ctt_vesta_fp_double_in_place(vesta_fp* a);
void        ctt_vesta_fp_prod(vesta_fp* r, const vesta_fp* a, const vesta_fp* b);
void        ctt_vesta_fp_mul_in_place(vesta_fp* a, const vesta_fp* b);
void        ctt_vesta_fp_square(vesta_fp* r, const vesta_fp* a);
void        ctt_vesta_fp_square_in_place(vesta_fp* a);
void        ctt_vesta_fp_div2(vesta_fp* a);
void        ctt_vesta_fp_inv(vesta_fp* r, const vesta_fp* a);
void        ctt_vesta_fp_inv_in_place(vesta_fp* a);
void        ctt_vesta_fp_csetZero(vesta_fp* a, const secret_bool ctl);
void        ctt_vesta_fp_csetOne(vesta_fp* a, const secret_bool ctl);
void        ctt_vesta_fp_cneg_in_place(vesta_fp* a, const secret_bool ctl);
void        ctt_vesta_fp_cadd_in_place(vesta_fp* a, const vesta_fp* b, const secret_bool ctl);
void        ctt_vesta_fp_csub_in_place(vesta_fp* a, const vesta_fp* b, const secret_bool ctl);

secret_bool ctt_vesta_fp_is_square(const vesta_fp* a);
void        ctt_vesta_fp_invsqrt(vesta_fp* r, const vesta_fp* a);
secret_bool ctt_vesta_fp_invsqrt_in_place(vesta_fp* r, const vesta_fp* a);
void        ctt_vesta_fp_sqrt_in_place(vesta_fp* a);
secret_bool ctt_vesta_fp_sqrt_if_square_in_place(vesta_fp* a);
void        ctt_vesta_fp_sqrt_invsqrt(vesta_fp* sqrt, vesta_fp* invsqrt, const vesta_fp* a);
secret_bool ctt_vesta_fp_sqrt_invsqrt_if_square(vesta_fp* sqrt, vesta_fp* invsqrt, const vesta_fp* a);
secret_bool ctt_vesta_fp_sqrt_ratio_if_square(vesta_fp* r, const vesta_fp* u, const vesta_fp* v);

secret_bool ctt_pallas_ec_aff_is_eq(const pallas_ec_aff* P, const pallas_ec_aff* Q);
secret_bool ctt_pallas_ec_aff_is_inf(const pallas_ec_aff* P);
void        ctt_pallas_ec_aff_set_inf(pallas_ec_aff* P);
void        ctt_pallas_ec_aff_ccopy(pallas_ec_aff* P, const pallas_ec_aff* Q, const secret_bool ctl);
secret_bool ctt_pallas_ec_aff_is_on_curve(const pallas_fp* x, const pallas_fp* y);
void        ctt_pallas_ec_aff_neg(pallas_ec_aff* P, const pallas_ec_aff* Q);
void        ctt_pallas_ec_aff_neg_in_place(pallas_ec_aff* P);

secret_bool ctt_vesta_ec_aff_is_eq(const vesta_ec_aff* P, const vesta_ec_aff* Q);
secret_bool ctt_vesta_ec_aff_is_inf(const vesta_ec_aff* P);
void        ctt_vesta_ec_aff_set_inf(vesta_ec_aff* P);
void        ctt_vesta_ec_aff_ccopy(vesta_ec_aff* P, const vesta_ec_aff* Q, const secret_bool ctl);
secret_bool ctt_vesta_ec_aff_is_on_curve(const pallas_fp* x, const pallas_fp* y);
void        ctt_vesta_ec_aff_neg(vesta_ec_aff* P, const vesta_ec_aff* Q);
void        ctt_vesta_ec_aff_neg_in_place(vesta_ec_aff* P);

/*
 * Initializes the library:
 * - the Nim runtime if heap-allocated types are used,
 *   this is the case only if Constantine is multithreaded.
 * - runtime CPU features detection
 */
void ctt_pasta_NimMain(void);


#ifdef __cplusplus
}
#endif


#endif
