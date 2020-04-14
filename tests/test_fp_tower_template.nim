# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

# ############################################################
#
#         Template tests for towered extension fields
#
# ############################################################


import
  # Standard library
  std/[unittest, times],
  # Internals
  ../constantine/towers,
  ../constantine/config/[common, curves],
  ../constantine/arithmetic,
  # Test utilities
  ../helpers/[prng_unsafe, static_for]

template ExtField(degree: static int, curve: static Curve): untyped =
  when degree == 2:
    Fp2[curve]
  elif degree == 6:
    Fp6[curve]
  elif degree == 12:
    Fp12[curve]
  else:
    {.error: "Unconfigured extension degree".}

proc runTowerTests*[N](
      ExtDegree: static int,
      Iters: static int,
      TestCurves: static array[N, Curve],
      moduleName: string,
      testSuiteDesc: string
    ) =

  # Random seed for reproducibility
  var rng: RngState
  let seed = uint32(getTime().toUnix() and (1'i64 shl 32 - 1)) # unixTime mod 2^32
  rng.seed(seed)
  echo moduleName, " xoshiro512** seed: ", seed

  suite testSuiteDesc:
    test "Comparison sanity checks":
      proc test(Field: typedesc) =
        var z, o {.noInit.}: Field

        z.setZero()
        o.setOne()

        check: not bool(z == o)

      staticFor(curve, TestCurves):
        test(ExtField(ExtDegree, curve))

    test "Addition, substraction negation are consistent":
      proc test(Field: typedesc) =
        # Try to exercise all code paths for in-place/out-of-place add/sum/sub/diff/double/neg
        # (1 - (-a) - b + (-a) - 2a) + (2a + 2b + (-b))  == 1
        var accum {.noInit.}, One {.noInit.}, a{.noInit.}, na{.noInit.}, b{.noInit.}, nb{.noInit.}, a2 {.noInit.}, b2 {.noInit.}: Field

        One.setOne()
        a = rng.random_unsafe(Field)
        a2 = a
        a2.double()
        na.neg(a)

        b = rng.random_unsafe(Field)
        b2.double(b)
        nb.neg(b)

        accum.diff(One, na)
        accum -= b
        accum += na
        accum -= a2

        var t{.noInit.}: Field
        t.sum(a2, b2)
        t += nb

        accum += t
        check: bool accum.isOne()

      staticFor(curve, TestCurves):
        test(ExtField(ExtDegree, curve))

    test "Squaring 1 returns 1":
      proc test(Field: typedesc) =
        let One = block:
          var O{.noInit.}: Field
          O.setOne()
          O
        block:
          var r{.noinit.}: Field
          r.square(One)
          check: bool(r == One)
        block:
          var r{.noinit.}: Field
          r.prod(One, One)
          check: bool(r == One)

      staticFor(curve, TestCurves):
        test(ExtField(ExtDegree, curve))

    test "Squaring 2 returns 4":
      proc test(Field: typedesc) =
        let One = block:
          var O{.noInit.}: Field
          O.setOne()
          O

        var Two: Field
        Two.double(One)

        var Four: Field
        Four.double(Two)

        block:
          var r: Field
          r.square(Two)

          check: bool(r == Four)
        block:
          var r: Field
          r.prod(Two, Two)

          check: bool(r == Four)

      staticFor(curve, TestCurves):
        test(ExtField(ExtDegree, curve))

    test "Squaring 3 returns 9":
      proc test(Field: typedesc) =
        let One = block:
          var O{.noInit.}: Field
          O.setOne()
          O

        var Three: Field
        for _ in 0 ..< 3:
          Three += One

        var Nine: Field
        for _ in 0 ..< 9:
          Nine += One

        block:
          var u: Field
          u.square(Three)

          check: bool(u == Nine)
        block:
          var u: Field
          u.prod(Three, Three)

          check: bool(u == Nine)

      staticFor(curve, TestCurves):
        test(ExtField(ExtDegree, curve))

    test "Squaring -3 returns 9":
      proc test(Field: typedesc) =
        let One = block:
          var O{.noInit.}: Field
          O.setOne()
          O

        var MinusThree: Field
        for _ in 0 ..< 3:
          MinusThree -= One

        var Nine: Field
        for _ in 0 ..< 9:
          Nine += One

        block:
          var u: Field
          u.square(MinusThree)

          check: bool(u == Nine)
        block:
          var u: Field
          u.prod(MinusThree, MinusThree)

          check: bool(u == Nine)

      staticFor(curve, TestCurves):
        test(ExtField(ExtDegree, curve))

    test "Multiplication by 0 and 1":
      template test(Field: typedesc, body: untyped) =
        block:
          proc testInstance() =
            let Z {.inject.} = block:
              var Z{.noInit.}: Field
              Z.setZero()
              Z
            let O {.inject.} = block:
              var O{.noInit.}: Field
              O.setOne()
              O

            for _ in 0 ..< Iters:
              let x {.inject.} = rng.random_unsafe(Field)
              var r{.noinit, inject.}: Field
              body

          testInstance()

      staticFor(curve, TestCurves):
        test(ExtField(ExtDegree, curve)):
          r.prod(x, Z)
          check: bool(r == Z)
        test(ExtField(ExtDegree, curve)):
          r.prod(Z, x)
          check: bool(r == Z)
        test(ExtField(ExtDegree, curve)):
          r.prod(x, O)
          check: bool(r == x)
        test(ExtField(ExtDegree, curve)):
          r.prod(O, x)
          check: bool(r == x)

    test "Multiplication and Squaring are consistent":
      proc test(Field: typedesc, Iters: static int) =
        for _ in 0 ..< Iters:
          let a = rng.random_unsafe(Field)
          var rMul{.noInit.}, rSqr{.noInit.}: Field

          rMul.prod(a, a)
          rSqr.square(a)

          check: bool(rMul == rSqr)

      staticFor(curve, TestCurves):
        test(ExtField(ExtDegree, curve), Iters)

    test "Squaring the opposite gives the same result":
      proc test(Field: typedesc, Iters: static int) =
        for _ in 0 ..< Iters:
          let a = rng.random_unsafe(Field)
          var na{.noInit.}: Field
          na.neg(a)

          var rSqr{.noInit.}, rNegSqr{.noInit.}: Field

          rSqr.square(a)
          rNegSqr.square(na)

          check: bool(rSqr == rNegSqr)

      staticFor(curve, TestCurves):
        test(ExtField(ExtDegree, curve), Iters)

    test "Multiplication and Addition/Substraction are consistent":
      proc test(Field: typedesc, Iters: static int) =
        for _ in 0 ..< Iters:
          let factor = rng.random_unsafe(-30..30)

          let a = rng.random_unsafe(Field)

          if factor == 0: continue

          var sum{.noInit.}, one{.noInit.}, f{.noInit.}: Field
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

          var r{.noInit.}: Field

          r.prod(a, f)

          check: bool(r == sum)

      staticFor(curve, TestCurves):
        test(ExtField(ExtDegree, curve), Iters)

    test "Addition is associative and commutative":
      proc test(Field: typedesc, Iters: static int) =
        for _ in 0 ..< Iters:
          let a = rng.random_unsafe(Field)
          let b = rng.random_unsafe(Field)
          let c = rng.random_unsafe(Field)

          var tmp1{.noInit.}, tmp2{.noInit.}: Field

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

      staticFor(curve, TestCurves):
        test(ExtField(ExtDegree, curve), Iters)

    test "Multiplication is associative and commutative":
      proc test(Field: typedesc, Iters: static int) =
        for _ in 0 ..< Iters:
          let a = rng.random_unsafe(Field)
          let b = rng.random_unsafe(Field)
          let c = rng.random_unsafe(Field)

          var tmp1{.noInit.}, tmp2{.noInit.}: Field

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

      staticFor(curve, TestCurves):
        test(ExtField(ExtDegree, curve), Iters)

    test "Extension field multiplicative inverse":
      proc test(Field: typedesc, Iters: static int) =
        var aInv, r{.noInit.}: Field

        for _ in 0 ..< Iters:
          let a = rng.random_unsafe(Field)
          aInv.inv(a)
          r.prod(a, aInv)
          check: bool(r.isOne())
          r.prod(aInv, a)
          check: bool(r.isOne())

      staticFor(curve, TestCurves):
        test(ExtField(ExtDegree, curve), Iters)

    test "0 does not have a multiplicative inverse and should return 0 for projective/jacobian => affine coordinates conversion":
      proc test(Field: typedesc) =
        var z: Field
        z.setZero()

        var zInv{.noInit.}: Field

        zInv.inv(z)
        check: bool zInv.isZero()

      staticFor(curve, TestCurves):
        test(ExtField(ExtDegree, curve))
