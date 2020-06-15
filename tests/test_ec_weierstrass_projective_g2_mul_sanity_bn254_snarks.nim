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
  ../constantine/towers,
  ../constantine/io/io_bigints,
  ../constantine/elliptic/[ec_weierstrass_affine, ec_weierstrass_projective, ec_scalar_mul],
  # Test utilities
  ../helpers/prng_unsafe,
  ./support/ec_reference_scalar_mult,
  ./test_ec_template

const
  Iters = 128
  ItersMul = Iters div 4

run_EC_mul_sanity_tests(
    ec = ECP_SWei_Proj[Fp2[BN254_Snarks]],
    ItersMul = ItersMul,
    moduleName = "test_ec_weierstrass_projective_g2_mul_sanity_" & $BN254_Snarks
  )

# TODO: the order on E'(Fp2) for BN curve is r∗(2p−r) with r the order on E(Fp)
#
# test "EC mul [Order]P == Inf":
#   var rng: RngState
#   let seed = uint32(getTime().toUnix() and (1'i64 shl 32 - 1)) # unixTime mod 2^32
#   rng.seed(seed)
#   echo "test_ec_weierstrass_projective_g1_mul_sanity_extra_curve_order_mul_sanity xoshiro512** seed: ", seed
#
#   proc test(EC: typedesc, bits: static int, randZ: static bool) =
#     for _ in 0 ..< ItersMul:
#       when randZ:
#         let a = rng.random_unsafe_with_randZ(EC)
#       else:
#         let a = rng.random_unsafe(EC)
#
#       let exponent = F.C.getCurveOrder()
#       var exponentCanonical{.noInit.}: array[(bits+7) div 8, byte]
#       exponentCanonical.exportRawUint(exponent, bigEndian)
#
#       var
#         impl = a
#         reference = a
#         scratchSpace{.noInit.}: array[1 shl 4, EC]
#
#       impl.scalarMulGeneric(exponentCanonical, scratchSpace)
#       reference.unsafe_ECmul_double_add(exponentCanonical)
#
#       check:
#         bool(impl.isInf())
#         bool(reference.isInf())
#
#   test(ECP_SWei_Proj[Fp2[BN254_Snarks]], bits = BN254_Snarks.getCurveOrderBitwidth(), randZ = false)
#   test(ECP_SWei_Proj[Fp2[BN254_Snarks]], bits = BN254_Snarks.getCurveOrderBitwidth(), randZ = true)
