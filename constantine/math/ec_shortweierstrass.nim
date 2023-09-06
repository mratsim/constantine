# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

# ############################################################
#
#                Short Weierstrass Elliptic Curves
#
# ############################################################

import
  ./arithmetic,
  elliptic/[
    ec_shortweierstrass_affine,
    ec_shortweierstrass_jacobian,
    ec_shortweierstrass_projective,
    ec_shortweierstrass_batch_ops,
    ec_scalar_mul, ec_scalar_mul_vartime
  ]

export ec_shortweierstrass_affine, ec_shortweierstrass_jacobian, ec_shortweierstrass_projective,
       ec_shortweierstrass_batch_ops, ec_scalar_mul, ec_scalar_mul_vartime

type ECP_ShortW*[F; G: static Subgroup] = ECP_ShortW_Aff[F, G] | ECP_ShortW_Jac[F, G] | ECP_ShortW_Prj[F, G]

func projectiveFromJacobian*[F; G](
       prj: var ECP_ShortW_Prj[F, G],
       jac: ECP_ShortW_Jac[F, G]) {.inline.} =
  prj.x.prod(jac.x, jac.z)
  prj.y = jac.y
  prj.z.square(jac.z)
  prj.z *= jac.z

func double_repeated*(P: var ECP_ShortW, num: int) {.inline.} =
  ## Repeated doublings
  for _ in 0 ..< num:
    P.double()
