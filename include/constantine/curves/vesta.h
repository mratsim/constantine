/** Constantine
 *  Copyright (c) 2018-2019    Status Research & Development GmbH
 *  Copyright (c) 2020-Present Mamy André-Ratsimbazafy
 *  Licensed and distributed under either of
 *    * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
 *    * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
 *  at your option. This file may not be copied, modified, or distributed except according to those terms.
 */
#ifndef __CTT_H_VESTA__
#define __CTT_H_VESTA__

#include "constantine/core/datatypes.h"
#include "constantine/curves/bigints.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef struct { secret_word limbs[CTT_WORDS_REQUIRED(255)]; } vesta_fr;
typedef struct { secret_word limbs[CTT_WORDS_REQUIRED(255)]; } vesta_fp;
typedef struct { vesta_fp x, y; } vesta_ec_aff;
typedef struct { vesta_fp x, y, z; } vesta_ec_jac;
typedef struct { vesta_fp x, y, z; } vesta_ec_prj;

void        ctt_big255_from_vesta_fr(big255* dst, const vesta_fr* src);
void        ctt_vesta_fr_from_big255(vesta_fr* dst, const big255* src);
ctt_bool    ctt_vesta_fr_unmarshalBE(vesta_fr* dst, const byte src[], size_t src_len) __attribute__((warn_unused_result));
ctt_bool    ctt_vesta_fr_marshalBE(byte dst[], size_t dst_len, const vesta_fr* src) __attribute__((warn_unused_result));
secret_bool ctt_vesta_fr_is_eq(const vesta_fr* a, const vesta_fr* b);
secret_bool ctt_vesta_fr_is_zero(const vesta_fr* a);
secret_bool ctt_vesta_fr_is_one(const vesta_fr* a);
secret_bool ctt_vesta_fr_is_minus_one(const vesta_fr* a);
void        ctt_vesta_fr_set_zero(vesta_fr* a);
void        ctt_vesta_fr_set_one(vesta_fr* a);
void        ctt_vesta_fr_set_minus_one(vesta_fr* a);
void        ctt_vesta_fr_neg(vesta_fr* r, const vesta_fr* a);
void        ctt_vesta_fr_neg_in_place(vesta_fr* a);
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
void        ctt_vesta_fr_ccopy(vesta_fr* a, const vesta_fr* b, secret_bool ctl);
void        ctt_vesta_fr_cswap(vesta_fr* a, vesta_fr* b, secret_bool ctl);
void        ctt_vesta_fr_cset_zero(vesta_fr* a, secret_bool ctl);
void        ctt_vesta_fr_cset_one(vesta_fr* a, secret_bool ctl);
void        ctt_vesta_fr_cneg_in_place(vesta_fr* a, secret_bool ctl);
void        ctt_vesta_fr_cadd_in_place(vesta_fr* a, const vesta_fr* b, secret_bool ctl);
void        ctt_vesta_fr_csub_in_place(vesta_fr* a, const vesta_fr* b, secret_bool ctl);
void        ctt_big255_from_vesta_fp(big255* dst, const vesta_fp* src);
void        ctt_vesta_fp_from_big255(vesta_fp* dst, const big255* src);
ctt_bool    ctt_vesta_fp_unmarshalBE(vesta_fp* dst, const byte src[], size_t src_len) __attribute__((warn_unused_result));
ctt_bool    ctt_vesta_fp_marshalBE(byte dst[], size_t dst_len, const vesta_fp* src) __attribute__((warn_unused_result));
secret_bool ctt_vesta_fp_is_eq(const vesta_fp* a, const vesta_fp* b);
secret_bool ctt_vesta_fp_is_zero(const vesta_fp* a);
secret_bool ctt_vesta_fp_is_one(const vesta_fp* a);
secret_bool ctt_vesta_fp_is_minus_one(const vesta_fp* a);
void        ctt_vesta_fp_set_zero(vesta_fp* a);
void        ctt_vesta_fp_set_one(vesta_fp* a);
void        ctt_vesta_fp_set_minus_one(vesta_fp* a);
void        ctt_vesta_fp_neg(vesta_fp* r, const vesta_fp* a);
void        ctt_vesta_fp_neg_in_place(vesta_fp* a);
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
void        ctt_vesta_fp_ccopy(vesta_fp* a, const vesta_fp* b, secret_bool ctl);
void        ctt_vesta_fp_cswap(vesta_fp* a, vesta_fp* b, secret_bool ctl);
void        ctt_vesta_fp_cset_zero(vesta_fp* a, secret_bool ctl);
void        ctt_vesta_fp_cset_one(vesta_fp* a, secret_bool ctl);
void        ctt_vesta_fp_cneg_in_place(vesta_fp* a, secret_bool ctl);
void        ctt_vesta_fp_cadd_in_place(vesta_fp* a, const vesta_fp* b, secret_bool ctl);
void        ctt_vesta_fp_csub_in_place(vesta_fp* a, const vesta_fp* b, secret_bool ctl);
secret_bool ctt_vesta_fp_is_square(const vesta_fp* a);
void        ctt_vesta_fp_invsqrt(vesta_fp* r, const vesta_fp* a);
secret_bool ctt_vesta_fp_invsqrt_in_place(vesta_fp* r, const vesta_fp* a);
void        ctt_vesta_fp_sqrt_in_place(vesta_fp* a);
secret_bool ctt_vesta_fp_sqrt_if_square_in_place(vesta_fp* a);
void        ctt_vesta_fp_sqrt_invsqrt(vesta_fp* sqrt, vesta_fp* invsqrt, const vesta_fp* a);
secret_bool ctt_vesta_fp_sqrt_invsqrt_if_square(vesta_fp* sqrt, vesta_fp* invsqrt, const vesta_fp* a);
secret_bool ctt_vesta_fp_sqrt_ratio_if_square(vesta_fp* r, const vesta_fp* u, const vesta_fp* v);
secret_bool ctt_vesta_ec_aff_is_eq(const vesta_ec_aff* P, const vesta_ec_aff* Q);
secret_bool ctt_vesta_ec_aff_is_neutral(const vesta_ec_aff* P);
void        ctt_vesta_ec_aff_set_neutral(vesta_ec_aff* P);
void        ctt_vesta_ec_aff_ccopy(vesta_ec_aff* P, const vesta_ec_aff* Q, secret_bool ctl);
secret_bool ctt_vesta_ec_aff_is_on_curve(const vesta_fp* x, const vesta_fp* y);
void        ctt_vesta_ec_aff_neg(vesta_ec_aff* P, const vesta_ec_aff* Q);
void        ctt_vesta_ec_aff_neg_in_place(vesta_ec_aff* P);
secret_bool ctt_vesta_ec_jac_is_eq(const vesta_ec_jac* P, const vesta_ec_jac* Q);
secret_bool ctt_vesta_ec_jac_is_neutral(const vesta_ec_jac* P);
void        ctt_vesta_ec_jac_set_neutral(vesta_ec_jac* P);
void        ctt_vesta_ec_jac_ccopy(vesta_ec_jac* P, const vesta_ec_jac* Q, secret_bool ctl);
void        ctt_vesta_ec_jac_neg(vesta_ec_jac* P, const vesta_ec_jac* Q);
void        ctt_vesta_ec_jac_neg_in_place(vesta_ec_jac* P);
void        ctt_vesta_ec_jac_cneg_in_place(vesta_ec_jac* P, secret_bool ctl);
void        ctt_vesta_ec_jac_sum(vesta_ec_jac* r, const vesta_ec_jac* P, const vesta_ec_jac* Q);
void        ctt_vesta_ec_jac_add_in_place(vesta_ec_jac* P, const vesta_ec_jac* Q);
void        ctt_vesta_ec_jac_diff(vesta_ec_jac* r, const vesta_ec_jac* P, const vesta_ec_jac* Q);
void        ctt_vesta_ec_jac_double(vesta_ec_jac* r, const vesta_ec_jac* P);
void        ctt_vesta_ec_jac_double_in_place(vesta_ec_jac* P);
void        ctt_vesta_ec_jac_affine(vesta_ec_aff* dst, const vesta_ec_jac* src);
void        ctt_vesta_ec_jac_from_affine(vesta_ec_jac* dst, const vesta_ec_aff* src);
void        ctt_vesta_ec_jac_batch_affine(const vesta_ec_aff dst[], const vesta_ec_jac src[], size_t n);
void        ctt_vesta_ec_jac_scalar_mul_big_coef(vesta_ec_jac* P, const big255* scalar);
void        ctt_vesta_ec_jac_scalar_mul_fr_coef(vesta_ec_jac* P, const vesta_fr* scalar);
void        ctt_vesta_ec_jac_scalar_mul_big_coef_vartime(vesta_ec_jac* P, const big255* scalar);
void        ctt_vesta_ec_jac_scalar_mul_fr_coef_vartime(vesta_ec_jac* P, const vesta_fr* scalar);
void        ctt_vesta_ec_jac_multi_scalar_mul_big_coefs_vartime(vesta_ec_jac* r, const big255 coefs[], const vesta_ec_aff points[], size_t len);
void        ctt_vesta_ec_jac_multi_scalar_mul_fr_coefs_vartime(vesta_ec_jac* r, const vesta_fr coefs[], const vesta_ec_aff points[], size_t len);
secret_bool ctt_vesta_ec_prj_is_eq(const vesta_ec_prj* P, const vesta_ec_prj* Q);
secret_bool ctt_vesta_ec_prj_is_neutral(const vesta_ec_prj* P);
void        ctt_vesta_ec_prj_set_neutral(vesta_ec_prj* P);
void        ctt_vesta_ec_prj_ccopy(vesta_ec_prj* P, const vesta_ec_prj* Q, secret_bool ctl);
void        ctt_vesta_ec_prj_neg(vesta_ec_prj* P, const vesta_ec_prj* Q);
void        ctt_vesta_ec_prj_neg_in_place(vesta_ec_prj* P);
void        ctt_vesta_ec_prj_cneg_in_place(vesta_ec_prj* P, secret_bool ctl);
void        ctt_vesta_ec_prj_sum(vesta_ec_prj* r, const vesta_ec_prj* P, const vesta_ec_prj* Q);
void        ctt_vesta_ec_prj_add_in_place(vesta_ec_prj* P, const vesta_ec_prj* Q);
void        ctt_vesta_ec_prj_diff(vesta_ec_prj* r, const vesta_ec_prj* P, const vesta_ec_prj* Q);
void        ctt_vesta_ec_prj_double(vesta_ec_prj* r, const vesta_ec_prj* P);
void        ctt_vesta_ec_prj_double_in_place(vesta_ec_prj* P);
void        ctt_vesta_ec_prj_affine(vesta_ec_aff* dst, const vesta_ec_prj* src);
void        ctt_vesta_ec_prj_from_affine(vesta_ec_prj* dst, const vesta_ec_aff* src);
void        ctt_vesta_ec_prj_batch_affine(const vesta_ec_aff dst[], const vesta_ec_prj src[], size_t n);
void        ctt_vesta_ec_prj_scalar_mul_big_coef(vesta_ec_prj* P, const big255* scalar);
void        ctt_vesta_ec_prj_scalar_mul_fr_coef(vesta_ec_prj* P, const vesta_fr* scalar);
void        ctt_vesta_ec_prj_scalar_mul_big_coef_vartime(vesta_ec_prj* P, const big255* scalar);
void        ctt_vesta_ec_prj_scalar_mul_fr_coef_vartime(vesta_ec_prj* P, const vesta_fr* scalar);
void        ctt_vesta_ec_prj_multi_scalar_mul_big_coefs_vartime(vesta_ec_prj* r, const big255 coefs[], const vesta_ec_aff points[], size_t len);
void        ctt_vesta_ec_prj_multi_scalar_mul_fr_coefs_vartime(vesta_ec_prj* r, const vesta_fr coefs[], const vesta_ec_aff points[], size_t len);

#ifdef __cplusplus
}
#endif

#endif // __CTT_H_VESTA__
