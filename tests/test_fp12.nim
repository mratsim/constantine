# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  # Standard library
  unittest, times, random,
  # Internals
  ../constantine/tower_field_extensions/[abelian_groups, fp12_quad_fp6],
  ../constantine/config/[common, curves],
  ../constantine/arithmetic,
  # Test utilities
  ../helpers/prng

const Iters = 128

var rng: RngState
let seed = uint32(getTime().toUnix() and (1'i64 shl 32 - 1)) # unixTime mod 2^32
rng.seed(seed)
echo "test_fp12 xoshiro512** seed: ", seed

# Import: wrap in field element tests in small procedures
#         otherwise they will become globals,
#         and will create binary size issues.
#         Also due to Nim stack scanning,
#         having too many elements on the stack (a couple kB)
#         will significantly slow down testing (100x is possible)

suite "𝔽p12 = 𝔽p6[√∛(1+𝑖)]":
  test "Squaring 1 returns 1":
    template test(C: static Curve) =
      block:
        proc testInstance() =
          let One = block:
            var O{.noInit.}: Fp12[C]
            O.setOne()
            O
          block:
            var r{.noinit.}: Fp12[C]
            r.square(One)
            check: bool(r == One)
          # block:
          #   var r{.noinit.}: Fp12[C]
          #   r.prod(One, One)
          #   check: bool(r == One)

        testInstance()

    test(BN254)
    test(BLS12_377)
    test(BLS12_381)
    test(BN446)
    test(FKM12_447)
    test(BLS12_461)
    test(BN462)

  test "Squaring 2 returns 4":
    template test(C: static Curve) =
      block:
        proc testInstance() =
          let One = block:
            var O{.noInit.}: Fp12[C]
            O.setOne()
            O

          var Two: Fp12[C]
          Two.double(One)

          var Four: Fp12[C]
          Four.double(Two)

          block:
            var r: Fp12[C]
            r.square(Two)

            check: bool(r == Four)
          # block:
          #   var r: Fp12[C]
          #   r.prod(Two, Two)

          #   check: bool(r == Four)

        testInstance()

    test(BN254)
    test(BLS12_377)
    test(BLS12_381)
    test(BN446)
    test(FKM12_447)
    test(BLS12_461)
    test(BN462)

  test "Squaring 3 returns 9":
    template test(C: static Curve) =
      block:
        proc testInstance() =
          let One = block:
            var O{.noInit.}: Fp12[C]
            O.setOne()
            O

          var Three: Fp12[C]
          for _ in 0 ..< 3:
            Three += One

          var Nine: Fp12[C]
          for _ in 0 ..< 9:
            Nine += One

          block:
            var u: Fp12[C]
            u.square(Three)

            check: bool(u == Nine)
          # block:
          #   var u: Fp12[C]
          #   u.prod(Three, Three)

          #   check: bool(u == Nine)

        testInstance()

    test(BN254)
    test(BLS12_377)
    test(BLS12_381)
    test(BN446)
    test(FKM12_447)
    test(BLS12_461)
    test(BN462)

  test "Squaring -3 returns 9":
    template test(C: static Curve) =
      block:
        proc testInstance() =
          let One = block:
            var O{.noInit.}: Fp12[C]
            O.setOne()
            O

          var MinusThree: Fp12[C]
          for _ in 0 ..< 3:
            MinusThree -= One

          var Nine: Fp12[C]
          for _ in 0 ..< 9:
            Nine += One

          block:
            var u: Fp12[C]
            u.square(MinusThree)

            check: bool(u == Nine)
          # block:
          #   var u: Fp12[C]
          #   u.prod(MinusThree, MinusThree)

          #   check: bool(u == Nine)

        testInstance()

    test(BN254)
    test(BLS12_377)
    test(BLS12_381)
    test(BN446)
    test(FKM12_447)
    test(BLS12_461)
    test(BN462)
