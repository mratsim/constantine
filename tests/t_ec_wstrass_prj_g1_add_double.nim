# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  # Standard library
  std/[unittest, times],
  # Internals
  ../constantine/config/[common, curves],
  ../constantine/arithmetic,
  ../constantine/io/io_bigints,
  ../constantine/elliptic/[ec_weierstrass_affine, ec_weierstrass_projective],
  # Test utilities
  ../helpers/prng_unsafe,
  ./t_ec_template

const
  Iters = 8

run_EC_addition_tests(
    ec = ECP_SWei_Proj[Fp[BN254_Snarks]],
    Iters = Iters,
    moduleName = "test_ec_weierstrass_projective_g1_add_double_" & $BN254_Snarks
  )

run_EC_addition_tests(
    ec = ECP_SWei_Proj[Fp[BLS12_381]],
    Iters = Iters,
    moduleName = "test_ec_weierstrass_projective_g1_add_double_" & $BLS12_381
  )

run_EC_addition_tests(
    ec = ECP_SWei_Proj[Fp[BLS12_377]],
    Iters = Iters,
    moduleName = "test_ec_weierstrass_projective_g1_add_double_" & $BLS12_377
  )
