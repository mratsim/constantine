# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  # Standard library
  unittest, times,
  # Internals
  ../constantine/config/[common, curves],
  ../constantine/arithmetic,
  ../constantine/elliptic/[ec_weierstrass_affine, ec_weierstrass_projective],
  # Test utilities
  ../helpers/prng_unsafe

const Iters = 128

var rng: RngState
let seed = uint32(getTime().toUnix() and (1'i64 shl 32 - 1)) # unixTime mod 2^32
rng.seed(seed)
echo "test_ec_weierstrass_projective_g1 xoshiro512** seed: ", seed

# Import: wrap in elliptic curve tests in small procedures
#         otherwise they will become globals,
#         and will create binary size issues.
#         Also due to Nim stack scanning,
#         having too many elements on the stack (a couple kB)
#         will significantly slow down testing (100x is possible)

suite "Elliptic curve in Short Weierstrass form y² = x³ + a x + b with projective coordinates (X, Y, Z): Y²Z = X³ + aXZ² + bZ³ i.e. X = xZ, Y = yZ":
  test "The infinity point is the neutral element w.r.t. to EC addition":
    proc test(F: typedesc, randZ: static bool) =
      var inf {.noInit.}: ECP_SWei_Proj[F]
      inf.setInf()
      check: bool inf.isInf()

      for _ in 0 ..< Iters:
        var r{.noInit.}: ECP_SWei_Proj[F]
        when randZ:
          let P = rng.random_unsafe_with_randZ(ECP_SWei_Proj[F])
        else:
          let P = rng.random_unsafe(ECP_SWei_Proj[F])

        r.sum(P, inf)
        check: bool(r == P)

        r.sum(inf, P)
        check: bool(r == P)

    test(Fp[BLS12_381], randZ = false)
    test(Fp[BLS12_381], randZ = true)

  test "Adding opposites gives an infinity point":
    proc test(F: typedesc, randZ: static bool) =
      for _ in 0 ..< Iters:
        var r{.noInit.}: ECP_SWei_Proj[F]
        when randZ:
          let P = rng.random_unsafe_with_randZ(ECP_SWei_Proj[F])
        else:
          let P = rng.random_unsafe(ECP_SWei_Proj[F])
        var Q = P
        Q.neg()

        r.sum(P, Q)
        check: bool r.isInf()

        r.sum(Q, P)
        check: bool r.isInf()

    test(Fp[BLS12_381], randZ = false)
    test(Fp[BLS12_381], randZ = true)

  test "EC add is commutative":
    proc test(F: typedesc, randZ: static bool) =
      for _ in 0 ..< Iters:
        var r0{.noInit.}, r1{.noInit.}: ECP_SWei_Proj[F]
        when randZ:
          let P = rng.random_unsafe_with_randZ(ECP_SWei_Proj[F])
          let Q = rng.random_unsafe_with_randZ(ECP_SWei_Proj[F])
        else:
          let P = rng.random_unsafe(ECP_SWei_Proj[F])
          let Q = rng.random_unsafe(ECP_SWei_Proj[F])

        r0.sum(P, Q)
        r1.sum(Q, P)
        check: bool(r0 == r1)

    test(Fp[BLS12_381], randZ = false)
    test(Fp[BLS12_381], randZ = true)

  test "EC add is associative":
    proc test(F: typedesc, randZ: static bool) =
      for _ in 0 ..< Iters:
        when randZ:
          let a = rng.random_unsafe_with_randZ(ECP_SWei_Proj[F])
          let b = rng.random_unsafe_with_randZ(ECP_SWei_Proj[F])
          let c = rng.random_unsafe_with_randZ(ECP_SWei_Proj[F])
        else:
          let a = rng.random_unsafe(ECP_SWei_Proj[F])
          let b = rng.random_unsafe(ECP_SWei_Proj[F])
          let c = rng.random_unsafe(ECP_SWei_Proj[F])

        var tmp1{.noInit.}, tmp2{.noInit.}: ECP_SWei_Proj[F]

        # r0 = (a + b) + c
        tmp1.sum(a, b)
        tmp2.sum(tmp1, c)
        let r0 = tmp2

        # r1 = a + (b + c)
        tmp1.sum(b, c)
        tmp2.sum(a, tmp1)
        let r1 = tmp2

        # r2 = (a + c) + b
        tmp1.sum(a, c)
        tmp2.sum(tmp1, b)
        let r2 = tmp2

        # r3 = a + (c + b)
        tmp1.sum(c, b)
        tmp2.sum(a, tmp1)
        let r3 = tmp2

        # r4 = (c + a) + b
        tmp1.sum(c, a)
        tmp2.sum(tmp1, b)
        let r4 = tmp2

        # ...

        check:
          bool(r0 == r1)
          bool(r0 == r2)
          bool(r0 == r3)
          bool(r0 == r4)

    test(Fp[BLS12_381], randZ = false)
    test(Fp[BLS12_381], randZ = true)
