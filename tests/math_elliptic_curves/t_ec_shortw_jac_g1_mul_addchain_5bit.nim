# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  std/[times],
  constantine/named/algebras,
  constantine/math/elliptic/ec_shortweierstrass_jacobian,
  ./t_ec_template

run_EC_mul_addchain_5bit_tests(
  ec = EC_ShortW_Jac[Fp[BN254_Snarks], G1],
  moduleName = "test_ec_shortw_jac_g1_mul_addchain_5bit_" & $BN254_Snarks
)