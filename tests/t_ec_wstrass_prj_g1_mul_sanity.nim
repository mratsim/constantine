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
  ../constantine/io/[io_bigints, io_fields, io_ec],
  ../constantine/elliptic/[ec_weierstrass_affine, ec_weierstrass_projective, ec_scalar_mul],
  # Test utilities
  ../helpers/prng_unsafe,
  ./support/ec_reference_scalar_mult,
  ./t_ec_template

const
  Iters = 128
  ItersMul = Iters div 4

run_EC_mul_sanity_tests(
    ec = ECP_SWei_Proj[Fp[BN254_Snarks]],
    ItersMul = ItersMul,
    moduleName = "test_ec_weierstrass_projective_g1_mul_sanity_" & $BN254_Snarks
  )

suite "Order checks on BN254_Snarks":
  test "EC mul [Order]P == Inf":
    var rng: RngState
    let seed = uint32(getTime().toUnix() and (1'i64 shl 32 - 1)) # unixTime mod 2^32
    rng.seed(seed)
    echo "test_ec_weierstrass_projective_g1_mul_sanity_extra_curve_order_mul_sanity xoshiro512** seed: ", seed

    proc test(EC: typedesc, bits: static int, randZ: static bool) =
      for _ in 0 ..< ItersMul:
        when randZ:
          let a = rng.random_unsafe_with_randZ(EC)
        else:
          let a = rng.random_unsafe(EC)

        let exponent = EC.F.C.getCurveOrder()
        var exponentCanonical{.noInit.}: array[(bits+7) div 8, byte]
        exponentCanonical.exportRawUint(exponent, bigEndian)

        var
          impl = a
          reference = a
          scratchSpace{.noInit.}: array[1 shl 4, EC]

        impl.scalarMulGeneric(exponentCanonical, scratchSpace)
        reference.unsafe_ECmul_double_add(exponentCanonical)

        check:
          bool(impl.isInf())
          bool(reference.isInf())

    test(ECP_SWei_Proj[Fp[BN254_Snarks]], bits = BN254_Snarks.getCurveOrderBitwidth(), randZ = false)
    test(ECP_SWei_Proj[Fp[BN254_Snarks]], bits = BN254_Snarks.getCurveOrderBitwidth(), randZ = true)
    # TODO: BLS12 is using a subgroup of order "r" such as r*h = CurveOrder
    #       with h the curve cofactor
    #       instead of the full group
    # test(Fp[BLS12_381], bits = BLS12_381.getCurveOrderBitwidth(), randZ = false)
    # test(Fp[BLS12_381], bits = BLS12_381.getCurveOrderBitwidth(), randZ = true)

  test "Multiplying by order should give infinity - #67":
    var a: ECP_SWei_Proj[Fp[BN254_Snarks]]
    var ax, az: Fp[BN254_Snarks]
    ax.fromHex"0x2a74c9ca553cd5f3437b41e77ca0c8cc77567a7eca5e7debc55b146b0bee324b"
    az.fromHex"0x2ce3f308c2648cf748f9b330d0e1556d7f4889509a9ca6de88c8e101cdf1035b"
    check: bool a.trySetFromCoordsXandZ(ax, az)
    # echo a.toHex()
    # check: bool a.fromHex(
    #   "0x2a74c9ca553cd5f3437b41e77ca0c8cc77567a7eca5e7debc55b146b0bee324b",
    #   "0x1f6254761c0bdfe084eeb4383bed8bd3173091c51409664343eb32fc354b489e"
    # )

    let exponent = BN254_Snarks.getCurveOrder()
    var exponentCanonical{.noInit.}: array[(BN254_Snarks.getCurveOrderBitwidth()+7) div 8, byte]
    exponentCanonical.exportRawUint(exponent, bigEndian)

    var
      impl = a
      reference = a
      scratchSpace{.noInit.}: array[1 shl 4, ECP_SWei_Proj[Fp[BN254_Snarks]]]

    impl.scalarMulGeneric(exponentCanonical, scratchSpace)
    reference.unsafe_ECmul_double_add(exponentCanonical)

    check:
      bool(impl.isInf())
      bool(reference.isInf())


run_EC_mul_sanity_tests(
    ec = ECP_SWei_Proj[Fp[BLS12_381]],
    ItersMul = ItersMul,
    moduleName = "test_ec_weierstrass_projective_g1_mul_sanity_" & $BLS12_381
  )
