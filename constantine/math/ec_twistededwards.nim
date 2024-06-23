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
  ./elliptic/[
    ec_twistededwards_affine,
    ec_twistededwards_projective,
    ec_twistededwards_batch_ops,
    ec_scalar_mul, ec_scalar_mul_vartime,
    ec_multi_scalar_mul,
  ],
  ./constants/zoo_generators

export ec_twistededwards_affine, ec_twistededwards_projective,
       ec_twistededwards_batch_ops, ec_scalar_mul, ec_scalar_mul_vartime,
       ec_multi_scalar_mul

type ECP_TwEdwards*[F] = ECP_TwEdwards_Aff[F] | ECP_TwEdwards_Prj[F]

func generator*[F](g: var ECP_TwEdwards[F]) {.inline.} =
  when g is ECP_TwEdwards_Aff:
    g = F.C.getGenerator()
  else:
    g.fromAffine(F.C.getGenerator())
