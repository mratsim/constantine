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
  ../constantine/tower_field_extensions/[abelian_groups, fp2_complex],
  ../constantine/config/[common, curves],
  ../constantine/arithmetic/bigints_checked,
  # Test utilities
  ./prng

const Iters = 1

var rng: RngState
let seed = uint32(getTime().toUnix() and (1'i64 shl 32 - 1)) # unixTime mod 2^32
rng.seed(seed)
echo "test_fp2 xoshiro512** seed: ", seed

# Import: wrap in field element tests in small procedures
#         otherwise they will become globals,
#         and will create binary size issues.
#         Also due to Nim stack scanning,
#         having too many elements on the stack (a couple kB)
#         will significantly slow down testing (100x is possible)

suite "𝔽p2 = 𝔽p[𝑖] (irreducible polynomial x²+1)":
  test "Squaring 1 returns 1":
    template test(C: static Curve) =
      block:
        proc testInstance() =
          let One {.inject.} = block:
            var O{.noInit.}: Fp2[C]
            O.setOne()
            O
          block:
            var r{.noinit.}: Fp2[C]
            r.square(One)
            check: bool(r == One)
          block:
            var r{.noinit.}: Fp2[C]
            r.prod(One, One)
            check: bool(r == One)

        testInstance()

    test(BN254)
    test(BLS12_381)
    test(P256)
    test(Secp256k1)

  test "Multiplication by 0 and 1":
    template test(C: static Curve, body: untyped) =
      block:
        proc testInstance() =
          let Zero {.inject.} = block:
            var Z{.noInit.}: Fp2[C]
            Z.setZero()
            Z
          let One {.inject.} = block:
            var O{.noInit.}: Fp2[C]
            O.setOne()
            O

          for i in 0 ..< Iters:
            let x {.inject.} = rng.random(Fp2[C])
            var r{.noinit, inject.}: Fp2[C]
            body

        testInstance()

    test(BN254):
      r.prod(x, Zero)
      check: bool(r == Zero)
    test(BN254):
      r.prod(Zero, x)
      check: bool(r == Zero)
    # test(BN254):
    #   r.prod(x, One)
    #   echo "r: ", r
    #   echo "x: ", x
    #   check: bool(r == x)
    # test(BN254):
    #   r.prod(One, x)
    #   echo "r: ", r
    #   echo "x: ", x
    #   check: bool(r == x)
    test(BLS12_381):
      r.prod(x, Zero)
      check: bool(r == Zero)
    test(BLS12_381):
      r.prod(Zero, x)
      check: bool(r == Zero)
    # test(BLS12_381):
    #   r.prod(x, One)
    #   check: bool(r == x)
    # test(BLS12_381):
    #   r.prod(One, x)
    #   check: bool(r == x)
    test(P256):
      r.prod(x, Zero)
      check: bool(r == Zero)
    test(P256):
      r.prod(Zero, x)
      check: bool(r == Zero)
    # test(P256):
    #   r.prod(x, One)
    #   check: bool(r == x)
    # test(P256):
    #   r.prod(One, x)
    #   check: bool(r == x)
    test(Secp256k1):
      r.prod(x, Zero)
      check: bool(r == Zero)
    test(Secp256k1):
      r.prod(Zero, x)
      check: bool(r == Zero)
    # test(Secp256k1):
    #   r.prod(x, One)
    #   check: bool(r == x)
    # test(Secp256k1):
    #   r.prod(One, x)
    #   check: bool(r == x)
