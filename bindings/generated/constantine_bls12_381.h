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
void        ctt_bls12381_fr_neg(bls12381_fr* r, const bls12381_fr* a);
void        ctt_bls12381_fr_neg_in_place(bls12381_fr* a);
void        ctt_bls12381_fr_sum(bls12381_fr* r, const bls12381_fr* a, const bls12381_fr* b);
void        ctt_bls12381_fr_add_in_place(bls12381_fr* a, const bls12381_fr* b);
void        ctt_bls12381_fr_diff(bls12381_fr* r, const bls12381_fr* a, const bls12381_fr* b);
void        ctt_bls12381_fr_sub_in_place(bls12381_fr* a, const bls12381_fr* b);
void        ctt_bls12381_fr_double(bls12381_fr* r, const bls12381_fr* a);
void        ctt_bls12381_fr_double_in_place(bls12381_fr* a);
void        ctt_bls12381_fr_prod(bls12381_fr* r, const bls12381_fr* a, const bls12381_fr* b);
void        ctt_bls12381_fr_mul_in_place(bls12381_fr* a, const bls12381_fr* b);
void        ctt_bls12381_fr_square(bls12381_fr* r, const bls12381_fr* a);
void        ctt_bls12381_fr_square_in_place(bls12381_fr* a);
void        ctt_bls12381_fr_div2(bls12381_fr* a);
void        ctt_bls12381_fr_inv(bls12381_fr* r, const bls12381_fr* a);
void        ctt_bls12381_fr_inv_in_place(bls12381_fr* a);
void        ctt_bls12381_fr_ccopy(bls12381_fr* a, const bls12381_fr* b, const secret_bool ctl);
void        ctt_bls12381_fr_cswap(bls12381_fr* a, bls12381_fr* b, const secret_bool ctl);
void        ctt_bls12381_fr_cset_zero(bls12381_fr* a, const secret_bool ctl);
void        ctt_bls12381_fr_cset_one(bls12381_fr* a, const secret_bool ctl);
void        ctt_bls12381_fr_cneg_in_place(bls12381_fr* a, const secret_bool ctl);
void        ctt_bls12381_fr_cadd_in_place(bls12381_fr* a, const bls12381_fr* b, const secret_bool ctl);
void        ctt_bls12381_fr_csub_in_place(bls12381_fr* a, const bls12381_fr* b, const secret_bool ctl);

void        ctt_bls12381_fp_unmarshalBE(bls12381_fp* dst, const byte src[], ptrdiff_t src_len);
void        ctt_bls12381_fp_marshalBE(byte dst[], ptrdiff_t dst_len, const bls12381_fp* src);
secret_bool ctt_bls12381_fp_is_eq(const bls12381_fp* a, const bls12381_fp* b);
secret_bool ctt_bls12381_fp_is_zero(const bls12381_fp* a);
secret_bool ctt_bls12381_fp_is_one(const bls12381_fp* a);
secret_bool ctt_bls12381_fp_is_minus_one(const bls12381_fp* a);
void        ctt_bls12381_fp_set_zero(bls12381_fp* a);
void        ctt_bls12381_fp_set_one(bls12381_fp* a);
void        ctt_bls12381_fp_set_minus_one(bls12381_fp* a);
void        ctt_bls12381_fp_neg(bls12381_fp* r, const bls12381_fp* a);
void        ctt_bls12381_fp_neg_in_place(bls12381_fp* a);
void        ctt_bls12381_fp_sum(bls12381_fp* r, const bls12381_fp* a, const bls12381_fp* b);
void        ctt_bls12381_fp_add_in_place(bls12381_fp* a, const bls12381_fp* b);
void        ctt_bls12381_fp_diff(bls12381_fp* r, const bls12381_fp* a, const bls12381_fp* b);
void        ctt_bls12381_fp_sub_in_place(bls12381_fp* a, const bls12381_fp* b);
void        ctt_bls12381_fp_double(bls12381_fp* r, const bls12381_fp* a);
void        ctt_bls12381_fp_double_in_place(bls12381_fp* a);
void        ctt_bls12381_fp_prod(bls12381_fp* r, const bls12381_fp* a, const bls12381_fp* b);
void        ctt_bls12381_fp_mul_in_place(bls12381_fp* a, const bls12381_fp* b);
void        ctt_bls12381_fp_square(bls12381_fp* r, const bls12381_fp* a);
void        ctt_bls12381_fp_square_in_place(bls12381_fp* a);
void        ctt_bls12381_fp_div2(bls12381_fp* a);
void        ctt_bls12381_fp_inv(bls12381_fp* r, const bls12381_fp* a);
void        ctt_bls12381_fp_inv_in_place(bls12381_fp* a);
void        ctt_bls12381_fp_ccopy(bls12381_fp* a, const bls12381_fp* b, const secret_bool ctl);
void        ctt_bls12381_fp_cswap(bls12381_fp* a, bls12381_fp* b, const secret_bool ctl);
void        ctt_bls12381_fp_cset_zero(bls12381_fp* a, const secret_bool ctl);
void        ctt_bls12381_fp_cset_one(bls12381_fp* a, const secret_bool ctl);
void        ctt_bls12381_fp_cneg_in_place(bls12381_fp* a, const secret_bool ctl);
void        ctt_bls12381_fp_cadd_in_place(bls12381_fp* a, const bls12381_fp* b, const secret_bool ctl);
void        ctt_bls12381_fp_csub_in_place(bls12381_fp* a, const bls12381_fp* b, const secret_bool ctl);

secret_bool ctt_bls12381_fp_is_square(const bls12381_fp* a);
void        ctt_bls12381_fp_invsqrt(bls12381_fp* r, const bls12381_fp* a);
secret_bool ctt_bls12381_fp_invsqrt_in_place(bls12381_fp* r, const bls12381_fp* a);
void        ctt_bls12381_fp_sqrt_in_place(bls12381_fp* a);
secret_bool ctt_bls12381_fp_sqrt_if_square_in_place(bls12381_fp* a);
void        ctt_bls12381_fp_sqrt_invsqrt(bls12381_fp* sqrt, bls12381_fp* invsqrt, const bls12381_fp* a);
secret_bool ctt_bls12381_fp_sqrt_invsqrt_if_square(bls12381_fp* sqrt, bls12381_fp* invsqrt, const bls12381_fp* a);
secret_bool ctt_bls12381_fp_sqrt_ratio_if_square(bls12381_fp* r, const bls12381_fp* u, const bls12381_fp* v);

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
void        ctt_bls12381_fp2_conj(bls12381_fp2* r, const bls12381_fp2* a);
void        ctt_bls12381_fp2_conj_in_place(bls12381_fp2* a);
void        ctt_bls12381_fp2_conjneg(bls12381_fp2* r, const bls12381_fp2* a);
void        ctt_bls12381_fp2_conjneg_in_place(bls12381_fp2* a);
void        ctt_bls12381_fp2_prod(bls12381_fp2* r, const bls12381_fp2* a, const bls12381_fp2* b);
void        ctt_bls12381_fp2_mul_in_place(bls12381_fp2* a, const bls12381_fp2* b);
void        ctt_bls12381_fp2_square(bls12381_fp2* r, const bls12381_fp2* a);
void        ctt_bls12381_fp2_square_in_place(bls12381_fp2* a);
void        ctt_bls12381_fp2_div2(bls12381_fp2* a);
void        ctt_bls12381_fp2_inv(bls12381_fp2* r, const bls12381_fp2* a);
void        ctt_bls12381_fp2_inv_in_place(bls12381_fp2* a);
void        ctt_bls12381_fp2_ccopy(bls12381_fp2* a, const bls12381_fp2* b, const secret_bool ctl);
void        ctt_bls12381_fp2_cset_zero(bls12381_fp2* a, const secret_bool ctl);
void        ctt_bls12381_fp2_cset_one(bls12381_fp2* a, const secret_bool ctl);
void        ctt_bls12381_fp2_cneg_in_place(bls12381_fp2* a, const secret_bool ctl);
void        ctt_bls12381_fp2_cadd_in_place(bls12381_fp2* a, const bls12381_fp2* b, const secret_bool ctl);
void        ctt_bls12381_fp2_csub_in_place(bls12381_fp2* a, const bls12381_fp2* b, const secret_bool ctl);

secret_bool ctt_bls12381_fp2_is_square(const bls12381_fp2* a);
void        ctt_bls12381_fp2_sqrt_in_place(bls12381_fp2* a);
secret_bool ctt_bls12381_fp2_sqrt_if_square_in_place(bls12381_fp2* a);

secret_bool ctt_bls12381_ec_g1_aff_is_eq(const bls12381_ec_g1_aff* P, const bls12381_ec_g1_aff* Q);
secret_bool ctt_bls12381_ec_g1_aff_is_inf(const bls12381_ec_g1_aff* P);
void        ctt_bls12381_ec_g1_aff_set_inf(bls12381_ec_g1_aff* P);
void        ctt_bls12381_ec_g1_aff_ccopy(bls12381_ec_g1_aff* P, const bls12381_ec_g1_aff* Q, const secret_bool ctl);
secret_bool ctt_bls12381_ec_g1_aff_is_on_curve(const bls12381_fp* x, const bls12381_fp* y);
void        ctt_bls12381_ec_g1_aff_neg(bls12381_ec_g1_aff* P, const bls12381_ec_g1_aff* Q);
void        ctt_bls12381_ec_g1_aff_neg_in_place(bls12381_ec_g1_aff* P);

secret_bool ctt_bls12381_ec_g1_jac_is_eq(const bls12381_ec_g1_jac* P, const bls12381_ec_g1_jac* Q);
secret_bool ctt_bls12381_ec_g1_jac_is_inf(const bls12381_ec_g1_jac* P);
void        ctt_bls12381_ec_g1_jac_set_inf(bls12381_ec_g1_jac* P);
void        ctt_bls12381_ec_g1_jac_ccopy(bls12381_ec_g1_jac* P, const bls12381_ec_g1_jac* Q, const secret_bool ctl);
void        ctt_bls12381_ec_g1_jac_neg(bls12381_ec_g1_jac* P, const bls12381_ec_g1_jac* Q);
void        ctt_bls12381_ec_g1_jac_neg_in_place(bls12381_ec_g1_jac* P);
void        ctt_bls12381_ec_g1_jac_cneg_in_place(bls12381_ec_g1_jac* P, const secret_bool ctl);
void        ctt_bls12381_ec_g1_jac_sum(bls12381_ec_g1_jac* r, const bls12381_ec_g1_jac* P, const bls12381_ec_g1_jac* Q);
void        ctt_bls12381_ec_g1_jac_add_in_place(bls12381_ec_g1_jac* P, const bls12381_ec_g1_jac* Q);
void        ctt_bls12381_ec_g1_jac_diff(bls12381_ec_g1_jac* r, const bls12381_ec_g1_jac* P, const bls12381_ec_g1_jac* Q);
void        ctt_bls12381_ec_g1_jac_double(bls12381_ec_g1_jac* r, const bls12381_ec_g1_jac* P);
void        ctt_bls12381_ec_g1_jac_double_in_place(bls12381_ec_g1_jac* P);
void        ctt_bls12381_ec_g1_jac_affine(bls12381_ec_g1_aff* dst, const bls12381_ec_g1_jac* src);
void        ctt_bls12381_ec_g1_jac_from_affine(bls12381_ec_g1_jac* dst, const bls12381_ec_g1_aff* src);

secret_bool ctt_bls12381_ec_g1_prj_is_eq(const bls12381_ec_g1_prj* P, const bls12381_ec_g1_prj* Q);
secret_bool ctt_bls12381_ec_g1_prj_is_inf(const bls12381_ec_g1_prj* P);
void        ctt_bls12381_ec_g1_prj_set_inf(bls12381_ec_g1_prj* P);
void        ctt_bls12381_ec_g1_prj_ccopy(bls12381_ec_g1_prj* P, const bls12381_ec_g1_prj* Q, const secret_bool ctl);
void        ctt_bls12381_ec_g1_prj_neg(bls12381_ec_g1_prj* P, const bls12381_ec_g1_prj* Q);
void        ctt_bls12381_ec_g1_prj_neg_in_place(bls12381_ec_g1_prj* P);
void        ctt_bls12381_ec_g1_prj_cneg_in_place(bls12381_ec_g1_prj* P, const secret_bool ctl);
void        ctt_bls12381_ec_g1_prj_sum(bls12381_ec_g1_prj* r, const bls12381_ec_g1_prj* P, const bls12381_ec_g1_prj* Q);
void        ctt_bls12381_ec_g1_prj_add_in_place(bls12381_ec_g1_prj* P, const bls12381_ec_g1_prj* Q);
void        ctt_bls12381_ec_g1_prj_diff(bls12381_ec_g1_prj* r, const bls12381_ec_g1_prj* P, const bls12381_ec_g1_prj* Q);
void        ctt_bls12381_ec_g1_prj_double(bls12381_ec_g1_prj* r, const bls12381_ec_g1_prj* P);
void        ctt_bls12381_ec_g1_prj_double_in_place(bls12381_ec_g1_prj* P);
void        ctt_bls12381_ec_g1_prj_affine(bls12381_ec_g1_aff* dst, const bls12381_ec_g1_prj* src);
void        ctt_bls12381_ec_g1_prj_from_affine(bls12381_ec_g1_prj* dst, const bls12381_ec_g1_aff* src);

secret_bool ctt_bls12381_ec_g2_aff_is_eq(const bls12381_ec_g2_aff* P, const bls12381_ec_g2_aff* Q);
secret_bool ctt_bls12381_ec_g2_aff_is_inf(const bls12381_ec_g2_aff* P);
void        ctt_bls12381_ec_g2_aff_set_inf(bls12381_ec_g2_aff* P);
void        ctt_bls12381_ec_g2_aff_ccopy(bls12381_ec_g2_aff* P, const bls12381_ec_g2_aff* Q, const secret_bool ctl);
secret_bool ctt_bls12381_ec_g2_aff_is_on_curve(const bls12381_fp2* x, const bls12381_fp2* y);
void        ctt_bls12381_ec_g2_aff_neg(bls12381_ec_g2_aff* P, const bls12381_ec_g2_aff* Q);
void        ctt_bls12381_ec_g2_aff_neg_in_place(bls12381_ec_g2_aff* P);

secret_bool ctt_bls12381_ec_g2_jac_is_eq(const bls12381_ec_g2_jac* P, const bls12381_ec_g2_jac* Q);
secret_bool ctt_bls12381_ec_g2_jac_is_inf(const bls12381_ec_g2_jac* P);
void        ctt_bls12381_ec_g2_jac_set_inf(bls12381_ec_g2_jac* P);
void        ctt_bls12381_ec_g2_jac_ccopy(bls12381_ec_g2_jac* P, const bls12381_ec_g2_jac* Q, const secret_bool ctl);
void        ctt_bls12381_ec_g2_jac_neg(bls12381_ec_g2_jac* P, const bls12381_ec_g2_jac* Q);
void        ctt_bls12381_ec_g2_jac_neg_in_place(bls12381_ec_g2_jac* P);
void        ctt_bls12381_ec_g2_jac_cneg_in_place(bls12381_ec_g2_jac* P, const secret_bool ctl);
void        ctt_bls12381_ec_g2_jac_sum(bls12381_ec_g2_jac* r, const bls12381_ec_g2_jac* P, const bls12381_ec_g2_jac* Q);
void        ctt_bls12381_ec_g2_jac_add_in_place(bls12381_ec_g2_jac* P, const bls12381_ec_g2_jac* Q);
void        ctt_bls12381_ec_g2_jac_diff(bls12381_ec_g2_jac* r, const bls12381_ec_g2_jac* P, const bls12381_ec_g2_jac* Q);
void        ctt_bls12381_ec_g2_jac_double(bls12381_ec_g2_jac* r, const bls12381_ec_g2_jac* P);
void        ctt_bls12381_ec_g2_jac_double_in_place(bls12381_ec_g2_jac* P);
void        ctt_bls12381_ec_g2_jac_affine(bls12381_ec_g2_aff* dst, const bls12381_ec_g2_jac* src);
void        ctt_bls12381_ec_g2_jac_from_affine(bls12381_ec_g2_jac* dst, const bls12381_ec_g2_aff* src);

secret_bool ctt_bls12381_ec_g2_prj_is_eq(const bls12381_ec_g2_prj* P, const bls12381_ec_g2_prj* Q);
secret_bool ctt_bls12381_ec_g2_prj_is_inf(const bls12381_ec_g2_prj* P);
void        ctt_bls12381_ec_g2_prj_set_inf(bls12381_ec_g2_prj* P);
void        ctt_bls12381_ec_g2_prj_ccopy(bls12381_ec_g2_prj* P, const bls12381_ec_g2_prj* Q, const secret_bool ctl);
void        ctt_bls12381_ec_g2_prj_neg(bls12381_ec_g2_prj* P, const bls12381_ec_g2_prj* Q);
void        ctt_bls12381_ec_g2_prj_neg_in_place(bls12381_ec_g2_prj* P);
void        ctt_bls12381_ec_g2_prj_cneg_in_place(bls12381_ec_g2_prj* P, const secret_bool ctl);
void        ctt_bls12381_ec_g2_prj_sum(bls12381_ec_g2_prj* r, const bls12381_ec_g2_prj* P, const bls12381_ec_g2_prj* Q);
void        ctt_bls12381_ec_g2_prj_add_in_place(bls12381_ec_g2_prj* P, const bls12381_ec_g2_prj* Q);
void        ctt_bls12381_ec_g2_prj_diff(bls12381_ec_g2_prj* r, const bls12381_ec_g2_prj* P, const bls12381_ec_g2_prj* Q);
void        ctt_bls12381_ec_g2_prj_double(bls12381_ec_g2_prj* r, const bls12381_ec_g2_prj* P);
void        ctt_bls12381_ec_g2_prj_double_in_place(bls12381_ec_g2_prj* P);
void        ctt_bls12381_ec_g2_prj_affine(bls12381_ec_g2_aff* dst, const bls12381_ec_g2_prj* src);
void        ctt_bls12381_ec_g2_prj_from_affine(bls12381_ec_g2_prj* dst, const bls12381_ec_g2_aff* src);

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
