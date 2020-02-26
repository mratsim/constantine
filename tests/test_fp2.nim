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

const Iters = 128

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
  test "Fp2 '1' coordinates in canonical domain":
    template test(C: static Curve) =
      block:
        proc testInstance() =
          let oneFp2 = block:
            var O{.noInit.}: Fp2[C]
            O.setOne()
            O
          let oneBig = block:
            var O{.noInit.}: typeof(C.Mod.mres)
            O.setOne()
            O

          var r: typeof(C.Mod.mres)
          r.redc(oneFp2.c0.mres, C.Mod.mres, C.getNegInvModWord())

          check:
            bool(r == oneBig)
            bool(oneFp2.c1.mres.isZero())

    test(BN254)
    test(BLS12_381)
    test(P256)
    test(Secp256k1)

  test "Squaring 1 returns 1":
    template test(C: static Curve) =
      block:
        proc testInstance() =
          let One = block:
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

          for _ in 0 ..< Iters:
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
    test(BN254):
      r.prod(x, One)
      check: bool(r == x)
    test(BN254):
      r.prod(One, x)
      check: bool(r == x)
    test(BLS12_381):
      r.prod(x, Zero)
      check: bool(r == Zero)
    test(BLS12_381):
      r.prod(Zero, x)
      check: bool(r == Zero)
    test(BLS12_381):
      r.prod(x, One)
      check: bool(r == x)
    test(BLS12_381):
      r.prod(One, x)
      check: bool(r == x)
    test(P256):
      r.prod(x, Zero)
      check: bool(r == Zero)
    test(P256):
      r.prod(Zero, x)
      check: bool(r == Zero)
    test(P256):
      r.prod(x, One)
      check: bool(r == x)
    test(P256):
      r.prod(One, x)
      check: bool(r == x)
    test(Secp256k1):
      r.prod(x, Zero)
      check: bool(r == Zero)
    test(Secp256k1):
      r.prod(Zero, x)
      check: bool(r == Zero)
    test(Secp256k1):
      r.prod(x, One)
      check: bool(r == x)
    test(Secp256k1):
      r.prod(One, x)
      check: bool(r == x)

  test "𝔽p2 = 𝔽p[𝑖] addition is associative and commutative":
    proc abelianGroup(curve: static Curve) =
      for _ in 0 ..< Iters:
        let a = rng.random(Fp2[curve])
        let b = rng.random(Fp2[curve])
        let c = rng.random(Fp2[curve])

        var tmp1{.noInit.}, tmp2{.noInit.}: Fp2[curve]

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

    abelianGroup(BN254)
    abelianGroup(BLS12_381)
    abelianGroup(Secp256k1)
    abelianGroup(P256)

  test "𝔽p2 = 𝔽p[𝑖] multiplication is associative and commutative":
    proc commutativeRing(curve: static Curve) =
      for _ in 0 ..< Iters:
        let a = rng.random(Fp2[curve])
        let b = rng.random(Fp2[curve])
        let c = rng.random(Fp2[curve])

        var tmp1{.noInit.}, tmp2{.noInit.}: Fp2[curve]

        # r0 = (a * b) * c
        tmp1.prod(a, b)
        tmp2.prod(tmp1, c)
        let r0 = tmp2

        # r1 = a * (b * c)
        tmp1.prod(b, c)
        tmp2.prod(a, tmp1)
        let r1 = tmp2

        # r2 = (a * c) * b
        tmp1.prod(a, c)
        tmp2.prod(tmp1, b)
        let r2 = tmp2

        # r3 = a * (c * b)
        tmp1.prod(c, b)
        tmp2.prod(a, tmp1)
        let r3 = tmp2

        # r4 = (c * a) * b
        tmp1.prod(c, a)
        tmp2.prod(tmp1, b)
        let r4 = tmp2

        # ...

        check:
          bool(r0 == r1)
          bool(r0 == r2)
          bool(r0 == r3)
          bool(r0 == r4)

    commutativeRing(BN254)
    commutativeRing(BLS12_381)
    commutativeRing(Secp256k1)
    commutativeRing(P256)
