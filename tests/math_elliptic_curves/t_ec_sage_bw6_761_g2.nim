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
  constantine/math/ec_shortweierstrass,
  # Test utilities
  ./t_ec_sage_template

# When EC_ShortW_Aff[Fp[Foo], G1]
# and EC_ShortW_Aff[Fp[Foo], G2]
# are generated in the same file (i.e. twists and base curve are both on Fp)
# this creates bad codegen, in the C code, the `value`parameter gets the wrong type
# TODO: upstream

staticFor(bits, [Fr[BW6_761].bits()]):
  # run_scalar_mul_test_vs_sage(
  #   EC_ShortW_Prj[Fp[BW6_761], G1], bits,
  #   "t_ec_sage_bw6_761_g1_projective"
  # )

  # run_scalar_mul_test_vs_sage(
  #   EC_ShortW_Jac[Fp[BW6_761], G1], bits,
  #   "t_ec_sage_bw6_761_g1_jacobian"
  # )

  run_scalar_mul_test_vs_sage(
    EC_ShortW_Prj[Fp[BW6_761], G2], bits,
    "t_ec_sage_bw6_761_g2_projective"
  )

  run_scalar_mul_test_vs_sage(
    EC_ShortW_Jac[Fp[BW6_761], G2], bits,
    "t_ec_sage_bw6_761_g2_jacobian"
  )
