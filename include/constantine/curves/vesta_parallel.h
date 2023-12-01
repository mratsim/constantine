/** Constantine
 *  Copyright (c) 2018-2019    Status Research & Development GmbH
 *  Copyright (c) 2020-Present Mamy André-Ratsimbazafy
 *  Licensed and distributed under either of
 *    * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
 *    * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
 *  at your option. This file may not be copied, modified, or distributed except according to those terms.
 */
#ifndef __CTT_H_VESTA_PARALLEL__
#define __CTT_H_VESTA_PARALLEL__

#include "constantine/core/datatypes.h"
#include "constantine/core/threadpool.h"
#include "constantine/curves/bigints.h"
#include "constantine/curves/vesta.h"

#ifdef __cplusplus
extern "C" {
#endif

void        ctt_vesta_ec_jac_multi_scalar_mul_big_coefs_vartime_parallel(const ctt_threadpool* tp, vesta_ec_jac* r, const big255 coefs[], const vesta_ec_aff points[], size_t len);
void        ctt_vesta_ec_jac_multi_scalar_mul_fr_coefs_vartime_parallel(const ctt_threadpool* tp, vesta_ec_jac* r, const vesta_fr coefs[], const vesta_ec_aff points[], size_t len);
void        ctt_vesta_ec_prj_multi_scalar_mul_big_coefs_vartime_parallel(const ctt_threadpool* tp, vesta_ec_prj* r, const big255 coefs[], const vesta_ec_aff points[], size_t len);
void        ctt_vesta_ec_prj_multi_scalar_mul_fr_coefs_vartime_parallel(const ctt_threadpool* tp, vesta_ec_prj* r, const vesta_fr coefs[], const vesta_ec_aff points[], size_t len);

#ifdef __cplusplus
}
#endif

#endif // __CTT_H_VESTA_PARALLEL__
