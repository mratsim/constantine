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
  elliptic/[
    ec_shortweierstrass_affine,
    ec_shortweierstrass_jacobian,
    ec_shortweierstrass_projective,
    ec_scalar_mul
  ]

export ec_shortweierstrass_affine, ec_shortweierstrass_jacobian, ec_shortweierstrass_projective, ec_scalar_mul

func projectiveFromJacobian*[F; Tw](
       prj: var ECP_ShortW_Prj[F, Tw],
       jac: ECP_ShortW_Jac[F, Tw]) {.inline.} =
  prj.x.prod(jac.x, jac.z)
  prj.y = jac.y
  prj.z.square(jac.z)
  prj.z *= jac.z

