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
  ../constantine/towers,
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

suite "𝔽p12 = 𝔽p6[w] (irreducible polynomial w² - γ)":
  test "Comparison sanity checks":
    proc test(C: static Curve) =
      var z, o {.noInit.}: Fp12[C]

      z.setZero()
      o.setOne()

      check: not bool(z == o)

    test(BN254_Snarks)
    test(BLS12_381)

  test "Addition, substraction negation are consistent":
    proc test(C: static Curve) =
      # Try to exercise all code paths for in-place/out-of-place add/sum/sub/diff/double/neg
      # (1 - (-a) - b + (-a) - 2a) + (2a + 2b + (-b))  == 1
      var accum {.noInit.}, One {.noInit.}, a{.noInit.}, na{.noInit.}, b{.noInit.}, nb{.noInit.}, a2 {.noInit.}, b2 {.noInit.}: Fp12[C]

      One.setOne()
      a = rng.random(Fp12[C])
      a2 = a
      a2.double()
      na.neg(a)

      b = rng.random(Fp12[C])
      b2.double(b)
      nb.neg(b)

      accum.diff(One, na)
      accum -= b
      accum += na
      accum -= a2

      var t{.noInit.}: Fp12[C]
      t.sum(a2, b2)
      t += nb

      accum += t
      check: bool accum.isOne()

    # test(BN254_Nogami)
    test(BN254_Snarks)
    test(BLS12_377)
    test(BLS12_381)
    # test(BN446)
    # test(FKM12_447)
    # test(BLS12_461)
    # test(BN462)

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

    # test(BN254_Nogami)
    test(BN254_Snarks)
    test(BLS12_377)
    test(BLS12_381)
    # test(BN446)
    # test(FKM12_447)
    # test(BLS12_461)
    # test(BN462)

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

    # test(BN254_Nogami)
    test(BN254_Snarks)
    test(BLS12_377)
    test(BLS12_381)
    # test(BN446)
    # test(FKM12_447)
    # test(BLS12_461)
    # test(BN462)

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

    # test(BN254_Nogami)
    test(BN254_Snarks)
    test(BLS12_377)
    test(BLS12_381)
    # test(BN446)
    # test(FKM12_447)
    # test(BLS12_461)
    # test(BN462)

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

    # test(BN254_Nogami)
    test(BN254_Snarks)
    test(BLS12_377)
    test(BLS12_381)
    # test(BN446)
    # test(FKM12_447)
    # test(BLS12_461)
    # test(BN462)

  test "Multiplication by 0 and 1":
    template test(C: static Curve, body: untyped) =
      block:
        proc testInstance() =
          let Zero {.inject, used.} = block:
            var Z{.noInit.}: Fp12[C]
            Z.setZero()
            Z
          let One {.inject, used.} = block:
            var O{.noInit.}: Fp12[C]
            O.setOne()
            O

          for _ in 0 ..< Iters:
            let x {.inject.} = rng.random(Fp12[C])
            var r{.noinit, inject.}: Fp12[C]
            body

        testInstance()

    # test(BN254_Nogami):
    #   r.prod(x, Zero)
    #   check: bool(r == Zero)
    # test(BN254_Nogami):
    #   r.prod(Zero, x)
    #   check: bool(r == Zero)
    # test(BN254_Nogami):
    #   r.prod(x, One)
    #   check: bool(r == x)
    # test(BN254_Nogami):
    #   r.prod(One, x)
    #   check: bool(r == x)
    test(BN254_Snarks):
      r.prod(x, Zero)
      check: bool(r == Zero)
    test(BN254_Snarks):
      r.prod(Zero, x)
      check: bool(r == Zero)
    test(BN254_Snarks):
      r.prod(x, One)
      check: bool(r == x)
    test(BN254_Snarks):
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
    # test(BN462):
    #   r.prod(x, Zero)
    #   check: bool(r == Zero)
    # test(BN462):
    #   r.prod(Zero, x)
    #   check: bool(r == Zero)
    # test(BN462):
    #   r.prod(x, One)
    #   check: bool(r == x)
    # test(BN462):
    #   r.prod(One, x)
    #   check: bool(r == x)

  test "Multiplication and Squaring are consistent":
    template test(C: static Curve) =
      block:
        proc testInstance() =
          for _ in 0 ..< Iters:
            let a = rng.random(Fp12[C])
            var rMul{.noInit.}, rSqr{.noInit.}: Fp12[C]

            rMul.prod(a, a)
            rSqr.square(a)

            check: bool(rMul == rSqr)

        testInstance()

    # test(BN254_Nogami)
    test(BN254_Snarks)
    test(BLS12_377)
    test(BLS12_381)
    # test(BN446)
    # test(FKM12_447)
    # test(BLS12_461)
    # test(BN462)

  test "Squaring the opposite gives the same result":
    template test(C: static Curve) =
      block:
        proc testInstance() =
          for _ in 0 ..< Iters:
            let a = rng.random(Fp12[C])
            var na{.noInit.}: Fp12[C]
            na.neg(a)

            var rSqr{.noInit.}, rNegSqr{.noInit.}: Fp12[C]

            rSqr.square(a)
            rNegSqr.square(na)

            check: bool(rSqr == rNegSqr)

        testInstance()

    # test(BN254_Nogami)
    test(BN254_Snarks)
    test(BLS12_377)
    test(BLS12_381)
    # test(BN446)
    # test(FKM12_447)
    # test(BLS12_461)
    # test(BN462)

  test "Multiplication and Addition/Substraction are consistent":
    template test(C: static Curve) =
      block:
        proc testInstance() =
          for _ in 0 ..< Iters:
            let factor = rand(-30..30)

            let a = rng.random(Fp12[C])

            if factor == 0: continue

            var sum{.noInit.}, one{.noInit.}, f{.noInit.}: Fp12[C]
            one.setOne()

            if factor < 0:
              sum.neg(a)
              f.neg(one)
              for i in 1 ..< -factor:
                sum -= a
                f -= one
            else:
              sum = a
              f = one
              for i in 1 ..< factor:
                sum += a
                f += one

            var r{.noInit.}: Fp12[C]

            r.prod(a, f)

            check: bool(r == sum)

        testInstance()

    # test(BN254_Nogami)
    test(BN254_Snarks)
    test(BLS12_377)
    test(BLS12_381)
    # test(BN446)
    # test(FKM12_447)
    # test(BLS12_461)
    # test(BN462)

  test "Addition is associative and commutative":
    proc abelianGroup(curve: static Curve) =
      for _ in 0 ..< Iters:
        let a = rng.random(Fp12[curve])
        let b = rng.random(Fp12[curve])
        let c = rng.random(Fp12[curve])

        var tmp1{.noInit.}, tmp2{.noInit.}: Fp12[curve]

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

    # abelianGroup(BN254_Nogami)
    abelianGroup(BN254_Snarks)
    abelianGroup(BLS12_377)
    abelianGroup(BLS12_381)
    # abelianGroup(BN446)
    # abelianGroup(FKM12_447)
    # abelianGroup(BLS12_461)
    # abelianGroup(BN462)

  test "Multiplication is associative and commutative":
    proc commutativeRing(curve: static Curve) =
      for _ in 0 ..< Iters:
        let a = rng.random(Fp12[curve])
        let b = rng.random(Fp12[curve])
        let c = rng.random(Fp12[curve])

        var tmp1{.noInit.}, tmp2{.noInit.}: Fp12[curve]

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

    # commutativeRing(BN254_Nogami)
    commutativeRing(BN254_Snarks)
    commutativeRing(BLS12_377)
    commutativeRing(BLS12_381)
    # commutativeRing(BN446)
    # commutativeRing(FKM12_447)
    # commutativeRing(BLS12_461)
    # commutativeRing(BN462)

  test "Extension field multiplicative inverse":
    proc mulInvOne(curve: static Curve) =
      var one: Fp12[curve]
      one.setOne()

      block: # Inverse of 1 is 1
        var r {.noInit.}: Fp12[curve]
        r.inv(one)
        check: bool(r == one)

      var aInv, r{.noInit.}: Fp12[curve]

      for _ in 0 ..< Iters:
        let a = rng.random(Fp12[curve])

        aInv.inv(a)
        r.prod(a, aInv)
        check: bool(r == one)

        r.prod(aInv, a)
        check: bool(r == one)

    # mulInvOne(BN254_Nogami)
    mulInvOne(BN254_Snarks)
    mulInvOne(BLS12_377)
    mulInvOne(BLS12_381)
    # mulInvOne(BN446)
    # mulInvOne(FKM12_447)
    # mulInvOne(BLS12_461)
    # mulInvOne(BN462)

  test "0 does not have a multiplicative inverse and should return 0 for projective/jacobian => affine coordinates conversion":
    proc test(curve: static Curve) =
      var z: Fp12[curve]
      z.setZero()

      var zInv{.noInit.}: Fp12[curve]

      zInv.inv(z)
      check: bool zInv.isZero()

    # test(BN254_Nogami)
    test(BN254_Snarks)
    test(BLS12_377)
    test(BLS12_381)
    # test(BN446)
    # test(FKM12_447)
    # test(BLS12_461)
    # test(BN462)
