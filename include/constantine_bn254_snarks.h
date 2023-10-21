/** Constantine
 *  Copyright (c) 2018-2019    Status Research & Development GmbH
 *  Copyright (c) 2020-Present Mamy André-Ratsimbazafy
 *  Licensed and distributed under either of
 *    * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
 *    * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
 *  at your option. This file may not be copied, modified, or distributed except according to those terms.
 */
#ifndef __CTT_H_BN254SNARKS__
#define __CTT_H_BN254SNARKS__

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

#if defined(__STDC_VERSION__) && __STDC_VERSION__>=199901
# define bool _Bool
#else
# define bool unsigned char
#endif

typedef size_t           secret_word;
typedef size_t           secret_bool;
typedef uint8_t          byte;

#define WordBitWidth         (sizeof(secret_word)*8)
#define words_required(bits) ((bits+WordBitWidth-1)/WordBitWidth)

typedef struct { secret_word limbs[words_required(254)]; } bn254_snarks_fr;
typedef struct { secret_word limbs[words_required(254)]; } bn254_snarks_fp;
typedef struct { bn254_snarks_fp c[2]; } bn254_snarks_fp2;
typedef struct { bn254_snarks_fp x, y; } bn254_snarks_ec_g1_aff;
typedef struct { bn254_snarks_fp x, y, z; } bn254_snarks_ec_g1_jac;
typedef struct { bn254_snarks_fp x, y, z; } bn254_snarks_ec_g1_prj;
typedef struct { bn254_snarks_fp2 x, y; } bn254_snarks_ec_g2_aff;
typedef struct { bn254_snarks_fp2 x, y, z; } bn254_snarks_ec_g2_jac;
typedef struct { bn254_snarks_fp2 x, y, z; } bn254_snarks_ec_g2_prj;

/*
 * Initializes the library:
 * - detect CPU features like ADX instructions support (MULX, ADCX, ADOX)
 */
void ctt_bn254_snarks_init_NimMain(void);

bool ctt_bn254_snarks_fr_unmarshalBE(bn254_snarks_fr* dst, const byte src[], ptrdiff_t src_len) __attribute__((warn_unused_result));
bool ctt_bn254_snarks_fr_marshalBE(byte dst[], ptrdiff_t dst_len, const bn254_snarks_fr* src) __attribute__((warn_unused_result));
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
void        ctt_bn254_snarks_fr_ccopy(bn254_snarks_fr* a, const bn254_snarks_fr* b, const secret_bool ctl);
void        ctt_bn254_snarks_fr_cswap(bn254_snarks_fr* a, bn254_snarks_fr* b, const secret_bool ctl);
void        ctt_bn254_snarks_fr_cset_zero(bn254_snarks_fr* a, const secret_bool ctl);
void        ctt_bn254_snarks_fr_cset_one(bn254_snarks_fr* a, const secret_bool ctl);
void        ctt_bn254_snarks_fr_cneg_in_place(bn254_snarks_fr* a, const secret_bool ctl);
void        ctt_bn254_snarks_fr_cadd_in_place(bn254_snarks_fr* a, const bn254_snarks_fr* b, const secret_bool ctl);
void        ctt_bn254_snarks_fr_csub_in_place(bn254_snarks_fr* a, const bn254_snarks_fr* b, const secret_bool ctl);
bool ctt_bn254_snarks_fp_unmarshalBE(bn254_snarks_fp* dst, const byte src[], ptrdiff_t src_len) __attribute__((warn_unused_result));
bool ctt_bn254_snarks_fp_marshalBE(byte dst[], ptrdiff_t dst_len, const bn254_snarks_fp* src) __attribute__((warn_unused_result));
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
void        ctt_bn254_snarks_fp_ccopy(bn254_snarks_fp* a, const bn254_snarks_fp* b, const secret_bool ctl);
void        ctt_bn254_snarks_fp_cswap(bn254_snarks_fp* a, bn254_snarks_fp* b, const secret_bool ctl);
void        ctt_bn254_snarks_fp_cset_zero(bn254_snarks_fp* a, const secret_bool ctl);
void        ctt_bn254_snarks_fp_cset_one(bn254_snarks_fp* a, const secret_bool ctl);
void        ctt_bn254_snarks_fp_cneg_in_place(bn254_snarks_fp* a, const secret_bool ctl);
void        ctt_bn254_snarks_fp_cadd_in_place(bn254_snarks_fp* a, const bn254_snarks_fp* b, const secret_bool ctl);
void        ctt_bn254_snarks_fp_csub_in_place(bn254_snarks_fp* a, const bn254_snarks_fp* b, const secret_bool ctl);
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
void        ctt_bn254_snarks_fp2_ccopy(bn254_snarks_fp2* a, const bn254_snarks_fp2* b, const secret_bool ctl);
void        ctt_bn254_snarks_fp2_cset_zero(bn254_snarks_fp2* a, const secret_bool ctl);
void        ctt_bn254_snarks_fp2_cset_one(bn254_snarks_fp2* a, const secret_bool ctl);
void        ctt_bn254_snarks_fp2_cneg_in_place(bn254_snarks_fp2* a, const secret_bool ctl);
void        ctt_bn254_snarks_fp2_cadd_in_place(bn254_snarks_fp2* a, const bn254_snarks_fp2* b, const secret_bool ctl);
void        ctt_bn254_snarks_fp2_csub_in_place(bn254_snarks_fp2* a, const bn254_snarks_fp2* b, const secret_bool ctl);
secret_bool ctt_bn254_snarks_fp2_is_square(const bn254_snarks_fp2* a);
void        ctt_bn254_snarks_fp2_sqrt_in_place(bn254_snarks_fp2* a);
secret_bool ctt_bn254_snarks_fp2_sqrt_if_square_in_place(bn254_snarks_fp2* a);
secret_bool ctt_bn254_snarks_ec_g1_aff_is_eq(const bn254_snarks_ec_g1_aff* P, const bn254_snarks_ec_g1_aff* Q);
secret_bool ctt_bn254_snarks_ec_g1_aff_is_inf(const bn254_snarks_ec_g1_aff* P);
void        ctt_bn254_snarks_ec_g1_aff_set_inf(bn254_snarks_ec_g1_aff* P);
void        ctt_bn254_snarks_ec_g1_aff_ccopy(bn254_snarks_ec_g1_aff* P, const bn254_snarks_ec_g1_aff* Q, const secret_bool ctl);
secret_bool ctt_bn254_snarks_ec_g1_aff_is_on_curve(const bn254_snarks_fp* x, const bn254_snarks_fp* y);
void        ctt_bn254_snarks_ec_g1_aff_neg(bn254_snarks_ec_g1_aff* P, const bn254_snarks_ec_g1_aff* Q);
void        ctt_bn254_snarks_ec_g1_aff_neg_in_place(bn254_snarks_ec_g1_aff* P);
secret_bool ctt_bn254_snarks_ec_g1_jac_is_eq(const bn254_snarks_ec_g1_jac* P, const bn254_snarks_ec_g1_jac* Q);
secret_bool ctt_bn254_snarks_ec_g1_jac_is_inf(const bn254_snarks_ec_g1_jac* P);
void        ctt_bn254_snarks_ec_g1_jac_set_inf(bn254_snarks_ec_g1_jac* P);
void        ctt_bn254_snarks_ec_g1_jac_ccopy(bn254_snarks_ec_g1_jac* P, const bn254_snarks_ec_g1_jac* Q, const secret_bool ctl);
void        ctt_bn254_snarks_ec_g1_jac_neg(bn254_snarks_ec_g1_jac* P, const bn254_snarks_ec_g1_jac* Q);
void        ctt_bn254_snarks_ec_g1_jac_neg_in_place(bn254_snarks_ec_g1_jac* P);
void        ctt_bn254_snarks_ec_g1_jac_cneg_in_place(bn254_snarks_ec_g1_jac* P, const secret_bool ctl);
void        ctt_bn254_snarks_ec_g1_jac_sum(bn254_snarks_ec_g1_jac* r, const bn254_snarks_ec_g1_jac* P, const bn254_snarks_ec_g1_jac* Q);
void        ctt_bn254_snarks_ec_g1_jac_add_in_place(bn254_snarks_ec_g1_jac* P, const bn254_snarks_ec_g1_jac* Q);
void        ctt_bn254_snarks_ec_g1_jac_diff(bn254_snarks_ec_g1_jac* r, const bn254_snarks_ec_g1_jac* P, const bn254_snarks_ec_g1_jac* Q);
void        ctt_bn254_snarks_ec_g1_jac_double(bn254_snarks_ec_g1_jac* r, const bn254_snarks_ec_g1_jac* P);
void        ctt_bn254_snarks_ec_g1_jac_double_in_place(bn254_snarks_ec_g1_jac* P);
void        ctt_bn254_snarks_ec_g1_jac_affine(bn254_snarks_ec_g1_aff* dst, const bn254_snarks_ec_g1_jac* src);
void        ctt_bn254_snarks_ec_g1_jac_from_affine(bn254_snarks_ec_g1_jac* dst, const bn254_snarks_ec_g1_aff* src);
secret_bool ctt_bn254_snarks_ec_g1_prj_is_eq(const bn254_snarks_ec_g1_prj* P, const bn254_snarks_ec_g1_prj* Q);
secret_bool ctt_bn254_snarks_ec_g1_prj_is_inf(const bn254_snarks_ec_g1_prj* P);
void        ctt_bn254_snarks_ec_g1_prj_set_inf(bn254_snarks_ec_g1_prj* P);
void        ctt_bn254_snarks_ec_g1_prj_ccopy(bn254_snarks_ec_g1_prj* P, const bn254_snarks_ec_g1_prj* Q, const secret_bool ctl);
void        ctt_bn254_snarks_ec_g1_prj_neg(bn254_snarks_ec_g1_prj* P, const bn254_snarks_ec_g1_prj* Q);
void        ctt_bn254_snarks_ec_g1_prj_neg_in_place(bn254_snarks_ec_g1_prj* P);
void        ctt_bn254_snarks_ec_g1_prj_cneg_in_place(bn254_snarks_ec_g1_prj* P, const secret_bool ctl);
void        ctt_bn254_snarks_ec_g1_prj_sum(bn254_snarks_ec_g1_prj* r, const bn254_snarks_ec_g1_prj* P, const bn254_snarks_ec_g1_prj* Q);
void        ctt_bn254_snarks_ec_g1_prj_add_in_place(bn254_snarks_ec_g1_prj* P, const bn254_snarks_ec_g1_prj* Q);
void        ctt_bn254_snarks_ec_g1_prj_diff(bn254_snarks_ec_g1_prj* r, const bn254_snarks_ec_g1_prj* P, const bn254_snarks_ec_g1_prj* Q);
void        ctt_bn254_snarks_ec_g1_prj_double(bn254_snarks_ec_g1_prj* r, const bn254_snarks_ec_g1_prj* P);
void        ctt_bn254_snarks_ec_g1_prj_double_in_place(bn254_snarks_ec_g1_prj* P);
void        ctt_bn254_snarks_ec_g1_prj_affine(bn254_snarks_ec_g1_aff* dst, const bn254_snarks_ec_g1_prj* src);
void        ctt_bn254_snarks_ec_g1_prj_from_affine(bn254_snarks_ec_g1_prj* dst, const bn254_snarks_ec_g1_aff* src);
secret_bool ctt_bn254_snarks_ec_g2_aff_is_eq(const bn254_snarks_ec_g2_aff* P, const bn254_snarks_ec_g2_aff* Q);
secret_bool ctt_bn254_snarks_ec_g2_aff_is_inf(const bn254_snarks_ec_g2_aff* P);
void        ctt_bn254_snarks_ec_g2_aff_set_inf(bn254_snarks_ec_g2_aff* P);
void        ctt_bn254_snarks_ec_g2_aff_ccopy(bn254_snarks_ec_g2_aff* P, const bn254_snarks_ec_g2_aff* Q, const secret_bool ctl);
secret_bool ctt_bn254_snarks_ec_g2_aff_is_on_curve(const bn254_snarks_fp2* x, const bn254_snarks_fp2* y);
void        ctt_bn254_snarks_ec_g2_aff_neg(bn254_snarks_ec_g2_aff* P, const bn254_snarks_ec_g2_aff* Q);
void        ctt_bn254_snarks_ec_g2_aff_neg_in_place(bn254_snarks_ec_g2_aff* P);
secret_bool ctt_bn254_snarks_ec_g2_jac_is_eq(const bn254_snarks_ec_g2_jac* P, const bn254_snarks_ec_g2_jac* Q);
secret_bool ctt_bn254_snarks_ec_g2_jac_is_inf(const bn254_snarks_ec_g2_jac* P);
void        ctt_bn254_snarks_ec_g2_jac_set_inf(bn254_snarks_ec_g2_jac* P);
void        ctt_bn254_snarks_ec_g2_jac_ccopy(bn254_snarks_ec_g2_jac* P, const bn254_snarks_ec_g2_jac* Q, const secret_bool ctl);
void        ctt_bn254_snarks_ec_g2_jac_neg(bn254_snarks_ec_g2_jac* P, const bn254_snarks_ec_g2_jac* Q);
void        ctt_bn254_snarks_ec_g2_jac_neg_in_place(bn254_snarks_ec_g2_jac* P);
void        ctt_bn254_snarks_ec_g2_jac_cneg_in_place(bn254_snarks_ec_g2_jac* P, const secret_bool ctl);
void        ctt_bn254_snarks_ec_g2_jac_sum(bn254_snarks_ec_g2_jac* r, const bn254_snarks_ec_g2_jac* P, const bn254_snarks_ec_g2_jac* Q);
void        ctt_bn254_snarks_ec_g2_jac_add_in_place(bn254_snarks_ec_g2_jac* P, const bn254_snarks_ec_g2_jac* Q);
void        ctt_bn254_snarks_ec_g2_jac_diff(bn254_snarks_ec_g2_jac* r, const bn254_snarks_ec_g2_jac* P, const bn254_snarks_ec_g2_jac* Q);
void        ctt_bn254_snarks_ec_g2_jac_double(bn254_snarks_ec_g2_jac* r, const bn254_snarks_ec_g2_jac* P);
void        ctt_bn254_snarks_ec_g2_jac_double_in_place(bn254_snarks_ec_g2_jac* P);
void        ctt_bn254_snarks_ec_g2_jac_affine(bn254_snarks_ec_g2_aff* dst, const bn254_snarks_ec_g2_jac* src);
void        ctt_bn254_snarks_ec_g2_jac_from_affine(bn254_snarks_ec_g2_jac* dst, const bn254_snarks_ec_g2_aff* src);
secret_bool ctt_bn254_snarks_ec_g2_prj_is_eq(const bn254_snarks_ec_g2_prj* P, const bn254_snarks_ec_g2_prj* Q);
secret_bool ctt_bn254_snarks_ec_g2_prj_is_inf(const bn254_snarks_ec_g2_prj* P);
void        ctt_bn254_snarks_ec_g2_prj_set_inf(bn254_snarks_ec_g2_prj* P);
void        ctt_bn254_snarks_ec_g2_prj_ccopy(bn254_snarks_ec_g2_prj* P, const bn254_snarks_ec_g2_prj* Q, const secret_bool ctl);
void        ctt_bn254_snarks_ec_g2_prj_neg(bn254_snarks_ec_g2_prj* P, const bn254_snarks_ec_g2_prj* Q);
void        ctt_bn254_snarks_ec_g2_prj_neg_in_place(bn254_snarks_ec_g2_prj* P);
void        ctt_bn254_snarks_ec_g2_prj_cneg_in_place(bn254_snarks_ec_g2_prj* P, const secret_bool ctl);
void        ctt_bn254_snarks_ec_g2_prj_sum(bn254_snarks_ec_g2_prj* r, const bn254_snarks_ec_g2_prj* P, const bn254_snarks_ec_g2_prj* Q);
void        ctt_bn254_snarks_ec_g2_prj_add_in_place(bn254_snarks_ec_g2_prj* P, const bn254_snarks_ec_g2_prj* Q);
void        ctt_bn254_snarks_ec_g2_prj_diff(bn254_snarks_ec_g2_prj* r, const bn254_snarks_ec_g2_prj* P, const bn254_snarks_ec_g2_prj* Q);
void        ctt_bn254_snarks_ec_g2_prj_double(bn254_snarks_ec_g2_prj* r, const bn254_snarks_ec_g2_prj* P);
void        ctt_bn254_snarks_ec_g2_prj_double_in_place(bn254_snarks_ec_g2_prj* P);
void        ctt_bn254_snarks_ec_g2_prj_affine(bn254_snarks_ec_g2_aff* dst, const bn254_snarks_ec_g2_prj* src);
void        ctt_bn254_snarks_ec_g2_prj_from_affine(bn254_snarks_ec_g2_prj* dst, const bn254_snarks_ec_g2_aff* src);


#ifdef __cplusplus
}
#endif


#endif
