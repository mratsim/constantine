# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  # Internals
  ../../constantine/backend/config/[type_ff, curves],
  ../../constantine/backend/towers,
  ../../constantine/backend/elliptic/ec_shortweierstrass_jacobian,
  ../../constantine/backend/elliptic/ec_shortweierstrass_projective,
  # Test utilities
  ./t_ec_sage_template

run_scalar_mul_test_vs_sage(
  ECP_ShortW_Prj[Fp[BLS12_377], G1],
  "t_ec_sage_bls12_377_g1_projective"
)

run_scalar_mul_test_vs_sage(
  ECP_ShortW_Jac[Fp[BLS12_377], G1],
  "t_ec_sage_bls12_377_g1_jacobian"
)

run_scalar_mul_test_vs_sage(
  ECP_ShortW_Prj[Fp2[BLS12_377], G2],
  "t_ec_sage_bls12_377_g2_projective"
)

run_scalar_mul_test_vs_sage(
  ECP_ShortW_Jac[Fp2[BLS12_377], G2],
  "t_ec_sage_bls12_377_g2_jacobian"
)
