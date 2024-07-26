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
  constantine/math/elliptic/ec_shortweierstrass_jacobian_extended,
  constantine/math/arithmetic,
  # Test utilities
  ./t_ec_template

const
  Iters = 6

run_EC_mixed_add_impl(
    ec = EC_ShortW_JacExt[Fp[BN254_Snarks], G1],
    Iters = Iters,
    moduleName = "test_ec_shortweierstrass_jacobian_extendedmixed_add_" & $BN254_Snarks
  )

run_EC_mixed_add_impl(
    ec = EC_ShortW_JacExt[Fp[Secp256k1], G1],
    Iters = Iters,
    moduleName = "test_ec_shortweierstrass_jacobian_extendedmixed_add_" & $Secp256k1
  )

run_EC_mixed_add_impl(
    ec = EC_ShortW_JacExt[Fp[BLS12_381], G1],
    Iters = Iters,
    moduleName = "test_ec_shortweierstrass_jacobian_extendedmixed_add_" & $BLS12_381
  )

run_EC_mixed_add_impl(
    ec = EC_ShortW_JacExt[Fp[BLS12_377], G1],
    Iters = Iters,
    moduleName = "test_ec_shortweierstrass_jacobian_extendedmixed_add_" & $BLS12_377
  )

run_EC_mixed_add_impl(
    ec = EC_ShortW_JacExt[Fp[BW6_761], G1],
    Iters = Iters,
    moduleName = "test_ec_shortweierstrass_jacobian_extendedmixed_add_" & $BW6_761
  )

run_EC_mixed_add_impl(
    ec = EC_ShortW_JacExt[Fp[Pallas], G1],
    Iters = Iters,
    moduleName = "test_ec_shortweierstrass_jacobian_extendedmixed_add_" & $Pallas
  )

run_EC_mixed_add_impl(
    ec = EC_ShortW_JacExt[Fp[Vesta], G1],
    Iters = Iters,
    moduleName = "test_ec_shortweierstrass_jacobian_extendedmixed_add_" & $Vesta
  )
