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
  ../constantine/io/io_bigints,
  ../constantine/elliptic/[ec_weierstrass_affine, ec_weierstrass_projective, ec_scalar_mul],
  # Test utilities
  ../helpers/prng_unsafe,
  ./support/ec_reference_scalar_mult

const
  Iters = 128
  ItersMul = Iters div 4

var rng: RngState
let seed = uint32(getTime().toUnix() and (1'i64 shl 32 - 1)) # unixTime mod 2^32
rng.seed(seed)
echo "test_ec_weierstrass_projective_g1_distributive xoshiro512** seed: ", seed

# Import: wrap in elliptic curve tests in small procedures
#         otherwise they will become globals,
#         and will create binary size issues.
#         Also due to Nim stack scanning,
#         having too many elements on the stack (a couple kB)
#         will significantly slow down testing (100x is possible)

suite "Elliptic curve in Short Weierstrass form y² = x³ + a x + b with projective coordinates (X, Y, Z): Y²Z = X³ + aXZ² + bZ³ i.e. X = xZ, Y = yZ":

  const BN254_Snarks_order_bits = BN254_Snarks.getCurveOrderBitwidth()
  const BLS12_381_order_bits = BLS12_381.getCurveOrderBitwidth()

  test "EC mul is distributive over EC add":
    proc test(F: typedesc, bits: static int, randZ: static bool) =
      for _ in 0 ..< ItersMul:
        when randZ:
          let a = rng.random_unsafe_with_randZ(ECP_SWei_Proj[F])
          let b = rng.random_unsafe_with_randZ(ECP_SWei_Proj[F])
        else:
          let a = rng.random_unsafe(ECP_SWei_Proj[F])
          let b = rng.random_unsafe_with_randZ(ECP_SWei_Proj[F])

        let exponent = rng.random_unsafe(BigInt[bits])
        var exponentCanonical{.noInit.}: array[(bits+7) div 8, byte]
        exponentCanonical.exportRawUint(exponent, bigEndian)

        # [k](a + b) - Factorized
        var
          fImpl{.noInit.}: ECP_SWei_Proj[F]
          fReference{.noInit.}: ECP_SWei_Proj[F]
          scratchSpace{.noInit.}: array[1 shl 4, ECP_SWei_Proj[F]]

        fImpl.sum(a, b)
        fReference.sum(a, b)

        fImpl.scalarMulGeneric(exponentCanonical, scratchSpace)
        fReference.unsafe_ECmul_double_add(exponentCanonical)

        # [k]a + [k]b - Distributed
        var kaImpl = a
        var kaRef = a

        kaImpl.scalarMulGeneric(exponentCanonical, scratchSpace)
        kaRef.unsafe_ECmul_double_add(exponentCanonical)

        var kbImpl = b
        var kbRef = b

        kbImpl.scalarMulGeneric(exponentCanonical, scratchSpace)
        kbRef.unsafe_ECmul_double_add(exponentCanonical)

        var kakbImpl{.noInit.}, kakbRef{.noInit.}: ECP_SWei_Proj[F]
        kakbImpl.sum(kaImpl, kbImpl)
        kakbRef.sum(kaRef, kbRef)

        check:
          bool(fImpl == kakbImpl)
          bool(fReference == kakbRef)
          bool(fImpl == fReference)

    test(Fp[BN254_Snarks], bits = BN254_Snarks_order_bits, randZ = false)
    test(Fp[BN254_Snarks], bits = BN254_Snarks_order_bits, randZ = true)
    test(Fp[BLS12_381], bits = BLS12_381_order_bits, randZ = false)
    test(Fp[BLS12_381], bits = BLS12_381_order_bits, randZ = true)
