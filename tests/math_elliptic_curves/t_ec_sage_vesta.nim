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
  constantine/math/extension_fields,
  constantine/math/ec_shortweierstrass,
  # Test utilities
  ./t_ec_sage_template

staticFor(bits, [Fr[Vesta].bits()]):
  run_scalar_mul_test_vs_sage(
    EC_ShortW_Prj[Fp[Vesta], G1], bits,
    "t_ec_sage_vesta_g1_projective"
  )

  run_scalar_mul_test_vs_sage(
    EC_ShortW_Jac[Fp[Vesta], G1], bits,
    "t_ec_sage_vesta_g1_jacobian"
  )
