# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  # Internals
  ../constantine/config/[type_fp, curves],
  ../constantine/elliptic/ec_shortweierstrass_projective,
  # Test utilities
  ./t_ec_template

const
  Iters = 1

run_EC_addition_tests(
    ec = ECP_ShortW_Proj[Fp[BN254_Snarks], NotOnTwist],
    Iters = Iters,
    moduleName = "test_ec_shortweierstrass_projective_g1_add_double_" & $BN254_Snarks
  )

run_EC_addition_tests(
    ec = ECP_ShortW_Proj[Fp[BLS12_381], NotOnTwist],
    Iters = Iters,
    moduleName = "test_ec_shortweierstrass_projective_g1_add_double_" & $BLS12_381
  )

run_EC_addition_tests(
    ec = ECP_ShortW_Proj[Fp[BLS12_377], NotOnTwist],
    Iters = Iters,
    moduleName = "test_ec_shortweierstrass_projective_g1_add_double_" & $BLS12_377
  )

run_EC_addition_tests(
    ec = ECP_ShortW_Proj[Fp[BW6_761], NotOnTwist],
    Iters = Iters,
    moduleName = "test_ec_shortweierstrass_projective_g1_add_double_" & $BW6_761
  )
