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
  ../../constantine/backend/elliptic/ec_twistededwards_projective,
  # Test utilities
  ./t_ec_template

const
  Iters = 8

run_EC_addition_tests(
    ec = ECP_TwEdwards_Prj[Fp[Curve25519]],
    Iters = Iters,
    moduleName = "test_ec_twistededwards_projective_add_double_" & $Curve25519
  )

run_EC_addition_tests(
    ec = ECP_TwEdwards_Prj[Fp[Jubjub]],
    Iters = Iters,
    moduleName = "test_ec_twistededwards_projective_add_double_" & $Jubjub
  )

run_EC_addition_tests(
    ec = ECP_TwEdwards_Prj[Fp[Bandersnatch]],
    Iters = Iters,
    moduleName = "test_ec_twistededwards_projective_add_double_" & $Bandersnatch
  )