# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  # Internals
  constantine/named/algebras,
  constantine/math/elliptic/[ec_shortweierstrass_jacobian, ec_shortweierstrass_projective],
  constantine/math/extension_fields,
  # Test utilities
  ./t_ec_template

const
  Iters = 8

run_EC_conversion_failures(
  moduleName = "test_ec_conversion_fuzzing_failures"
)

run_EC_affine_conversion(
    ec = EC_ShortW_Jac[Fp[BN254_Snarks], G1],
    Iters = Iters,
    moduleName = "test_ec_conversion_shortw_affine_jacobian_g1_" & $BN254_Snarks
  )
run_EC_affine_conversion(
    ec = EC_ShortW_Prj[Fp[BN254_Snarks], G1],
    Iters = Iters,
    moduleName = "test_ec_conversion_shortw_affine_projective_g1_" & $BN254_Snarks
  )
run_EC_affine_conversion(
    ec = EC_ShortW_Jac[Fp2[BN254_Snarks], G2],
    Iters = Iters,
    moduleName = "test_ec_conversion_shortw_affine_jacobian_g2_" & $BN254_Snarks
  )
run_EC_affine_conversion(
    ec = EC_ShortW_Prj[Fp2[BN254_Snarks], G2],
    Iters = Iters,
    moduleName = "test_ec_conversion_shortw_affine_projective_g2_" & $BN254_Snarks
  )
run_EC_affine_conversion(
    ec = EC_ShortW_Jac[Fp[BLS12_381], G1],
    Iters = Iters,
    moduleName = "test_ec_conversion_shortw_affine_jacobian_g1_" & $BLS12_381
  )
run_EC_affine_conversion(
    ec = EC_ShortW_Prj[Fp[BLS12_381], G1],
    Iters = Iters,
    moduleName = "test_ec_conversion_shortw_affine_projective_g1_" & $BLS12_381
  )
run_EC_affine_conversion(
    ec = EC_ShortW_Jac[Fp2[BLS12_381], G2],
    Iters = Iters,
    moduleName = "test_ec_conversion_shortw_affine_jacobian_g2_" & $BLS12_381
  )
run_EC_affine_conversion(
    ec = EC_ShortW_Prj[Fp2[BLS12_381], G2],
    Iters = Iters,
    moduleName = "test_ec_conversion_shortw_affine_projective_g2_" & $BLS12_381
  )
