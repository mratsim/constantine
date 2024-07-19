/** Constantine
 *  Copyright (c) 2018-2019    Status Research & Development GmbH
 *  Copyright (c) 2020-Present Mamy André-Ratsimbazafy
 *  Licensed and distributed under either of
 *    * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
 *    * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
 *  at your option. This file may not be copied, modified, or distributed except according to those terms.
 */
#ifndef __CTT_H_BN254_SNARKS__
#define __CTT_H_BN254_SNARKS__

#include "constantine/core/datatypes.h"
#include "constantine/curves/bigints.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef struct { secret_word limbs[CTT_WORDS_REQUIRED(254)]; } bn254_snarks_fr;
typedef struct { secret_word limbs[CTT_WORDS_REQUIRED(254)]; } bn254_snarks_fp;
typedef struct { bn254_snarks_fp c[2]; } bn254_snarks_fp2;
typedef struct { bn254_snarks_fp x, y; } bn254_snarks_g1_aff;
typedef struct { bn254_snarks_fp x, y, z; } bn254_snarks_g1_jac;
typedef struct { bn254_snarks_fp x, y, z; } bn254_snarks_g1_prj;
typedef struct { bn254_snarks_fp2 x, y; } bn254_snarks_g2_aff;
typedef struct { bn254_snarks_fp2 x, y, z; } bn254_snarks_g2_jac;
typedef struct { bn254_snarks_fp2 x, y, z; } bn254_snarks_g2_prj;

void        ctt_big254_from_bn254_snarks_fr(big254* dst, const bn254_snarks_fr* src);
void        ctt_bn254_snarks_fr_from_big254(bn254_snarks_fr* dst, const big254* src);
ctt_bool    ctt_bn254_snarks_fr_unmarshalBE(bn254_snarks_fr* dst, const byte src[], size_t src_len) __attribute__((warn_unused_result));
ctt_bool    ctt_bn254_snarks_fr_marshalBE(byte dst[], size_t dst_len, const bn254_snarks_fr* src) __attribute__((warn_unused_result));
secret_bool ctt_bn254_snarks_fr_is_eq(const bn254_snarks_fr* a, const bn254_snarks_fr* b);
secret_bool ctt_bn254_snarks_fr_is_zero(const bn254_snarks_fr* a);
secret_bool ctt_bn254_snarks_fr_is_one(const bn254_snarks_fr* a);
secret_bool ctt_bn254_snarks_fr_is_minus_one(const bn254_snarks_fr* a);
void        ctt_bn254_snarks_fr_set_zero(bn254_snarks_fr* a);
void        ctt_bn254_snarks_fr_set_one(bn254_snarks_fr* a);
void        ctt_bn254_snarks_fr_set_minus_one(bn254_snarks_fr* a);
void        ctt_bn254_snarks_fr_neg(bn254_snarks_fr* r, const bn254_snarks_fr* a);
void        ctt_bn254_snarks_fr_neg_in_place(bn254_snarks_fr* a);
void        ctt_bn254_snarks_fr_sum(bn254_snarks_fr* r, const bn254_snarks_fr* a, const bn254_snarks_fr* b);
void        ctt_bn254_snarks_fr_add_in_place(bn254_snarks_fr* a, const bn254_snarks_fr* b);
void        ctt_bn254_snarks_fr_diff(bn254_snarks_fr* r, const bn254_snarks_fr* a, const bn254_snarks_fr* b);
void        ctt_bn254_snarks_fr_sub_in_place(bn254_snarks_fr* a, const bn254_snarks_fr* b);
void        ctt_bn254_snarks_fr_double(bn254_snarks_fr* r, const bn254_snarks_fr* a);
void        ctt_bn254_snarks_fr_double_in_place(bn254_snarks_fr* a);
void        ctt_bn254_snarks_fr_prod(bn254_snarks_fr* r, const bn254_snarks_fr* a, const bn254_snarks_fr* b);
void        ctt_bn254_snarks_fr_mul_in_place(bn254_snarks_fr* a, const bn254_snarks_fr* b);
void        ctt_bn254_snarks_fr_square(bn254_snarks_fr* r, const bn254_snarks_fr* a);
void        ctt_bn254_snarks_fr_square_in_place(bn254_snarks_fr* a);
void        ctt_bn254_snarks_fr_div2(bn254_snarks_fr* a);
void        ctt_bn254_snarks_fr_inv(bn254_snarks_fr* r, const bn254_snarks_fr* a);
void        ctt_bn254_snarks_fr_inv_in_place(bn254_snarks_fr* a);
void        ctt_bn254_snarks_fr_ccopy(bn254_snarks_fr* a, const bn254_snarks_fr* b, secret_bool ctl);
void        ctt_bn254_snarks_fr_cswap(bn254_snarks_fr* a, bn254_snarks_fr* b, secret_bool ctl);
void        ctt_bn254_snarks_fr_cset_zero(bn254_snarks_fr* a, secret_bool ctl);
void        ctt_bn254_snarks_fr_cset_one(bn254_snarks_fr* a, secret_bool ctl);
void        ctt_bn254_snarks_fr_cneg_in_place(bn254_snarks_fr* a, secret_bool ctl);
void        ctt_bn254_snarks_fr_cadd_in_place(bn254_snarks_fr* a, const bn254_snarks_fr* b, secret_bool ctl);
void        ctt_bn254_snarks_fr_csub_in_place(bn254_snarks_fr* a, const bn254_snarks_fr* b, secret_bool ctl);
void        ctt_big254_from_bn254_snarks_fp(big254* dst, const bn254_snarks_fp* src);
void        ctt_bn254_snarks_fp_from_big254(bn254_snarks_fp* dst, const big254* src);
ctt_bool    ctt_bn254_snarks_fp_unmarshalBE(bn254_snarks_fp* dst, const byte src[], size_t src_len) __attribute__((warn_unused_result));
ctt_bool    ctt_bn254_snarks_fp_marshalBE(byte dst[], size_t dst_len, const bn254_snarks_fp* src) __attribute__((warn_unused_result));
secret_bool ctt_bn254_snarks_fp_is_eq(const bn254_snarks_fp* a, const bn254_snarks_fp* b);
secret_bool ctt_bn254_snarks_fp_is_zero(const bn254_snarks_fp* a);
secret_bool ctt_bn254_snarks_fp_is_one(const bn254_snarks_fp* a);
secret_bool ctt_bn254_snarks_fp_is_minus_one(const bn254_snarks_fp* a);
void        ctt_bn254_snarks_fp_set_zero(bn254_snarks_fp* a);
void        ctt_bn254_snarks_fp_set_one(bn254_snarks_fp* a);
void        ctt_bn254_snarks_fp_set_minus_one(bn254_snarks_fp* a);
void        ctt_bn254_snarks_fp_neg(bn254_snarks_fp* r, const bn254_snarks_fp* a);
void        ctt_bn254_snarks_fp_neg_in_place(bn254_snarks_fp* a);
void        ctt_bn254_snarks_fp_sum(bn254_snarks_fp* r, const bn254_snarks_fp* a, const bn254_snarks_fp* b);
void        ctt_bn254_snarks_fp_add_in_place(bn254_snarks_fp* a, const bn254_snarks_fp* b);
void        ctt_bn254_snarks_fp_diff(bn254_snarks_fp* r, const bn254_snarks_fp* a, const bn254_snarks_fp* b);
void        ctt_bn254_snarks_fp_sub_in_place(bn254_snarks_fp* a, const bn254_snarks_fp* b);
void        ctt_bn254_snarks_fp_double(bn254_snarks_fp* r, const bn254_snarks_fp* a);
void        ctt_bn254_snarks_fp_double_in_place(bn254_snarks_fp* a);
void        ctt_bn254_snarks_fp_prod(bn254_snarks_fp* r, const bn254_snarks_fp* a, const bn254_snarks_fp* b);
void        ctt_bn254_snarks_fp_mul_in_place(bn254_snarks_fp* a, const bn254_snarks_fp* b);
void        ctt_bn254_snarks_fp_square(bn254_snarks_fp* r, const bn254_snarks_fp* a);
void        ctt_bn254_snarks_fp_square_in_place(bn254_snarks_fp* a);
void        ctt_bn254_snarks_fp_div2(bn254_snarks_fp* a);
void        ctt_bn254_snarks_fp_inv(bn254_snarks_fp* r, const bn254_snarks_fp* a);
void        ctt_bn254_snarks_fp_inv_in_place(bn254_snarks_fp* a);
void        ctt_bn254_snarks_fp_ccopy(bn254_snarks_fp* a, const bn254_snarks_fp* b, secret_bool ctl);
void        ctt_bn254_snarks_fp_cswap(bn254_snarks_fp* a, bn254_snarks_fp* b, secret_bool ctl);
void        ctt_bn254_snarks_fp_cset_zero(bn254_snarks_fp* a, secret_bool ctl);
void        ctt_bn254_snarks_fp_cset_one(bn254_snarks_fp* a, secret_bool ctl);
void        ctt_bn254_snarks_fp_cneg_in_place(bn254_snarks_fp* a, secret_bool ctl);
void        ctt_bn254_snarks_fp_cadd_in_place(bn254_snarks_fp* a, const bn254_snarks_fp* b, secret_bool ctl);
void        ctt_bn254_snarks_fp_csub_in_place(bn254_snarks_fp* a, const bn254_snarks_fp* b, secret_bool ctl);
secret_bool ctt_bn254_snarks_fp_is_square(const bn254_snarks_fp* a);
void        ctt_bn254_snarks_fp_invsqrt(bn254_snarks_fp* r, const bn254_snarks_fp* a);
secret_bool ctt_bn254_snarks_fp_invsqrt_in_place(bn254_snarks_fp* r, const bn254_snarks_fp* a);
void        ctt_bn254_snarks_fp_sqrt_in_place(bn254_snarks_fp* a);
secret_bool ctt_bn254_snarks_fp_sqrt_if_square_in_place(bn254_snarks_fp* a);
void        ctt_bn254_snarks_fp_sqrt_invsqrt(bn254_snarks_fp* sqrt, bn254_snarks_fp* invsqrt, const bn254_snarks_fp* a);
secret_bool ctt_bn254_snarks_fp_sqrt_invsqrt_if_square(bn254_snarks_fp* sqrt, bn254_snarks_fp* invsqrt, const bn254_snarks_fp* a);
secret_bool ctt_bn254_snarks_fp_sqrt_ratio_if_square(bn254_snarks_fp* r, const bn254_snarks_fp* u, const bn254_snarks_fp* v);
secret_bool ctt_bn254_snarks_fp2_is_eq(const bn254_snarks_fp2* a, const bn254_snarks_fp2* b);
secret_bool ctt_bn254_snarks_fp2_is_zero(const bn254_snarks_fp2* a);
secret_bool ctt_bn254_snarks_fp2_is_one(const bn254_snarks_fp2* a);
secret_bool ctt_bn254_snarks_fp2_is_minus_one(const bn254_snarks_fp2* a);
void        ctt_bn254_snarks_fp2_set_zero(bn254_snarks_fp2* a);
void        ctt_bn254_snarks_fp2_set_one(bn254_snarks_fp2* a);
void        ctt_bn254_snarks_fp2_set_minus_one(bn254_snarks_fp2* a);
void        ctt_bn254_snarks_fp2_neg(bn254_snarks_fp2* a);
void        ctt_bn254_snarks_fp2_sum(bn254_snarks_fp2* r, const bn254_snarks_fp2* a, const bn254_snarks_fp2* b);
void        ctt_bn254_snarks_fp2_add_in_place(bn254_snarks_fp2* a, const bn254_snarks_fp2* b);
void        ctt_bn254_snarks_fp2_diff(bn254_snarks_fp2* r, const bn254_snarks_fp2* a, const bn254_snarks_fp2* b);
void        ctt_bn254_snarks_fp2_sub_in_place(bn254_snarks_fp2* a, const bn254_snarks_fp2* b);
void        ctt_bn254_snarks_fp2_double(bn254_snarks_fp2* r, const bn254_snarks_fp2* a);
void        ctt_bn254_snarks_fp2_double_in_place(bn254_snarks_fp2* a);
void        ctt_bn254_snarks_fp2_conj(bn254_snarks_fp2* r, const bn254_snarks_fp2* a);
void        ctt_bn254_snarks_fp2_conj_in_place(bn254_snarks_fp2* a);
void        ctt_bn254_snarks_fp2_conjneg(bn254_snarks_fp2* r, const bn254_snarks_fp2* a);
void        ctt_bn254_snarks_fp2_conjneg_in_place(bn254_snarks_fp2* a);
void        ctt_bn254_snarks_fp2_prod(bn254_snarks_fp2* r, const bn254_snarks_fp2* a, const bn254_snarks_fp2* b);
void        ctt_bn254_snarks_fp2_mul_in_place(bn254_snarks_fp2* a, const bn254_snarks_fp2* b);
void        ctt_bn254_snarks_fp2_square(bn254_snarks_fp2* r, const bn254_snarks_fp2* a);
void        ctt_bn254_snarks_fp2_square_in_place(bn254_snarks_fp2* a);
void        ctt_bn254_snarks_fp2_div2(bn254_snarks_fp2* a);
void        ctt_bn254_snarks_fp2_inv(bn254_snarks_fp2* r, const bn254_snarks_fp2* a);
void        ctt_bn254_snarks_fp2_inv_in_place(bn254_snarks_fp2* a);
void        ctt_bn254_snarks_fp2_ccopy(bn254_snarks_fp2* a, const bn254_snarks_fp2* b, secret_bool ctl);
void        ctt_bn254_snarks_fp2_cset_zero(bn254_snarks_fp2* a, secret_bool ctl);
void        ctt_bn254_snarks_fp2_cset_one(bn254_snarks_fp2* a, secret_bool ctl);
void        ctt_bn254_snarks_fp2_cneg_in_place(bn254_snarks_fp2* a, secret_bool ctl);
void        ctt_bn254_snarks_fp2_cadd_in_place(bn254_snarks_fp2* a, const bn254_snarks_fp2* b, secret_bool ctl);
void        ctt_bn254_snarks_fp2_csub_in_place(bn254_snarks_fp2* a, const bn254_snarks_fp2* b, secret_bool ctl);
secret_bool ctt_bn254_snarks_fp2_is_square(const bn254_snarks_fp2* a);
void        ctt_bn254_snarks_fp2_sqrt_in_place(bn254_snarks_fp2* a);
secret_bool ctt_bn254_snarks_fp2_sqrt_if_square_in_place(bn254_snarks_fp2* a);
secret_bool ctt_bn254_snarks_g1_aff_is_eq(const bn254_snarks_g1_aff* P, const bn254_snarks_g1_aff* Q);
secret_bool ctt_bn254_snarks_g1_aff_is_neutral(const bn254_snarks_g1_aff* P);
void        ctt_bn254_snarks_g1_aff_set_neutral(bn254_snarks_g1_aff* P);
void        ctt_bn254_snarks_g1_aff_ccopy(bn254_snarks_g1_aff* P, const bn254_snarks_g1_aff* Q, secret_bool ctl);
secret_bool ctt_bn254_snarks_g1_aff_is_on_curve(const bn254_snarks_fp* x, const bn254_snarks_fp* y);
void        ctt_bn254_snarks_g1_aff_neg(bn254_snarks_g1_aff* P, const bn254_snarks_g1_aff* Q);
void        ctt_bn254_snarks_g1_aff_neg_in_place(bn254_snarks_g1_aff* P);
secret_bool ctt_bn254_snarks_g1_jac_is_eq(const bn254_snarks_g1_jac* P, const bn254_snarks_g1_jac* Q);
secret_bool ctt_bn254_snarks_g1_jac_is_neutral(const bn254_snarks_g1_jac* P);
void        ctt_bn254_snarks_g1_jac_set_neutral(bn254_snarks_g1_jac* P);
void        ctt_bn254_snarks_g1_jac_ccopy(bn254_snarks_g1_jac* P, const bn254_snarks_g1_jac* Q, secret_bool ctl);
void        ctt_bn254_snarks_g1_jac_neg(bn254_snarks_g1_jac* P, const bn254_snarks_g1_jac* Q);
void        ctt_bn254_snarks_g1_jac_neg_in_place(bn254_snarks_g1_jac* P);
void        ctt_bn254_snarks_g1_jac_cneg_in_place(bn254_snarks_g1_jac* P, secret_bool ctl);
void        ctt_bn254_snarks_g1_jac_sum(bn254_snarks_g1_jac* r, const bn254_snarks_g1_jac* P, const bn254_snarks_g1_jac* Q);
void        ctt_bn254_snarks_g1_jac_add_in_place(bn254_snarks_g1_jac* P, const bn254_snarks_g1_jac* Q);
void        ctt_bn254_snarks_g1_jac_diff(bn254_snarks_g1_jac* r, const bn254_snarks_g1_jac* P, const bn254_snarks_g1_jac* Q);
void        ctt_bn254_snarks_g1_jac_double(bn254_snarks_g1_jac* r, const bn254_snarks_g1_jac* P);
void        ctt_bn254_snarks_g1_jac_double_in_place(bn254_snarks_g1_jac* P);
void        ctt_bn254_snarks_g1_jac_affine(bn254_snarks_g1_aff* dst, const bn254_snarks_g1_jac* src);
void        ctt_bn254_snarks_g1_jac_from_affine(bn254_snarks_g1_jac* dst, const bn254_snarks_g1_aff* src);
void        ctt_bn254_snarks_g1_jac_batch_affine(const bn254_snarks_g1_aff dst[], const bn254_snarks_g1_jac src[], size_t n);
void        ctt_bn254_snarks_g1_jac_scalar_mul_big_coef(bn254_snarks_g1_jac* P, const big254* scalar);
void        ctt_bn254_snarks_g1_jac_scalar_mul_fr_coef(bn254_snarks_g1_jac* P, const bn254_snarks_fr* scalar);
void        ctt_bn254_snarks_g1_jac_scalar_mul_big_coef_vartime(bn254_snarks_g1_jac* P, const big254* scalar);
void        ctt_bn254_snarks_g1_jac_scalar_mul_fr_coef_vartime(bn254_snarks_g1_jac* P, const bn254_snarks_fr* scalar);
void        ctt_bn254_snarks_g1_jac_multi_scalar_mul_big_coefs_vartime(bn254_snarks_g1_jac* r, const big254 coefs[], const bn254_snarks_g1_aff points[], size_t len);
void        ctt_bn254_snarks_g1_jac_multi_scalar_mul_fr_coefs_vartime(bn254_snarks_g1_jac* r, const bn254_snarks_fr coefs[], const bn254_snarks_g1_aff points[], size_t len);
secret_bool ctt_bn254_snarks_g1_prj_is_eq(const bn254_snarks_g1_prj* P, const bn254_snarks_g1_prj* Q);
secret_bool ctt_bn254_snarks_g1_prj_is_neutral(const bn254_snarks_g1_prj* P);
void        ctt_bn254_snarks_g1_prj_set_neutral(bn254_snarks_g1_prj* P);
void        ctt_bn254_snarks_g1_prj_ccopy(bn254_snarks_g1_prj* P, const bn254_snarks_g1_prj* Q, secret_bool ctl);
void        ctt_bn254_snarks_g1_prj_neg(bn254_snarks_g1_prj* P, const bn254_snarks_g1_prj* Q);
void        ctt_bn254_snarks_g1_prj_neg_in_place(bn254_snarks_g1_prj* P);
void        ctt_bn254_snarks_g1_prj_cneg_in_place(bn254_snarks_g1_prj* P, secret_bool ctl);
void        ctt_bn254_snarks_g1_prj_sum(bn254_snarks_g1_prj* r, const bn254_snarks_g1_prj* P, const bn254_snarks_g1_prj* Q);
void        ctt_bn254_snarks_g1_prj_add_in_place(bn254_snarks_g1_prj* P, const bn254_snarks_g1_prj* Q);
void        ctt_bn254_snarks_g1_prj_diff(bn254_snarks_g1_prj* r, const bn254_snarks_g1_prj* P, const bn254_snarks_g1_prj* Q);
void        ctt_bn254_snarks_g1_prj_double(bn254_snarks_g1_prj* r, const bn254_snarks_g1_prj* P);
void        ctt_bn254_snarks_g1_prj_double_in_place(bn254_snarks_g1_prj* P);
void        ctt_bn254_snarks_g1_prj_affine(bn254_snarks_g1_aff* dst, const bn254_snarks_g1_prj* src);
void        ctt_bn254_snarks_g1_prj_from_affine(bn254_snarks_g1_prj* dst, const bn254_snarks_g1_aff* src);
void        ctt_bn254_snarks_g1_prj_batch_affine(const bn254_snarks_g1_aff dst[], const bn254_snarks_g1_prj src[], size_t n);
void        ctt_bn254_snarks_g1_prj_scalar_mul_big_coef(bn254_snarks_g1_prj* P, const big254* scalar);
void        ctt_bn254_snarks_g1_prj_scalar_mul_fr_coef(bn254_snarks_g1_prj* P, const bn254_snarks_fr* scalar);
void        ctt_bn254_snarks_g1_prj_scalar_mul_big_coef_vartime(bn254_snarks_g1_prj* P, const big254* scalar);
void        ctt_bn254_snarks_g1_prj_scalar_mul_fr_coef_vartime(bn254_snarks_g1_prj* P, const bn254_snarks_fr* scalar);
void        ctt_bn254_snarks_g1_prj_multi_scalar_mul_big_coefs_vartime(bn254_snarks_g1_prj* r, const big254 coefs[], const bn254_snarks_g1_aff points[], size_t len);
void        ctt_bn254_snarks_g1_prj_multi_scalar_mul_fr_coefs_vartime(bn254_snarks_g1_prj* r, const bn254_snarks_fr coefs[], const bn254_snarks_g1_aff points[], size_t len);
secret_bool ctt_bn254_snarks_g2_aff_is_eq(const bn254_snarks_g2_aff* P, const bn254_snarks_g2_aff* Q);
secret_bool ctt_bn254_snarks_g2_aff_is_neutral(const bn254_snarks_g2_aff* P);
void        ctt_bn254_snarks_g2_aff_set_neutral(bn254_snarks_g2_aff* P);
void        ctt_bn254_snarks_g2_aff_ccopy(bn254_snarks_g2_aff* P, const bn254_snarks_g2_aff* Q, secret_bool ctl);
secret_bool ctt_bn254_snarks_g2_aff_is_on_curve(const bn254_snarks_fp2* x, const bn254_snarks_fp2* y);
void        ctt_bn254_snarks_g2_aff_neg(bn254_snarks_g2_aff* P, const bn254_snarks_g2_aff* Q);
void        ctt_bn254_snarks_g2_aff_neg_in_place(bn254_snarks_g2_aff* P);
secret_bool ctt_bn254_snarks_g2_jac_is_eq(const bn254_snarks_g2_jac* P, const bn254_snarks_g2_jac* Q);
secret_bool ctt_bn254_snarks_g2_jac_is_neutral(const bn254_snarks_g2_jac* P);
void        ctt_bn254_snarks_g2_jac_set_neutral(bn254_snarks_g2_jac* P);
void        ctt_bn254_snarks_g2_jac_ccopy(bn254_snarks_g2_jac* P, const bn254_snarks_g2_jac* Q, secret_bool ctl);
void        ctt_bn254_snarks_g2_jac_neg(bn254_snarks_g2_jac* P, const bn254_snarks_g2_jac* Q);
void        ctt_bn254_snarks_g2_jac_neg_in_place(bn254_snarks_g2_jac* P);
void        ctt_bn254_snarks_g2_jac_cneg_in_place(bn254_snarks_g2_jac* P, secret_bool ctl);
void        ctt_bn254_snarks_g2_jac_sum(bn254_snarks_g2_jac* r, const bn254_snarks_g2_jac* P, const bn254_snarks_g2_jac* Q);
void        ctt_bn254_snarks_g2_jac_add_in_place(bn254_snarks_g2_jac* P, const bn254_snarks_g2_jac* Q);
void        ctt_bn254_snarks_g2_jac_diff(bn254_snarks_g2_jac* r, const bn254_snarks_g2_jac* P, const bn254_snarks_g2_jac* Q);
void        ctt_bn254_snarks_g2_jac_double(bn254_snarks_g2_jac* r, const bn254_snarks_g2_jac* P);
void        ctt_bn254_snarks_g2_jac_double_in_place(bn254_snarks_g2_jac* P);
void        ctt_bn254_snarks_g2_jac_affine(bn254_snarks_g2_aff* dst, const bn254_snarks_g2_jac* src);
void        ctt_bn254_snarks_g2_jac_from_affine(bn254_snarks_g2_jac* dst, const bn254_snarks_g2_aff* src);
void        ctt_bn254_snarks_g2_jac_batch_affine(const bn254_snarks_g2_aff dst[], const bn254_snarks_g2_jac src[], size_t n);
void        ctt_bn254_snarks_g2_jac_scalar_mul_big_coef(bn254_snarks_g2_jac* P, const big254* scalar);
void        ctt_bn254_snarks_g2_jac_scalar_mul_fr_coef(bn254_snarks_g2_jac* P, const bn254_snarks_fr* scalar);
void        ctt_bn254_snarks_g2_jac_scalar_mul_big_coef_vartime(bn254_snarks_g2_jac* P, const big254* scalar);
void        ctt_bn254_snarks_g2_jac_scalar_mul_fr_coef_vartime(bn254_snarks_g2_jac* P, const bn254_snarks_fr* scalar);
void        ctt_bn254_snarks_g2_jac_multi_scalar_mul_big_coefs_vartime(bn254_snarks_g2_jac* r, const big254 coefs[], const bn254_snarks_g2_aff points[], size_t len);
void        ctt_bn254_snarks_g2_jac_multi_scalar_mul_fr_coefs_vartime(bn254_snarks_g2_jac* r, const bn254_snarks_fr coefs[], const bn254_snarks_g2_aff points[], size_t len);
secret_bool ctt_bn254_snarks_g2_prj_is_eq(const bn254_snarks_g2_prj* P, const bn254_snarks_g2_prj* Q);
secret_bool ctt_bn254_snarks_g2_prj_is_neutral(const bn254_snarks_g2_prj* P);
void        ctt_bn254_snarks_g2_prj_set_neutral(bn254_snarks_g2_prj* P);
void        ctt_bn254_snarks_g2_prj_ccopy(bn254_snarks_g2_prj* P, const bn254_snarks_g2_prj* Q, secret_bool ctl);
void        ctt_bn254_snarks_g2_prj_neg(bn254_snarks_g2_prj* P, const bn254_snarks_g2_prj* Q);
void        ctt_bn254_snarks_g2_prj_neg_in_place(bn254_snarks_g2_prj* P);
void        ctt_bn254_snarks_g2_prj_cneg_in_place(bn254_snarks_g2_prj* P, secret_bool ctl);
void        ctt_bn254_snarks_g2_prj_sum(bn254_snarks_g2_prj* r, const bn254_snarks_g2_prj* P, const bn254_snarks_g2_prj* Q);
void        ctt_bn254_snarks_g2_prj_add_in_place(bn254_snarks_g2_prj* P, const bn254_snarks_g2_prj* Q);
void        ctt_bn254_snarks_g2_prj_diff(bn254_snarks_g2_prj* r, const bn254_snarks_g2_prj* P, const bn254_snarks_g2_prj* Q);
void        ctt_bn254_snarks_g2_prj_double(bn254_snarks_g2_prj* r, const bn254_snarks_g2_prj* P);
void        ctt_bn254_snarks_g2_prj_double_in_place(bn254_snarks_g2_prj* P);
void        ctt_bn254_snarks_g2_prj_affine(bn254_snarks_g2_aff* dst, const bn254_snarks_g2_prj* src);
void        ctt_bn254_snarks_g2_prj_from_affine(bn254_snarks_g2_prj* dst, const bn254_snarks_g2_aff* src);
void        ctt_bn254_snarks_g2_prj_batch_affine(const bn254_snarks_g2_aff dst[], const bn254_snarks_g2_prj src[], size_t n);
void        ctt_bn254_snarks_g2_prj_scalar_mul_big_coef(bn254_snarks_g2_prj* P, const big254* scalar);
void        ctt_bn254_snarks_g2_prj_scalar_mul_fr_coef(bn254_snarks_g2_prj* P, const bn254_snarks_fr* scalar);
void        ctt_bn254_snarks_g2_prj_scalar_mul_big_coef_vartime(bn254_snarks_g2_prj* P, const big254* scalar);
void        ctt_bn254_snarks_g2_prj_scalar_mul_fr_coef_vartime(bn254_snarks_g2_prj* P, const bn254_snarks_fr* scalar);
void        ctt_bn254_snarks_g2_prj_multi_scalar_mul_big_coefs_vartime(bn254_snarks_g2_prj* r, const big254 coefs[], const bn254_snarks_g2_aff points[], size_t len);
void        ctt_bn254_snarks_g2_prj_multi_scalar_mul_fr_coefs_vartime(bn254_snarks_g2_prj* r, const bn254_snarks_fr coefs[], const bn254_snarks_g2_aff points[], size_t len);
void        ctt_bn254_snarks_g1_aff_svdw_sha256(bn254_snarks_g1_aff* r, const byte augmentation[], size_t augmentation_len, const byte message[], size_t message_len, const byte domainSepTag[], size_t domainSepTag_len);
void        ctt_bn254_snarks_g1_jac_svdw_sha256(bn254_snarks_g1_jac* r, const byte augmentation[], size_t augmentation_len, const byte message[], size_t message_len, const byte domainSepTag[], size_t domainSepTag_len);
void        ctt_bn254_snarks_g1_prj_svdw_sha256(bn254_snarks_g1_prj* r, const byte augmentation[], size_t augmentation_len, const byte message[], size_t message_len, const byte domainSepTag[], size_t domainSepTag_len);
void        ctt_bn254_snarks_g2_aff_svdw_sha256(bn254_snarks_g2_aff* r, const byte augmentation[], size_t augmentation_len, const byte message[], size_t message_len, const byte domainSepTag[], size_t domainSepTag_len);
void        ctt_bn254_snarks_g2_jac_svdw_sha256(bn254_snarks_g2_jac* r, const byte augmentation[], size_t augmentation_len, const byte message[], size_t message_len, const byte domainSepTag[], size_t domainSepTag_len);
void        ctt_bn254_snarks_g2_prj_svdw_sha256(bn254_snarks_g2_prj* r, const byte augmentation[], size_t augmentation_len, const byte message[], size_t message_len, const byte domainSepTag[], size_t domainSepTag_len);

#ifdef __cplusplus
}
#endif

#endif // __CTT_H_BN254_SNARKS__
