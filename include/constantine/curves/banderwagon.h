/** Constantine
 *  Copyright (c) 2018-2019    Status Research & Development GmbH
 *  Copyright (c) 2020-Present Mamy André-Ratsimbazafy
 *  Licensed and distributed under either of
 *    * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
 *    * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
 *  at your option. This file may not be copied, modified, or distributed except according to those terms.
 */
#ifndef __CTT_H_BANDERWAGON__
#define __CTT_H_BANDERWAGON__

#include "constantine/core/datatypes.h"
#include "constantine/curves/bigints.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef struct { secret_word limbs[CTT_WORDS_REQUIRED(253)]; } banderwagon_fr;
typedef struct { secret_word limbs[CTT_WORDS_REQUIRED(255)]; } banderwagon_fp;
typedef struct { banderwagon_fp x, y; } banderwagon_ec_aff;
typedef struct { banderwagon_fp x, y, z; } banderwagon_ec_prj;

void ctt_big253_from_banderwagon_fr(big253* dst, const banderwagon_fr* src);
void ctt_banderwagon_fr_from_big253(banderwagon_fr* dst, const big253* src);
ctt_bool ctt_banderwagon_fr_unmarshalBE(banderwagon_fr* dst, const byte src[], size_t src_len) __attribute__((warn_unused_result));
ctt_bool ctt_banderwagon_fr_marshalBE(byte dst[], size_t dst_len, const banderwagon_fr* src) __attribute__((warn_unused_result));
secret_bool ctt_banderwagon_fr_is_eq(const banderwagon_fr* a, const banderwagon_fr* b);
secret_bool ctt_banderwagon_fr_is_zero(const banderwagon_fr* a);
secret_bool ctt_banderwagon_fr_is_one(const banderwagon_fr* a);
secret_bool ctt_banderwagon_fr_is_minus_one(const banderwagon_fr* a);
void ctt_banderwagon_fr_set_zero(banderwagon_fr* a);
void ctt_banderwagon_fr_set_one(banderwagon_fr* a);
void ctt_banderwagon_fr_set_minus_one(banderwagon_fr* a);
void ctt_banderwagon_fr_neg(banderwagon_fr* r, const banderwagon_fr* a);
void ctt_banderwagon_fr_neg_in_place(banderwagon_fr* a);
void ctt_banderwagon_fr_sum(banderwagon_fr* r, const banderwagon_fr* a, const banderwagon_fr* b);
void ctt_banderwagon_fr_add_in_place(banderwagon_fr* a, const banderwagon_fr* b);
void ctt_banderwagon_fr_diff(banderwagon_fr* r, const banderwagon_fr* a, const banderwagon_fr* b);
void ctt_banderwagon_fr_sub_in_place(banderwagon_fr* a, const banderwagon_fr* b);
void ctt_banderwagon_fr_double(banderwagon_fr* r, const banderwagon_fr* a);
void ctt_banderwagon_fr_double_in_place(banderwagon_fr* a);
void ctt_banderwagon_fr_prod(banderwagon_fr* r, const banderwagon_fr* a, const banderwagon_fr* b);
void ctt_banderwagon_fr_mul_in_place(banderwagon_fr* a, const banderwagon_fr* b);
void ctt_banderwagon_fr_square(banderwagon_fr* r, const banderwagon_fr* a);
void ctt_banderwagon_fr_square_in_place(banderwagon_fr* a);
void ctt_banderwagon_fr_div2(banderwagon_fr* a);
void ctt_banderwagon_fr_inv(banderwagon_fr* r, const banderwagon_fr* a);
void ctt_banderwagon_fr_inv_in_place(banderwagon_fr* a);
void ctt_banderwagon_fr_ccopy(banderwagon_fr* a, const banderwagon_fr* b, secret_bool ctl);
void ctt_banderwagon_fr_cswap(banderwagon_fr* a, banderwagon_fr* b, secret_bool ctl);
void ctt_banderwagon_fr_cset_zero(banderwagon_fr* a, secret_bool ctl);
void ctt_banderwagon_fr_cset_one(banderwagon_fr* a, secret_bool ctl);
void ctt_banderwagon_fr_cneg_in_place(banderwagon_fr* a, secret_bool ctl);
void ctt_banderwagon_fr_cadd_in_place(banderwagon_fr* a, const banderwagon_fr* b, secret_bool ctl);
void ctt_banderwagon_fr_csub_in_place(banderwagon_fr* a, const banderwagon_fr* b, secret_bool ctl);
void ctt_big255_from_banderwagon_fp(big255* dst, const banderwagon_fp* src);
void ctt_banderwagon_fp_from_big255(banderwagon_fp* dst, const big255* src);
ctt_bool ctt_banderwagon_fp_unmarshalBE(banderwagon_fp* dst, const byte src[], size_t src_len) __attribute__((warn_unused_result));
ctt_bool ctt_banderwagon_fp_marshalBE(byte dst[], size_t dst_len, const banderwagon_fp* src) __attribute__((warn_unused_result));
secret_bool ctt_banderwagon_fp_is_eq(const banderwagon_fp* a, const banderwagon_fp* b);
secret_bool ctt_banderwagon_fp_is_zero(const banderwagon_fp* a);
secret_bool ctt_banderwagon_fp_is_one(const banderwagon_fp* a);
secret_bool ctt_banderwagon_fp_is_minus_one(const banderwagon_fp* a);
void ctt_banderwagon_fp_set_zero(banderwagon_fp* a);
void ctt_banderwagon_fp_set_one(banderwagon_fp* a);
void ctt_banderwagon_fp_set_minus_one(banderwagon_fp* a);
void ctt_banderwagon_fp_neg(banderwagon_fp* r, const banderwagon_fp* a);
void ctt_banderwagon_fp_neg_in_place(banderwagon_fp* a);
void ctt_banderwagon_fp_sum(banderwagon_fp* r, const banderwagon_fp* a, const banderwagon_fp* b);
void ctt_banderwagon_fp_add_in_place(banderwagon_fp* a, const banderwagon_fp* b);
void ctt_banderwagon_fp_diff(banderwagon_fp* r, const banderwagon_fp* a, const banderwagon_fp* b);
void ctt_banderwagon_fp_sub_in_place(banderwagon_fp* a, const banderwagon_fp* b);
void ctt_banderwagon_fp_double(banderwagon_fp* r, const banderwagon_fp* a);
void ctt_banderwagon_fp_double_in_place(banderwagon_fp* a);
void ctt_banderwagon_fp_prod(banderwagon_fp* r, const banderwagon_fp* a, const banderwagon_fp* b);
void ctt_banderwagon_fp_mul_in_place(banderwagon_fp* a, const banderwagon_fp* b);
void ctt_banderwagon_fp_square(banderwagon_fp* r, const banderwagon_fp* a);
void ctt_banderwagon_fp_square_in_place(banderwagon_fp* a);
void ctt_banderwagon_fp_div2(banderwagon_fp* a);
void ctt_banderwagon_fp_inv(banderwagon_fp* r, const banderwagon_fp* a);
void ctt_banderwagon_fp_inv_in_place(banderwagon_fp* a);
void ctt_banderwagon_fp_ccopy(banderwagon_fp* a, const banderwagon_fp* b, secret_bool ctl);
void ctt_banderwagon_fp_cswap(banderwagon_fp* a, banderwagon_fp* b, secret_bool ctl);
void ctt_banderwagon_fp_cset_zero(banderwagon_fp* a, secret_bool ctl);
void ctt_banderwagon_fp_cset_one(banderwagon_fp* a, secret_bool ctl);
void ctt_banderwagon_fp_cneg_in_place(banderwagon_fp* a, secret_bool ctl);
void ctt_banderwagon_fp_cadd_in_place(banderwagon_fp* a, const banderwagon_fp* b, secret_bool ctl);
void ctt_banderwagon_fp_csub_in_place(banderwagon_fp* a, const banderwagon_fp* b, secret_bool ctl);
secret_bool ctt_banderwagon_fp_is_square(const banderwagon_fp* a);
void ctt_banderwagon_fp_invsqrt(banderwagon_fp* r, const banderwagon_fp* a);
secret_bool ctt_banderwagon_fp_invsqrt_in_place(banderwagon_fp* r, const banderwagon_fp* a);
void ctt_banderwagon_fp_sqrt_in_place(banderwagon_fp* a);
secret_bool ctt_banderwagon_fp_sqrt_if_square_in_place(banderwagon_fp* a);
void ctt_banderwagon_fp_sqrt_invsqrt(banderwagon_fp* sqrt, banderwagon_fp* invsqrt, const banderwagon_fp* a);
secret_bool ctt_banderwagon_fp_sqrt_invsqrt_if_square(banderwagon_fp* sqrt, banderwagon_fp* invsqrt, const banderwagon_fp* a);
secret_bool ctt_banderwagon_fp_sqrt_ratio_if_square(banderwagon_fp* r, const banderwagon_fp* u, const banderwagon_fp* v);
secret_bool ctt_banderwagon_ec_aff_is_eq(const banderwagon_ec_aff* P, const banderwagon_ec_aff* Q);
secret_bool ctt_banderwagon_ec_aff_is_neutral(const banderwagon_ec_aff* P);
void ctt_banderwagon_ec_aff_set_neutral(banderwagon_ec_aff* P);
void ctt_banderwagon_ec_aff_ccopy(banderwagon_ec_aff* dst, const banderwagon_ec_aff* src, secret_bool ctl);
secret_bool ctt_banderwagon_ec_aff_is_on_curve(const banderwagon_fp* x, const banderwagon_fp* y);
void ctt_banderwagon_ec_neg(banderwagon_ec_aff* P, const banderwagon_ec_aff* Q);
void ctt_banderwagon_ec_neg_in_place(banderwagon_ec_aff* P);
void ctt_banderwagon_ec_cneg(banderwagon_ec_aff* P, const secret_bool ctl);
secret_bool ctt_banderwagon_ec_prj_is_eq(const banderwagon_ec_prj* P, const banderwagon_ec_prj* Q);
secret_bool ctt_banderwagon_ec_prj_is_neutral(const banderwagon_ec_prj* P);
void ctt_banderwagon_ec_prj_set_neutral(banderwagon_ec_prj* P);
void ctt_banderwagon_ec_prj_ccopy(banderwagon_ec_prj* P, const banderwagon_ec_prj* Q, secret_bool ctl);
secret_bool ctt_banderwagon_ec_prj_neg(banderwagon_ec_prj* P, const banderwagon_ec_prj* Q);
void ctt_banderwagon_ec_prj_neg_in_place(banderwagon_ec_prj* P);
void ctt_banderwagon_ec_prj_cneg(banderwagon_ec_prj* P, const secret_bool ctl);
void ctt_banderwagon_ec_prj_sum(banderwagon_ec_prj* r, const banderwagon_ec_prj* P, const banderwagon_ec_prj* Q);
void ctt_banderwagon_ec_prj_double(banderwagon_ec_prj* r, const banderwagon_ec_prj* P);
void ctt_banderwagon_ec_prj_add_in_place(banderwagon_ec_prj* P, const banderwagon_ec_prj* Q);
void ctt_banderwagon_ec_prj_diff(banderwagon_ec_prj* r, const banderwagon_ec_prj* P, const banderwagon_ec_prj* Q);
void ctt_banderwagon_ec_prj_diff_in_place(banderwagon_ec_prj* P, const banderwagon_ec_prj* Q);
void ctt_banderwagon_ec_prj_mixed_diff_in_place(banderwagon_ec_prj* P, const banderwagon_ec_aff* Q);
void ctt_banderwagon_ec_prj_affine(banderwagon_ec_aff* dst, const banderwagon_ec_prj* src);
void ctt_banderwagon_ec_prj_from_affine(banderwagon_ec_prj* dst, const banderwagon_ec_aff* src);
void ctt_banderwagon_ec_prj_batch_affine(const banderwagon_ec_aff dst[], const banderwagon_ec_prj src[], size_t n);
void ctt_banderwagon_ec_prj_scalar_mul_big_coef(banderwagon_ec_prj* P, const big253* scalar);
void ctt_banderwagon_ec_prj_scalar_mul_fr_coef(banderwagon_ec_prj* P, const banderwagon_fr* scalar);
void ctt_banderwagon_ec_prj_scalar_mul_big_coef_vartime(banderwagon_ec_prj* P, const big253* scalar);
void ctt_banderwagon_ec_prj_scalar_mul_fr_coef_vartime(banderwagon_ec_prj* P, const banderwagon_fr* scalar);
void ctt_banderwagon_ec_prj_multi_scalar_mul_big_coefs_vartime(banderwagon_ec_prj* r, const big253 coefs[], const banderwagon_ec_aff points[], size_t len);
void ctt_banderwagon_ec_prj_multi_scalar_mul_fr_coefs_vartime(banderwagon_ec_prj* r, const banderwagon_fr coefs[], const banderwagon_ec_aff points[], size_t len);

#ifdef __cplusplus
}
#endif

#endif // __CTT_H_BANDERWAGON__
