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
  ../constantine/elliptic/ec_shortweierstrass_jacobian,
  ../constantine/elliptic/ec_shortweierstrass_projective,
  # Test utilities
  ./t_ec_sage_template

# When ECP_ShortW_Aff[Fp[Foo], NotOnTwist]
# and ECP_ShortW_Aff[Fp[Foo], OnTwist]
# are generated in the same file (i.e. twists and base curve are both on Fp)
# this creates bad codegen, in the C code, the `value`parameter gets the wrong type
# TODO: upstream

# run_scalar_mul_test_vs_sage(
#   ECP_ShortW_Proj[Fp[BW6_761], NotOnTwist],
#   "t_ec_sage_bw6_761_g1_projective"
# )

# run_scalar_mul_test_vs_sage(
#   ECP_ShortW_Jac[Fp[BW6_761], NotOnTwist],
#   "t_ec_sage_bw6_761_g1_jacobian"
# )

run_scalar_mul_test_vs_sage(
  ECP_ShortW_Proj[Fp[BW6_761], OnTwist],
  "t_ec_sage_bw6_761_g2_projective"
)

run_scalar_mul_test_vs_sage(
  ECP_ShortW_Jac[Fp[BW6_761], OnTwist],
  "t_ec_sage_bw6_761_g2_jacobian"
)
