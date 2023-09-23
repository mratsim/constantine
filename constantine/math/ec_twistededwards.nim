# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

# ############################################################
#
#                Twisted Edwards Elliptic Curves
#
# ############################################################
import 
    ./arithmetic,
    ./elliptic/[
        ec_multi_scalar_mul, 
        ec_twistededwards_projective, 
        ec_twistededwards_affine,
        ec_scalar_mul,
        ec_scalar_mul_vartime]


export ec_multi_scalar_mul,  ec_twistededwards_projective, ec_twistededwards_affine, ec_scalar_mul, ec_scalar_mul_vartime

type ECP_TwEdwards*[F] = ECP_TwEdwards_Aff[F] | ECP_TwEdwards_Prj[F]

func double_repeated* (P: ECP_TwEdwards, num: int) {.inline.} = 
    ## Repeated doublings
    for _ in 0 ..<num:
        P.double()