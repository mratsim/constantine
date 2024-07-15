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
    ec_shortweierstrass_jacobian_extended,
    ec_shortweierstrass_projective,
    ec_shortweierstrass_batch_ops,
    ec_scalar_mul, ec_scalar_mul_vartime,
    ec_multi_scalar_mul,
  ],
  ../named/zoo_generators

export ec_shortweierstrass_affine, ec_shortweierstrass_jacobian, ec_shortweierstrass_projective,
       ec_shortweierstrass_jacobian_extended,
       ec_shortweierstrass_batch_ops, ec_scalar_mul, ec_scalar_mul_vartime,
       ec_multi_scalar_mul

type EC_ShortW*[F; G: static Subgroup] = EC_ShortW_Aff[F, G] | EC_ShortW_Jac[F, G] | EC_ShortW_Prj[F, G]

func projectiveFromJacobian*[F; G](
       prj: var EC_ShortW_Prj[F, G],
       jac: EC_ShortW_Jac[F, G]) {.inline.} =
  prj.x.prod(jac.x, jac.z)
  prj.y = jac.y
  prj.z.square(jac.z)
  prj.z *= jac.z

func double_repeated*(P: var EC_ShortW, num: int) {.inline.} =
  ## Repeated doublings
  for _ in 0 ..< num:
    P.double()

func setGenerator*[F, G](g: var EC_ShortW[F, G]) {.inline.} =
  when g is EC_ShortW_Aff:
    g = F.Name.getGenerator($G)
  else:
    g.fromAffine(F.Name.getGenerator($G))
