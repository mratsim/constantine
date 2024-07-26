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
  constantine/named/algebras,
  constantine/math/io/io_fields,
  constantine/math/elliptic/[ec_shortweierstrass_affine, ec_shortweierstrass_projective, ec_scalar_mul],
  # Test utilities
  helpers/prng_unsafe,
  constantine/math/elliptic/ec_scalar_mul_vartime,
  ./t_ec_template

const
  Iters = 8
  ItersMul = Iters div 4

run_EC_mul_sanity_tests(
    ec = EC_ShortW_Prj[Fp[BN254_Snarks], G1],
    ItersMul = ItersMul,
    moduleName = "test_ec_shortweierstrass_projective_g1_mul_sanity_" & $BN254_Snarks
  )

suite "Order checks on BN254_Snarks":
  test "EC mul [Order]P == Inf":
    var rng: RngState
    let seed = uint32(getTime().toUnix() and (1'i64 shl 32 - 1)) # unixTime mod 2^32
    rng.seed(seed)
    echo "test_ec_shortweierstrass_projective_g1_mul_sanity_extra_curve_order_mul_sanity xoshiro512** seed: ", seed

    proc test(EC: typedesc, bits: static int, randZ: static bool) =
      for _ in 0 ..< ItersMul:
        when randZ:
          let a = rng.random_unsafe_with_randZ(EC)
        else:
          let a = rng.random_unsafe(EC)

        let exponent = Fr[EC.F].getModulus()

        var
          impl = a
          reference = a

        impl.scalarMulGeneric(exponent)
        reference.scalarMul_doubleAdd_vartime(exponent)

        check:
          bool(impl.isNeutral())
          bool(reference.isNeutral())

    test(EC_ShortW_Prj[Fp[BN254_Snarks], G1], bits = BN254_Snarks.bits(), randZ = false)
    test(EC_ShortW_Prj[Fp[BN254_Snarks], G1], bits = BN254_Snarks.bits(), randZ = true)

  test "Not a point on the curve / not a square - #67":
    var ax, ay: Fp[BN254_Snarks]
    ax.fromHex"0x2a74c9ca553cd5f3437b41e77ca0c8cc77567a7eca5e7debc55b146b0bee324b"
    ay.curve_eq_rhs(ax, G1)

    check:
      bool not ay.isSquare()
      bool not ay.sqrt_if_square()

run_EC_mul_sanity_tests(
    ec = EC_ShortW_Prj[Fp[Secp256k1], G1],
    ItersMul = ItersMul,
    moduleName = "test_ec_shortweierstrass_projective_g1_mul_sanity_" & $Secp256k1
  )

run_EC_mul_sanity_tests(
    ec = EC_ShortW_Prj[Fp[BLS12_381], G1],
    ItersMul = ItersMul,
    moduleName = "test_ec_shortweierstrass_projective_g1_mul_sanity_" & $BLS12_381
  )

run_EC_mul_sanity_tests(
    ec = EC_ShortW_Prj[Fp[BLS12_377], G1],
    ItersMul = ItersMul,
    moduleName = "test_ec_shortweierstrass_projective_g1_mul_sanity_" & $BLS12_377
  )

run_EC_mul_sanity_tests(
    ec = EC_ShortW_Prj[Fp[BW6_761], G1],
    ItersMul = ItersMul,
    moduleName = "test_ec_shortweierstrass_projective_g1_mul_sanity_" & $BW6_761
  )

run_EC_mul_sanity_tests(
    ec = EC_ShortW_Prj[Fp[Pallas], G1],
    ItersMul = ItersMul,
    moduleName = "test_ec_shortweierstrass_projective_g1_mul_sanity_" & $Pallas
  )

run_EC_mul_sanity_tests(
    ec = EC_ShortW_Prj[Fp[Vesta], G1],
    ItersMul = ItersMul,
    moduleName = "test_ec_shortweierstrass_projective_g1_mul_sanity_" & $Vesta
  )
