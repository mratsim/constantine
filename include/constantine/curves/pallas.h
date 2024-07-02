/** Constantine
 *  Copyright (c) 2018-2019    Status Research & Development GmbH
 *  Copyright (c) 2020-Present Mamy André-Ratsimbazafy
 *  Licensed and distributed under either of
 *    * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
 *    * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
 *  at your option. This file may not be copied, modified, or distributed except according to those terms.
 */
#ifndef __CTT_H_PALLAS__
#define __CTT_H_PALLAS__

#include "constantine/core/datatypes.h"
#include "constantine/curves/bigints.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef struct { secret_word limbs[CTT_WORDS_REQUIRED(255)]; } pallas_fr;
typedef struct { secret_word limbs[CTT_WORDS_REQUIRED(255)]; } pallas_fp;
typedef struct { pallas_fp x, y; } pallas_ec_aff;
typedef struct { pallas_fp x, y, z; } pallas_ec_jac;
typedef struct { pallas_fp x, y, z; } pallas_ec_prj;

void        ctt_big255_from_pallas_fr(big255* dst, const pallas_fr* src);
void        ctt_pallas_fr_from_big255(pallas_fr* dst, const big255* src);
ctt_bool    ctt_pallas_fr_unmarshalBE(pallas_fr* dst, const byte src[], size_t src_len) __attribute__((warn_unused_result));
ctt_bool    ctt_pallas_fr_marshalBE(byte dst[], size_t dst_len, const pallas_fr* src) __attribute__((warn_unused_result));
secret_bool ctt_pallas_fr_is_eq(const pallas_fr* a, const pallas_fr* b);
secret_bool ctt_pallas_fr_is_zero(const pallas_fr* a);
secret_bool ctt_pallas_fr_is_one(const pallas_fr* a);
secret_bool ctt_pallas_fr_is_minus_one(const pallas_fr* a);
void        ctt_pallas_fr_set_zero(pallas_fr* a);
void        ctt_pallas_fr_set_one(pallas_fr* a);
void        ctt_pallas_fr_set_minus_one(pallas_fr* a);
void        ctt_pallas_fr_neg(pallas_fr* r, const pallas_fr* a);
void        ctt_pallas_fr_neg_in_place(pallas_fr* a);
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
void        ctt_pallas_fr_ccopy(pallas_fr* a, const pallas_fr* b, secret_bool ctl);
void        ctt_pallas_fr_cswap(pallas_fr* a, pallas_fr* b, secret_bool ctl);
void        ctt_pallas_fr_cset_zero(pallas_fr* a, secret_bool ctl);
void        ctt_pallas_fr_cset_one(pallas_fr* a, secret_bool ctl);
void        ctt_pallas_fr_cneg_in_place(pallas_fr* a, secret_bool ctl);
void        ctt_pallas_fr_cadd_in_place(pallas_fr* a, const pallas_fr* b, secret_bool ctl);
void        ctt_pallas_fr_csub_in_place(pallas_fr* a, const pallas_fr* b, secret_bool ctl);
void        ctt_big255_from_pallas_fp(big255* dst, const pallas_fp* src);
void        ctt_pallas_fp_from_big255(pallas_fp* dst, const big255* src);
ctt_bool    ctt_pallas_fp_unmarshalBE(pallas_fp* dst, const byte src[], size_t src_len) __attribute__((warn_unused_result));
ctt_bool    ctt_pallas_fp_marshalBE(byte dst[], size_t dst_len, const pallas_fp* src) __attribute__((warn_unused_result));
secret_bool ctt_pallas_fp_is_eq(const pallas_fp* a, const pallas_fp* b);
secret_bool ctt_pallas_fp_is_zero(const pallas_fp* a);
secret_bool ctt_pallas_fp_is_one(const pallas_fp* a);
secret_bool ctt_pallas_fp_is_minus_one(const pallas_fp* a);
void        ctt_pallas_fp_set_zero(pallas_fp* a);
void        ctt_pallas_fp_set_one(pallas_fp* a);
void        ctt_pallas_fp_set_minus_one(pallas_fp* a);
void        ctt_pallas_fp_neg(pallas_fp* r, const pallas_fp* a);
void        ctt_pallas_fp_neg_in_place(pallas_fp* a);
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
void        ctt_pallas_fp_ccopy(pallas_fp* a, const pallas_fp* b, secret_bool ctl);
void        ctt_pallas_fp_cswap(pallas_fp* a, pallas_fp* b, secret_bool ctl);
void        ctt_pallas_fp_cset_zero(pallas_fp* a, secret_bool ctl);
void        ctt_pallas_fp_cset_one(pallas_fp* a, secret_bool ctl);
void        ctt_pallas_fp_cneg_in_place(pallas_fp* a, secret_bool ctl);
void        ctt_pallas_fp_cadd_in_place(pallas_fp* a, const pallas_fp* b, secret_bool ctl);
void        ctt_pallas_fp_csub_in_place(pallas_fp* a, const pallas_fp* b, secret_bool ctl);
secret_bool ctt_pallas_fp_is_square(const pallas_fp* a);
void        ctt_pallas_fp_invsqrt(pallas_fp* r, const pallas_fp* a);
secret_bool ctt_pallas_fp_invsqrt_in_place(pallas_fp* r, const pallas_fp* a);
void        ctt_pallas_fp_sqrt_in_place(pallas_fp* a);
secret_bool ctt_pallas_fp_sqrt_if_square_in_place(pallas_fp* a);
void        ctt_pallas_fp_sqrt_invsqrt(pallas_fp* sqrt, pallas_fp* invsqrt, const pallas_fp* a);
secret_bool ctt_pallas_fp_sqrt_invsqrt_if_square(pallas_fp* sqrt, pallas_fp* invsqrt, const pallas_fp* a);
secret_bool ctt_pallas_fp_sqrt_ratio_if_square(pallas_fp* r, const pallas_fp* u, const pallas_fp* v);
secret_bool ctt_pallas_ec_aff_is_eq(const pallas_ec_aff* P, const pallas_ec_aff* Q);
secret_bool ctt_pallas_ec_aff_is_neutral(const pallas_ec_aff* P);
void        ctt_pallas_ec_aff_set_neutral(pallas_ec_aff* P);
void        ctt_pallas_ec_aff_ccopy(pallas_ec_aff* P, const pallas_ec_aff* Q, secret_bool ctl);
secret_bool ctt_pallas_ec_aff_is_on_curve(const pallas_fp* x, const pallas_fp* y);
void        ctt_pallas_ec_aff_neg(pallas_ec_aff* P, const pallas_ec_aff* Q);
void        ctt_pallas_ec_aff_neg_in_place(pallas_ec_aff* P);
secret_bool ctt_pallas_ec_jac_is_eq(const pallas_ec_jac* P, const pallas_ec_jac* Q);
secret_bool ctt_pallas_ec_jac_is_neutral(const pallas_ec_jac* P);
void        ctt_pallas_ec_jac_set_neutral(pallas_ec_jac* P);
void        ctt_pallas_ec_jac_ccopy(pallas_ec_jac* P, const pallas_ec_jac* Q, secret_bool ctl);
void        ctt_pallas_ec_jac_neg(pallas_ec_jac* P, const pallas_ec_jac* Q);
void        ctt_pallas_ec_jac_neg_in_place(pallas_ec_jac* P);
void        ctt_pallas_ec_jac_cneg_in_place(pallas_ec_jac* P, secret_bool ctl);
void        ctt_pallas_ec_jac_sum(pallas_ec_jac* r, const pallas_ec_jac* P, const pallas_ec_jac* Q);
void        ctt_pallas_ec_jac_add_in_place(pallas_ec_jac* P, const pallas_ec_jac* Q);
void        ctt_pallas_ec_jac_diff(pallas_ec_jac* r, const pallas_ec_jac* P, const pallas_ec_jac* Q);
void        ctt_pallas_ec_jac_double(pallas_ec_jac* r, const pallas_ec_jac* P);
void        ctt_pallas_ec_jac_double_in_place(pallas_ec_jac* P);
void        ctt_pallas_ec_jac_affine(pallas_ec_aff* dst, const pallas_ec_jac* src);
void        ctt_pallas_ec_jac_from_affine(pallas_ec_jac* dst, const pallas_ec_aff* src);
void        ctt_pallas_ec_jac_batch_affine(const pallas_ec_aff dst[], const pallas_ec_jac src[], size_t n);
void        ctt_pallas_ec_jac_scalar_mul_big_coef(pallas_ec_jac* P, const big255* scalar);
void        ctt_pallas_ec_jac_scalar_mul_fr_coef(pallas_ec_jac* P, const pallas_fr* scalar);
void        ctt_pallas_ec_jac_scalar_mul_big_coef_vartime(pallas_ec_jac* P, const big255* scalar);
void        ctt_pallas_ec_jac_scalar_mul_fr_coef_vartime(pallas_ec_jac* P, const pallas_fr* scalar);
void        ctt_pallas_ec_jac_multi_scalar_mul_big_coefs_vartime(pallas_ec_jac* r, const big255 coefs[], const pallas_ec_aff points[], size_t len);
void        ctt_pallas_ec_jac_multi_scalar_mul_fr_coefs_vartime(pallas_ec_jac* r, const pallas_fr coefs[], const pallas_ec_aff points[], size_t len);
secret_bool ctt_pallas_ec_prj_is_eq(const pallas_ec_prj* P, const pallas_ec_prj* Q);
secret_bool ctt_pallas_ec_prj_is_neutral(const pallas_ec_prj* P);
void        ctt_pallas_ec_prj_set_neutral(pallas_ec_prj* P);
void        ctt_pallas_ec_prj_ccopy(pallas_ec_prj* P, const pallas_ec_prj* Q, secret_bool ctl);
void        ctt_pallas_ec_prj_neg(pallas_ec_prj* P, const pallas_ec_prj* Q);
void        ctt_pallas_ec_prj_neg_in_place(pallas_ec_prj* P);
void        ctt_pallas_ec_prj_cneg_in_place(pallas_ec_prj* P, secret_bool ctl);
void        ctt_pallas_ec_prj_sum(pallas_ec_prj* r, const pallas_ec_prj* P, const pallas_ec_prj* Q);
void        ctt_pallas_ec_prj_add_in_place(pallas_ec_prj* P, const pallas_ec_prj* Q);
void        ctt_pallas_ec_prj_diff(pallas_ec_prj* r, const pallas_ec_prj* P, const pallas_ec_prj* Q);
void        ctt_pallas_ec_prj_double(pallas_ec_prj* r, const pallas_ec_prj* P);
void        ctt_pallas_ec_prj_double_in_place(pallas_ec_prj* P);
void        ctt_pallas_ec_prj_affine(pallas_ec_aff* dst, const pallas_ec_prj* src);
void        ctt_pallas_ec_prj_from_affine(pallas_ec_prj* dst, const pallas_ec_aff* src);
void        ctt_pallas_ec_prj_batch_affine(const pallas_ec_aff dst[], const pallas_ec_prj src[], size_t n);
void        ctt_pallas_ec_prj_scalar_mul_big_coef(pallas_ec_prj* P, const big255* scalar);
void        ctt_pallas_ec_prj_scalar_mul_fr_coef(pallas_ec_prj* P, const pallas_fr* scalar);
void        ctt_pallas_ec_prj_scalar_mul_big_coef_vartime(pallas_ec_prj* P, const big255* scalar);
void        ctt_pallas_ec_prj_scalar_mul_fr_coef_vartime(pallas_ec_prj* P, const pallas_fr* scalar);
void        ctt_pallas_ec_prj_multi_scalar_mul_big_coefs_vartime(pallas_ec_prj* r, const big255 coefs[], const pallas_ec_aff points[], size_t len);
void        ctt_pallas_ec_prj_multi_scalar_mul_fr_coefs_vartime(pallas_ec_prj* r, const pallas_fr coefs[], const pallas_ec_aff points[], size_t len);

#ifdef __cplusplus
}
#endif

#endif // __CTT_H_PALLAS__
