# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  # Internals
  ../../constantine/math/config/curves,
  ../../constantine/math/elliptic/ec_shortweierstrass_jacobian_extended,
  ../../constantine/math/arithmetic,
  # Test utilities
  ./t_ec_template

const numPoints = [1, 2, 8, 16, 128, 1024, 2048, 16384, 32768] # 262144, 1048576]

run_EC_batch_add_impl(
    ec = ECP_ShortW_JacExt[Fp[BN254_Snarks], G1],
    numPoints = numPoints,
    moduleName = "test_ec_shortweierstrass_jacobian_extended_batch_add_" & $BN254_Snarks
  )

run_EC_batch_add_impl(
    ec = ECP_ShortW_JacExt[Fp[BLS12_381], G1],
    numPoints = numPoints,
    moduleName = "test_ec_shortweierstrass_jacobian_extended_batch_add_" & $BLS12_381
  )
