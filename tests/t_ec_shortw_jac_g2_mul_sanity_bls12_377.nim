# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  # Internals
  ../constantine/config/curves,
  ../constantine/elliptic/ec_shortweierstrass_jacobian,
  ../constantine/towers,
  # Test utilities
  ./t_ec_template
  
const
  Iters = 12
  ItersMul = Iters div 4

run_EC_mul_sanity_tests(
    ec = ECP_ShortW_Jac[Fp2[BLS12_377]],
    ItersMul = ItersMul,
    moduleName = "test_ec_shortweierstrass_jacobian_g2_mul_sanity_" & $BLS12_377
  )

# TODO: the order on E'(Fp2) for BLS curves is ??? with r the order on E(Fp)
#
# test "EC mul [Order]P == Inf":
#   var rng: RngState
#   let seed = uint32(getTime().toUnix() and (1'i64 shl 32 - 1)) # unixTime mod 2^32
#   rng.seed(seed)
#   echo "test_ec_shortweierstrass_jacobian_g1_mul_sanity_extra_curve_order_mul_sanity xoshiro512** seed: ", seed
#
#   proc test(EC: typedesc, bits: static int, randZ: static bool) =
#     for _ in 0 ..< ItersMul:
#       when randZ:
#         let a = rng.random_unsafe_with_randZ(EC)
#       else:
#         let a = rng.random_unsafe(EC)
#
#       let exponent = F.C.getCurveOrder()
#
#       var
#         impl = a
#         reference = a
#
#       impl.scalarMulGeneric(exponent)
#       reference.unsafe_ECmul_double_add(exponent)
#
#       check:
#         bool(impl.isInf())
#         bool(reference.isInf())
#
#   test(ECP_ShortW_Jac[Fp2[BLS12_377]], bits = BLS12_377.getCurveOrderBitwidth(), randZ = false)
#   test(ECP_ShortW_Jac[Fp2[BLS12_377]], bits = BLS12_377.getCurveOrderBitwidth(), randZ = true)
