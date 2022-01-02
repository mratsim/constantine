# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  # Internals
  ../constantine/config/[type_ff, curves],
  ../constantine/elliptic/ec_shortweierstrass_projective,
  ../constantine/towers,
  # Test utilities
  ./t_ec_template

const
  Iters = 12
  ItersMul = Iters div 4

run_EC_subgroups_cofactors_impl(
    ec = ECP_ShortW_Prj[Fp[BN254_Nogami], G1],
    ItersMul = ItersMul,
    moduleName = "test_ec_subgroups_g1_" & $BN254_Nogami
  )

run_EC_subgroups_cofactors_impl(
    ec = ECP_ShortW_Prj[Fp2[BN254_Nogami], G2],
    ItersMul = ItersMul,
    moduleName = "test_ec_subgroups_g2_" & $BN254_Nogami
  )