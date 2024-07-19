/** Constantine
 *  Copyright (c) 2018-2019    Status Research & Development GmbH
 *  Copyright (c) 2020-Present Mamy André-Ratsimbazafy
 *  Licensed and distributed under either of
 *    * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
 *    * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
 *  at your option. This file may not be copied, modified, or distributed except according to those terms.
 */
#ifndef __CTT_H_BLS12_381__
#define __CTT_H_BLS12_381__

#include "constantine/core/datatypes.h"
#include "constantine/curves/bigints.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef struct { secret_word limbs[CTT_WORDS_REQUIRED(255)]; } bls12_381_fr;
typedef struct { secret_word limbs[CTT_WORDS_REQUIRED(381)]; } bls12_381_fp;
typedef struct { bls12_381_fp c[2]; } bls12_381_fp2;
typedef struct { bls12_381_fp x, y; } bls12_381_g1_aff;
typedef struct { bls12_381_fp x, y, z; } bls12_381_g1_jac;
typedef struct { bls12_381_fp x, y, z; } bls12_381_g1_prj;
typedef struct { bls12_381_fp2 x, y; } bls12_381_g2_aff;
typedef struct { bls12_381_fp2 x, y, z; } bls12_381_g2_jac;
typedef struct { bls12_381_fp2 x, y, z; } bls12_381_g2_prj;

void        ctt_big255_from_bls12_381_fr(big255* dst, const bls12_381_fr* src);
void        ctt_bls12_381_fr_from_big255(bls12_381_fr* dst, const big255* src);
ctt_bool    ctt_bls12_381_fr_unmarshalBE(bls12_381_fr* dst, const byte src[], size_t src_len) __attribute__((warn_unused_result));
ctt_bool    ctt_bls12_381_fr_marshalBE(byte dst[], size_t dst_len, const bls12_381_fr* src) __attribute__((warn_unused_result));
secret_bool ctt_bls12_381_fr_is_eq(const bls12_381_fr* a, const bls12_381_fr* b);
secret_bool ctt_bls12_381_fr_is_zero(const bls12_381_fr* a);
secret_bool ctt_bls12_381_fr_is_one(const bls12_381_fr* a);
secret_bool ctt_bls12_381_fr_is_minus_one(const bls12_381_fr* a);
void        ctt_bls12_381_fr_set_zero(bls12_381_fr* a);
void        ctt_bls12_381_fr_set_one(bls12_381_fr* a);
void        ctt_bls12_381_fr_set_minus_one(bls12_381_fr* a);
void        ctt_bls12_381_fr_neg(bls12_381_fr* r, const bls12_381_fr* a);
void        ctt_bls12_381_fr_neg_in_place(bls12_381_fr* a);
void        ctt_bls12_381_fr_sum(bls12_381_fr* r, const bls12_381_fr* a, const bls12_381_fr* b);
void        ctt_bls12_381_fr_add_in_place(bls12_381_fr* a, const bls12_381_fr* b);
void        ctt_bls12_381_fr_diff(bls12_381_fr* r, const bls12_381_fr* a, const bls12_381_fr* b);
void        ctt_bls12_381_fr_sub_in_place(bls12_381_fr* a, const bls12_381_fr* b);
void        ctt_bls12_381_fr_double(bls12_381_fr* r, const bls12_381_fr* a);
void        ctt_bls12_381_fr_double_in_place(bls12_381_fr* a);
void        ctt_bls12_381_fr_prod(bls12_381_fr* r, const bls12_381_fr* a, const bls12_381_fr* b);
void        ctt_bls12_381_fr_mul_in_place(bls12_381_fr* a, const bls12_381_fr* b);
void        ctt_bls12_381_fr_square(bls12_381_fr* r, const bls12_381_fr* a);
void        ctt_bls12_381_fr_square_in_place(bls12_381_fr* a);
void        ctt_bls12_381_fr_div2(bls12_381_fr* a);
void        ctt_bls12_381_fr_inv(bls12_381_fr* r, const bls12_381_fr* a);
void        ctt_bls12_381_fr_inv_in_place(bls12_381_fr* a);
void        ctt_bls12_381_fr_ccopy(bls12_381_fr* a, const bls12_381_fr* b, secret_bool ctl);
void        ctt_bls12_381_fr_cswap(bls12_381_fr* a, bls12_381_fr* b, secret_bool ctl);
void        ctt_bls12_381_fr_cset_zero(bls12_381_fr* a, secret_bool ctl);
void        ctt_bls12_381_fr_cset_one(bls12_381_fr* a, secret_bool ctl);
void        ctt_bls12_381_fr_cneg_in_place(bls12_381_fr* a, secret_bool ctl);
void        ctt_bls12_381_fr_cadd_in_place(bls12_381_fr* a, const bls12_381_fr* b, secret_bool ctl);
void        ctt_bls12_381_fr_csub_in_place(bls12_381_fr* a, const bls12_381_fr* b, secret_bool ctl);
void        ctt_big381_from_bls12_381_fp(big381* dst, const bls12_381_fp* src);
void        ctt_bls12_381_fp_from_big381(bls12_381_fp* dst, const big381* src);
ctt_bool    ctt_bls12_381_fp_unmarshalBE(bls12_381_fp* dst, const byte src[], size_t src_len) __attribute__((warn_unused_result));
ctt_bool    ctt_bls12_381_fp_marshalBE(byte dst[], size_t dst_len, const bls12_381_fp* src) __attribute__((warn_unused_result));
secret_bool ctt_bls12_381_fp_is_eq(const bls12_381_fp* a, const bls12_381_fp* b);
secret_bool ctt_bls12_381_fp_is_zero(const bls12_381_fp* a);
secret_bool ctt_bls12_381_fp_is_one(const bls12_381_fp* a);
secret_bool ctt_bls12_381_fp_is_minus_one(const bls12_381_fp* a);
void        ctt_bls12_381_fp_set_zero(bls12_381_fp* a);
void        ctt_bls12_381_fp_set_one(bls12_381_fp* a);
void        ctt_bls12_381_fp_set_minus_one(bls12_381_fp* a);
void        ctt_bls12_381_fp_neg(bls12_381_fp* r, const bls12_381_fp* a);
void        ctt_bls12_381_fp_neg_in_place(bls12_381_fp* a);
void        ctt_bls12_381_fp_sum(bls12_381_fp* r, const bls12_381_fp* a, const bls12_381_fp* b);
void        ctt_bls12_381_fp_add_in_place(bls12_381_fp* a, const bls12_381_fp* b);
void        ctt_bls12_381_fp_diff(bls12_381_fp* r, const bls12_381_fp* a, const bls12_381_fp* b);
void        ctt_bls12_381_fp_sub_in_place(bls12_381_fp* a, const bls12_381_fp* b);
void        ctt_bls12_381_fp_double(bls12_381_fp* r, const bls12_381_fp* a);
void        ctt_bls12_381_fp_double_in_place(bls12_381_fp* a);
void        ctt_bls12_381_fp_prod(bls12_381_fp* r, const bls12_381_fp* a, const bls12_381_fp* b);
void        ctt_bls12_381_fp_mul_in_place(bls12_381_fp* a, const bls12_381_fp* b);
void        ctt_bls12_381_fp_square(bls12_381_fp* r, const bls12_381_fp* a);
void        ctt_bls12_381_fp_square_in_place(bls12_381_fp* a);
void        ctt_bls12_381_fp_div2(bls12_381_fp* a);
void        ctt_bls12_381_fp_inv(bls12_381_fp* r, const bls12_381_fp* a);
void        ctt_bls12_381_fp_inv_in_place(bls12_381_fp* a);
void        ctt_bls12_381_fp_ccopy(bls12_381_fp* a, const bls12_381_fp* b, secret_bool ctl);
void        ctt_bls12_381_fp_cswap(bls12_381_fp* a, bls12_381_fp* b, secret_bool ctl);
void        ctt_bls12_381_fp_cset_zero(bls12_381_fp* a, secret_bool ctl);
void        ctt_bls12_381_fp_cset_one(bls12_381_fp* a, secret_bool ctl);
void        ctt_bls12_381_fp_cneg_in_place(bls12_381_fp* a, secret_bool ctl);
void        ctt_bls12_381_fp_cadd_in_place(bls12_381_fp* a, const bls12_381_fp* b, secret_bool ctl);
void        ctt_bls12_381_fp_csub_in_place(bls12_381_fp* a, const bls12_381_fp* b, secret_bool ctl);
secret_bool ctt_bls12_381_fp_is_square(const bls12_381_fp* a);
void        ctt_bls12_381_fp_invsqrt(bls12_381_fp* r, const bls12_381_fp* a);
secret_bool ctt_bls12_381_fp_invsqrt_in_place(bls12_381_fp* r, const bls12_381_fp* a);
void        ctt_bls12_381_fp_sqrt_in_place(bls12_381_fp* a);
secret_bool ctt_bls12_381_fp_sqrt_if_square_in_place(bls12_381_fp* a);
void        ctt_bls12_381_fp_sqrt_invsqrt(bls12_381_fp* sqrt, bls12_381_fp* invsqrt, const bls12_381_fp* a);
secret_bool ctt_bls12_381_fp_sqrt_invsqrt_if_square(bls12_381_fp* sqrt, bls12_381_fp* invsqrt, const bls12_381_fp* a);
secret_bool ctt_bls12_381_fp_sqrt_ratio_if_square(bls12_381_fp* r, const bls12_381_fp* u, const bls12_381_fp* v);
secret_bool ctt_bls12_381_fp2_is_eq(const bls12_381_fp2* a, const bls12_381_fp2* b);
secret_bool ctt_bls12_381_fp2_is_zero(const bls12_381_fp2* a);
secret_bool ctt_bls12_381_fp2_is_one(const bls12_381_fp2* a);
secret_bool ctt_bls12_381_fp2_is_minus_one(const bls12_381_fp2* a);
void        ctt_bls12_381_fp2_set_zero(bls12_381_fp2* a);
void        ctt_bls12_381_fp2_set_one(bls12_381_fp2* a);
void        ctt_bls12_381_fp2_set_minus_one(bls12_381_fp2* a);
void        ctt_bls12_381_fp2_neg(bls12_381_fp2* a);
void        ctt_bls12_381_fp2_sum(bls12_381_fp2* r, const bls12_381_fp2* a, const bls12_381_fp2* b);
void        ctt_bls12_381_fp2_add_in_place(bls12_381_fp2* a, const bls12_381_fp2* b);
void        ctt_bls12_381_fp2_diff(bls12_381_fp2* r, const bls12_381_fp2* a, const bls12_381_fp2* b);
void        ctt_bls12_381_fp2_sub_in_place(bls12_381_fp2* a, const bls12_381_fp2* b);
void        ctt_bls12_381_fp2_double(bls12_381_fp2* r, const bls12_381_fp2* a);
void        ctt_bls12_381_fp2_double_in_place(bls12_381_fp2* a);
void        ctt_bls12_381_fp2_conj(bls12_381_fp2* r, const bls12_381_fp2* a);
void        ctt_bls12_381_fp2_conj_in_place(bls12_381_fp2* a);
void        ctt_bls12_381_fp2_conjneg(bls12_381_fp2* r, const bls12_381_fp2* a);
void        ctt_bls12_381_fp2_conjneg_in_place(bls12_381_fp2* a);
void        ctt_bls12_381_fp2_prod(bls12_381_fp2* r, const bls12_381_fp2* a, const bls12_381_fp2* b);
void        ctt_bls12_381_fp2_mul_in_place(bls12_381_fp2* a, const bls12_381_fp2* b);
void        ctt_bls12_381_fp2_square(bls12_381_fp2* r, const bls12_381_fp2* a);
void        ctt_bls12_381_fp2_square_in_place(bls12_381_fp2* a);
void        ctt_bls12_381_fp2_div2(bls12_381_fp2* a);
void        ctt_bls12_381_fp2_inv(bls12_381_fp2* r, const bls12_381_fp2* a);
void        ctt_bls12_381_fp2_inv_in_place(bls12_381_fp2* a);
void        ctt_bls12_381_fp2_ccopy(bls12_381_fp2* a, const bls12_381_fp2* b, secret_bool ctl);
void        ctt_bls12_381_fp2_cset_zero(bls12_381_fp2* a, secret_bool ctl);
void        ctt_bls12_381_fp2_cset_one(bls12_381_fp2* a, secret_bool ctl);
void        ctt_bls12_381_fp2_cneg_in_place(bls12_381_fp2* a, secret_bool ctl);
void        ctt_bls12_381_fp2_cadd_in_place(bls12_381_fp2* a, const bls12_381_fp2* b, secret_bool ctl);
void        ctt_bls12_381_fp2_csub_in_place(bls12_381_fp2* a, const bls12_381_fp2* b, secret_bool ctl);
secret_bool ctt_bls12_381_fp2_is_square(const bls12_381_fp2* a);
void        ctt_bls12_381_fp2_sqrt_in_place(bls12_381_fp2* a);
secret_bool ctt_bls12_381_fp2_sqrt_if_square_in_place(bls12_381_fp2* a);
secret_bool ctt_bls12_381_g1_aff_is_eq(const bls12_381_g1_aff* P, const bls12_381_g1_aff* Q);
secret_bool ctt_bls12_381_g1_aff_is_neutral(const bls12_381_g1_aff* P);
void        ctt_bls12_381_g1_aff_set_neutral(bls12_381_g1_aff* P);
void        ctt_bls12_381_g1_aff_ccopy(bls12_381_g1_aff* P, const bls12_381_g1_aff* Q, secret_bool ctl);
secret_bool ctt_bls12_381_g1_aff_is_on_curve(const bls12_381_fp* x, const bls12_381_fp* y);
void        ctt_bls12_381_g1_aff_neg(bls12_381_g1_aff* P, const bls12_381_g1_aff* Q);
void        ctt_bls12_381_g1_aff_neg_in_place(bls12_381_g1_aff* P);
secret_bool ctt_bls12_381_g1_jac_is_eq(const bls12_381_g1_jac* P, const bls12_381_g1_jac* Q);
secret_bool ctt_bls12_381_g1_jac_is_neutral(const bls12_381_g1_jac* P);
void        ctt_bls12_381_g1_jac_set_neutral(bls12_381_g1_jac* P);
void        ctt_bls12_381_g1_jac_ccopy(bls12_381_g1_jac* P, const bls12_381_g1_jac* Q, secret_bool ctl);
void        ctt_bls12_381_g1_jac_neg(bls12_381_g1_jac* P, const bls12_381_g1_jac* Q);
void        ctt_bls12_381_g1_jac_neg_in_place(bls12_381_g1_jac* P);
void        ctt_bls12_381_g1_jac_cneg_in_place(bls12_381_g1_jac* P, secret_bool ctl);
void        ctt_bls12_381_g1_jac_sum(bls12_381_g1_jac* r, const bls12_381_g1_jac* P, const bls12_381_g1_jac* Q);
void        ctt_bls12_381_g1_jac_add_in_place(bls12_381_g1_jac* P, const bls12_381_g1_jac* Q);
void        ctt_bls12_381_g1_jac_diff(bls12_381_g1_jac* r, const bls12_381_g1_jac* P, const bls12_381_g1_jac* Q);
void        ctt_bls12_381_g1_jac_double(bls12_381_g1_jac* r, const bls12_381_g1_jac* P);
void        ctt_bls12_381_g1_jac_double_in_place(bls12_381_g1_jac* P);
void        ctt_bls12_381_g1_jac_affine(bls12_381_g1_aff* dst, const bls12_381_g1_jac* src);
void        ctt_bls12_381_g1_jac_from_affine(bls12_381_g1_jac* dst, const bls12_381_g1_aff* src);
void        ctt_bls12_381_g1_jac_batch_affine(const bls12_381_g1_aff dst[], const bls12_381_g1_jac src[], size_t n);
void        ctt_bls12_381_g1_jac_scalar_mul_big_coef(bls12_381_g1_jac* P, const big255* scalar);
void        ctt_bls12_381_g1_jac_scalar_mul_fr_coef(bls12_381_g1_jac* P, const bls12_381_fr* scalar);
void        ctt_bls12_381_g1_jac_scalar_mul_big_coef_vartime(bls12_381_g1_jac* P, const big255* scalar);
void        ctt_bls12_381_g1_jac_scalar_mul_fr_coef_vartime(bls12_381_g1_jac* P, const bls12_381_fr* scalar);
void        ctt_bls12_381_g1_jac_multi_scalar_mul_big_coefs_vartime(bls12_381_g1_jac* r, const big255 coefs[], const bls12_381_g1_aff points[], size_t len);
void        ctt_bls12_381_g1_jac_multi_scalar_mul_fr_coefs_vartime(bls12_381_g1_jac* r, const bls12_381_fr coefs[], const bls12_381_g1_aff points[], size_t len);
secret_bool ctt_bls12_381_g1_prj_is_eq(const bls12_381_g1_prj* P, const bls12_381_g1_prj* Q);
secret_bool ctt_bls12_381_g1_prj_is_neutral(const bls12_381_g1_prj* P);
void        ctt_bls12_381_g1_prj_set_neutral(bls12_381_g1_prj* P);
void        ctt_bls12_381_g1_prj_ccopy(bls12_381_g1_prj* P, const bls12_381_g1_prj* Q, secret_bool ctl);
void        ctt_bls12_381_g1_prj_neg(bls12_381_g1_prj* P, const bls12_381_g1_prj* Q);
void        ctt_bls12_381_g1_prj_neg_in_place(bls12_381_g1_prj* P);
void        ctt_bls12_381_g1_prj_cneg_in_place(bls12_381_g1_prj* P, secret_bool ctl);
void        ctt_bls12_381_g1_prj_sum(bls12_381_g1_prj* r, const bls12_381_g1_prj* P, const bls12_381_g1_prj* Q);
void        ctt_bls12_381_g1_prj_add_in_place(bls12_381_g1_prj* P, const bls12_381_g1_prj* Q);
void        ctt_bls12_381_g1_prj_diff(bls12_381_g1_prj* r, const bls12_381_g1_prj* P, const bls12_381_g1_prj* Q);
void        ctt_bls12_381_g1_prj_double(bls12_381_g1_prj* r, const bls12_381_g1_prj* P);
void        ctt_bls12_381_g1_prj_double_in_place(bls12_381_g1_prj* P);
void        ctt_bls12_381_g1_prj_affine(bls12_381_g1_aff* dst, const bls12_381_g1_prj* src);
void        ctt_bls12_381_g1_prj_from_affine(bls12_381_g1_prj* dst, const bls12_381_g1_aff* src);
void        ctt_bls12_381_g1_prj_batch_affine(const bls12_381_g1_aff dst[], const bls12_381_g1_prj src[], size_t n);
void        ctt_bls12_381_g1_prj_scalar_mul_big_coef(bls12_381_g1_prj* P, const big255* scalar);
void        ctt_bls12_381_g1_prj_scalar_mul_fr_coef(bls12_381_g1_prj* P, const bls12_381_fr* scalar);
void        ctt_bls12_381_g1_prj_scalar_mul_big_coef_vartime(bls12_381_g1_prj* P, const big255* scalar);
void        ctt_bls12_381_g1_prj_scalar_mul_fr_coef_vartime(bls12_381_g1_prj* P, const bls12_381_fr* scalar);
void        ctt_bls12_381_g1_prj_multi_scalar_mul_big_coefs_vartime(bls12_381_g1_prj* r, const big255 coefs[], const bls12_381_g1_aff points[], size_t len);
void        ctt_bls12_381_g1_prj_multi_scalar_mul_fr_coefs_vartime(bls12_381_g1_prj* r, const bls12_381_fr coefs[], const bls12_381_g1_aff points[], size_t len);
secret_bool ctt_bls12_381_g2_aff_is_eq(const bls12_381_g2_aff* P, const bls12_381_g2_aff* Q);
secret_bool ctt_bls12_381_g2_aff_is_neutral(const bls12_381_g2_aff* P);
void        ctt_bls12_381_g2_aff_set_neutral(bls12_381_g2_aff* P);
void        ctt_bls12_381_g2_aff_ccopy(bls12_381_g2_aff* P, const bls12_381_g2_aff* Q, secret_bool ctl);
secret_bool ctt_bls12_381_g2_aff_is_on_curve(const bls12_381_fp2* x, const bls12_381_fp2* y);
void        ctt_bls12_381_g2_aff_neg(bls12_381_g2_aff* P, const bls12_381_g2_aff* Q);
void        ctt_bls12_381_g2_aff_neg_in_place(bls12_381_g2_aff* P);
secret_bool ctt_bls12_381_g2_jac_is_eq(const bls12_381_g2_jac* P, const bls12_381_g2_jac* Q);
secret_bool ctt_bls12_381_g2_jac_is_neutral(const bls12_381_g2_jac* P);
void        ctt_bls12_381_g2_jac_set_neutral(bls12_381_g2_jac* P);
void        ctt_bls12_381_g2_jac_ccopy(bls12_381_g2_jac* P, const bls12_381_g2_jac* Q, secret_bool ctl);
void        ctt_bls12_381_g2_jac_neg(bls12_381_g2_jac* P, const bls12_381_g2_jac* Q);
void        ctt_bls12_381_g2_jac_neg_in_place(bls12_381_g2_jac* P);
void        ctt_bls12_381_g2_jac_cneg_in_place(bls12_381_g2_jac* P, secret_bool ctl);
void        ctt_bls12_381_g2_jac_sum(bls12_381_g2_jac* r, const bls12_381_g2_jac* P, const bls12_381_g2_jac* Q);
void        ctt_bls12_381_g2_jac_add_in_place(bls12_381_g2_jac* P, const bls12_381_g2_jac* Q);
void        ctt_bls12_381_g2_jac_diff(bls12_381_g2_jac* r, const bls12_381_g2_jac* P, const bls12_381_g2_jac* Q);
void        ctt_bls12_381_g2_jac_double(bls12_381_g2_jac* r, const bls12_381_g2_jac* P);
void        ctt_bls12_381_g2_jac_double_in_place(bls12_381_g2_jac* P);
void        ctt_bls12_381_g2_jac_affine(bls12_381_g2_aff* dst, const bls12_381_g2_jac* src);
void        ctt_bls12_381_g2_jac_from_affine(bls12_381_g2_jac* dst, const bls12_381_g2_aff* src);
void        ctt_bls12_381_g2_jac_batch_affine(const bls12_381_g2_aff dst[], const bls12_381_g2_jac src[], size_t n);
void        ctt_bls12_381_g2_jac_scalar_mul_big_coef(bls12_381_g2_jac* P, const big255* scalar);
void        ctt_bls12_381_g2_jac_scalar_mul_fr_coef(bls12_381_g2_jac* P, const bls12_381_fr* scalar);
void        ctt_bls12_381_g2_jac_scalar_mul_big_coef_vartime(bls12_381_g2_jac* P, const big255* scalar);
void        ctt_bls12_381_g2_jac_scalar_mul_fr_coef_vartime(bls12_381_g2_jac* P, const bls12_381_fr* scalar);
void        ctt_bls12_381_g2_jac_multi_scalar_mul_big_coefs_vartime(bls12_381_g2_jac* r, const big255 coefs[], const bls12_381_g2_aff points[], size_t len);
void        ctt_bls12_381_g2_jac_multi_scalar_mul_fr_coefs_vartime(bls12_381_g2_jac* r, const bls12_381_fr coefs[], const bls12_381_g2_aff points[], size_t len);
secret_bool ctt_bls12_381_g2_prj_is_eq(const bls12_381_g2_prj* P, const bls12_381_g2_prj* Q);
secret_bool ctt_bls12_381_g2_prj_is_neutral(const bls12_381_g2_prj* P);
void        ctt_bls12_381_g2_prj_set_neutral(bls12_381_g2_prj* P);
void        ctt_bls12_381_g2_prj_ccopy(bls12_381_g2_prj* P, const bls12_381_g2_prj* Q, secret_bool ctl);
void        ctt_bls12_381_g2_prj_neg(bls12_381_g2_prj* P, const bls12_381_g2_prj* Q);
void        ctt_bls12_381_g2_prj_neg_in_place(bls12_381_g2_prj* P);
void        ctt_bls12_381_g2_prj_cneg_in_place(bls12_381_g2_prj* P, secret_bool ctl);
void        ctt_bls12_381_g2_prj_sum(bls12_381_g2_prj* r, const bls12_381_g2_prj* P, const bls12_381_g2_prj* Q);
void        ctt_bls12_381_g2_prj_add_in_place(bls12_381_g2_prj* P, const bls12_381_g2_prj* Q);
void        ctt_bls12_381_g2_prj_diff(bls12_381_g2_prj* r, const bls12_381_g2_prj* P, const bls12_381_g2_prj* Q);
void        ctt_bls12_381_g2_prj_double(bls12_381_g2_prj* r, const bls12_381_g2_prj* P);
void        ctt_bls12_381_g2_prj_double_in_place(bls12_381_g2_prj* P);
void        ctt_bls12_381_g2_prj_affine(bls12_381_g2_aff* dst, const bls12_381_g2_prj* src);
void        ctt_bls12_381_g2_prj_from_affine(bls12_381_g2_prj* dst, const bls12_381_g2_aff* src);
void        ctt_bls12_381_g2_prj_batch_affine(const bls12_381_g2_aff dst[], const bls12_381_g2_prj src[], size_t n);
void        ctt_bls12_381_g2_prj_scalar_mul_big_coef(bls12_381_g2_prj* P, const big255* scalar);
void        ctt_bls12_381_g2_prj_scalar_mul_fr_coef(bls12_381_g2_prj* P, const bls12_381_fr* scalar);
void        ctt_bls12_381_g2_prj_scalar_mul_big_coef_vartime(bls12_381_g2_prj* P, const big255* scalar);
void        ctt_bls12_381_g2_prj_scalar_mul_fr_coef_vartime(bls12_381_g2_prj* P, const bls12_381_fr* scalar);
void        ctt_bls12_381_g2_prj_multi_scalar_mul_big_coefs_vartime(bls12_381_g2_prj* r, const big255 coefs[], const bls12_381_g2_aff points[], size_t len);
void        ctt_bls12_381_g2_prj_multi_scalar_mul_fr_coefs_vartime(bls12_381_g2_prj* r, const bls12_381_fr coefs[], const bls12_381_g2_aff points[], size_t len);
void        ctt_bls12_381_g1_aff_sswu_sha256(bls12_381_g1_aff* r, const byte augmentation[], size_t augmentation_len, const byte message[], size_t message_len, const byte domainSepTag[], size_t domainSepTag_len);
void        ctt_bls12_381_g1_jac_sswu_sha256(bls12_381_g1_jac* r, const byte augmentation[], size_t augmentation_len, const byte message[], size_t message_len, const byte domainSepTag[], size_t domainSepTag_len);
void        ctt_bls12_381_g1_prj_sswu_sha256(bls12_381_g1_prj* r, const byte augmentation[], size_t augmentation_len, const byte message[], size_t message_len, const byte domainSepTag[], size_t domainSepTag_len);
void        ctt_bls12_381_g2_aff_sswu_sha256(bls12_381_g2_aff* r, const byte augmentation[], size_t augmentation_len, const byte message[], size_t message_len, const byte domainSepTag[], size_t domainSepTag_len);
void        ctt_bls12_381_g2_jac_sswu_sha256(bls12_381_g2_jac* r, const byte augmentation[], size_t augmentation_len, const byte message[], size_t message_len, const byte domainSepTag[], size_t domainSepTag_len);
void        ctt_bls12_381_g2_prj_sswu_sha256(bls12_381_g2_prj* r, const byte augmentation[], size_t augmentation_len, const byte message[], size_t message_len, const byte domainSepTag[], size_t domainSepTag_len);

#ifdef __cplusplus
}
#endif

#endif // __CTT_H_BLS12_381__
