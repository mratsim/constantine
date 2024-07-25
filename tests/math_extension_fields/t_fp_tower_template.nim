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
  constantine/platforms/abstractions,
  constantine/math/extension_fields,
  constantine/named/algebras,
  constantine/math/arithmetic,
  constantine/math/io/io_extfields,
  # Test utilities
  helpers/prng_unsafe

export unittest # Generic sandwich

echo "\n------------------------------------------------------\n"

template ExtField(degree: static int, name: static Algebra): untyped =
  when degree == 2:
    Fp2[name]
  elif degree == 4:
    Fp4[name]
  elif degree == 6:
    Fp6[name]
  elif degree == 12:
    Fp12[name]
  else:
    {.error: "Unconfigured extension degree".}

type
  RandomGen = enum
    Uniform
    HighHammingWeight
    Long01Sequence

func random_elem(rng: var RngState, F: typedesc, gen: RandomGen): F {.inline, noInit.} =
  if gen == Uniform:
    result = rng.random_unsafe(F)
  elif gen == HighHammingWeight:
    result = rng.random_highHammingWeight(F)
  else:
    result = rng.random_long01Seq(F)

proc runTowerTests*[N](
      ExtDegree: static int,
      Iters: static int,
      TestCurves: static array[N, Algebra],
      moduleName: string,
      testSuiteDesc: string
    ) =

  # Random seed for reproducibility
  var rng: RngState
  let seed = uint32(getTime().toUnix() and (1'i64 shl 32 - 1)) # unixTime mod 2^32
  rng.seed(seed)
  echo moduleName, " xoshiro512** seed: ", seed

  suite testSuiteDesc & " [" & $WordBitWidth & "-bit words]":
    test "Comparison sanity checks":
      proc test(Field: typedesc) =
        var z, o {.noInit.}: Field

        z.setZero()
        o.setOne()

        check: not bool(z == o)

      staticFor(curve, TestCurves):
        test(ExtField(ExtDegree, curve))

    test "Addition, substraction negation are consistent":
      proc test(Field: typedesc, Iters: static int, gen: RandomGen) =
        # Try to exercise all code paths for in-place/out-of-place add/sum/sub/diff/double/neg
        # (1 - (-a) - b + (-a) - 2a) + (2a + 2b + (-b))  == 1
        var accum {.noInit.}, One {.noInit.}, a{.noInit.}, na{.noInit.}, b{.noInit.}, nb{.noInit.}, a2 {.noInit.}, b2 {.noInit.}: Field

        for _ in 0 ..< Iters:
          One.setOne()
          a = rng.random_elem(Field, gen)
          a2 = a
          a2.double()
          na.neg(a)

          b = rng.random_elem(Field, gen)
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
        test(ExtField(ExtDegree, curve), Iters, gen = Uniform)
        test(ExtField(ExtDegree, curve), Iters, gen = HighHammingWeight)
        test(ExtField(ExtDegree, curve), Iters, gen = Long01Sequence)

    test "Division by 2":
      proc test(Field: typedesc, Iters: static int, gen: static RandomGen) =
        for _ in 0 ..< Iters:
          let a = rng.random_elem(Field, gen)
          var a2 = a
          a2.double()
          a2.div2()
          check: bool(a == a2)
          a2.div2()
          a2.double()
          check: bool(a == a2)

      staticFor(curve, TestCurves):
        test(ExtField(ExtDegree, curve), Iters, gen = Uniform)
        test(ExtField(ExtDegree, curve), Iters, gen = HighHammingWeight)
        test(ExtField(ExtDegree, curve), Iters, gen = Long01Sequence)

    test "Squaring 1 returns 1":
      proc test(Field: typedesc) =
        let One = block:
          var O{.noInit.}: Field
          O.setOne()
          O
        block:
          var r{.noinit.}: Field
          r.square(One)
          doAssert bool(r == One),
            "\n(" & $Field & "): Expected one: " & One.toHex() & "\n" &
            "got: " & r.toHex()
        block:
          var r{.noinit.}: Field
          r.prod(One, One)
          doAssert bool(r == One),
            "\n(" & $Field & "): Expected one: " & One.toHex() & "\n" &
            "got: " & r.toHex()

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

          doAssert bool(r == Four),
            "\n(" & $Field & "): Expected 4: " & Four.toHex() & "\n" &
            "got: " & r.toHex()
        block:
          var r: Field
          r.prod(Two, Two)

          doAssert bool(r == Four),
            "\n(" & $Field & "): Expected 4: " & Four.toHex() & "\n" &
            "got: " & r.toHex()

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

          doAssert bool(u == Nine),
            "\n(" & $Field & "): Expected 9: " & Nine.toHex() & "\n" &
            "got: " & u.toHex()
        block:
          var u: Field
          u.prod(Three, Three)

          doAssert bool(u == Nine),
            "\n(" & $Field & "): Expected 9: " & Nine.toHex() & "\n" &
            "got: " & u.toHex()

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

          doAssert bool(u == Nine),
            "\n(" & $Field & "): Expected 9: " & Nine.toHex() & "\n" &
            "got: " & u.toHex()
        block:
          var u: Field
          u.prod(MinusThree, MinusThree)

          doAssert bool(u == Nine),
            "\n(" & $Field & "): Expected 9: " & Nine.toHex() & "\n" &
            "got: " & u.toHex()

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
          doAssert bool(r == Z),
            "\nExpected zero but got \n(" & $ExtField(ExtDegree, curve) & "): " & x.toHex()
        test(ExtField(ExtDegree, curve)):
          r.prod(Z, x)
          doAssert bool(r == Z),
            "\nExpected zero but got \n(" & $ExtField(ExtDegree, curve) & "): " & x.toHex()
        test(ExtField(ExtDegree, curve)):
          r.prod(x, O)
          doAssert bool(r == x),
            "\n(" & $ExtField(ExtDegree, curve) & "): Expected one: " & O.toHex() & "\n" &
            "got: " & x.toHex()
        test(ExtField(ExtDegree, curve)):
          r.prod(O, x)
          doAssert bool(r == x),
            "\n(" & $ExtField(ExtDegree, curve) & "): Expected one: " & O.toHex() & "\n" &
            "got: " & x.toHex()

    test "Multiplication and Squaring are consistent":
      proc test(Field: typedesc, Iters: static int, gen: static RandomGen) =
        for _ in 0 ..< Iters:
          let a = rng.random_elem(Field, gen)
          var rMul{.noInit.}, rSqr{.noInit.}: Field

          rMul.prod(a, a)
          rSqr.square(a)

          doAssert bool(rMul == rSqr), "Failure with a (" & $Field & "): \nInput:" & a.toHex() & "\n" &
            "Mul: " & rMul.toHex() & "\n" &
            "Sqr: " & rSqr.toHex() & "\n"

      staticFor(curve, TestCurves):
        test(ExtField(ExtDegree, curve), Iters, gen = Uniform)
        test(ExtField(ExtDegree, curve), Iters, gen = HighHammingWeight)
        test(ExtField(ExtDegree, curve), Iters, gen = Long01Sequence)

    test "Squaring the opposite gives the same result":
      proc test(Field: typedesc, Iters: static int, gen: static RandomGen) =
        for _ in 0 ..< Iters:
          let a = rng.random_elem(Field, gen)
          var na{.noInit.}: Field
          na.neg(a)

          var rSqr{.noInit.}, rNegSqr{.noInit.}: Field

          rSqr.square(a)
          rNegSqr.square(na)

          doAssert bool(rSqr == rNegSqr), "Failure with a \n(" & $Field & "): " & a.toHex() & "\n" &
            "Sqr:    " & rSqr.toHex() & "\n" &
            "SqrNeg: " & rNegSqr.toHex() & "\n"

      staticFor(curve, TestCurves):
        test(ExtField(ExtDegree, curve), Iters, gen = Uniform)
        test(ExtField(ExtDegree, curve), Iters, gen = HighHammingWeight)
        test(ExtField(ExtDegree, curve), Iters, gen = Long01Sequence)

    test "Multiplication and Addition/Substraction are consistent":
      proc test(Field: typedesc, Iters: static int, gen: static RandomGen) =
        for _ in 0 ..< Iters:
          let factor = rng.random_unsafe(-30..30)

          let a = rng.random_elem(Field, gen)

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
        test(ExtField(ExtDegree, curve), Iters, gen = Uniform)
        test(ExtField(ExtDegree, curve), Iters, gen = HighHammingWeight)
        test(ExtField(ExtDegree, curve), Iters, gen = Long01Sequence)

    test "Addition is associative and commutative":
      proc test(Field: typedesc, Iters: static int, gen: static RandomGen) =
        for _ in 0 ..< Iters:
          let a = rng.random_elem(Field, gen)
          let b = rng.random_elem(Field, gen)
          let c = rng.random_elem(Field, gen)

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
        test(ExtField(ExtDegree, curve), Iters, gen = Uniform)
        test(ExtField(ExtDegree, curve), Iters, gen = HighHammingWeight)
        test(ExtField(ExtDegree, curve), Iters, gen = Long01Sequence)

    test "Multiplication is associative and commutative":
      proc test(Field: typedesc, Iters: static int, gen: static RandomGen) =
        for _ in 0 ..< Iters:
          let a = rng.random_elem(Field, gen)
          let b = rng.random_elem(Field, gen)
          let c = rng.random_elem(Field, gen)

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
        test(ExtField(ExtDegree, curve), Iters, gen = Uniform)
        test(ExtField(ExtDegree, curve), Iters, gen = HighHammingWeight)
        test(ExtField(ExtDegree, curve), Iters, gen = Long01Sequence)

    test "Extension field multiplicative inverse":
      proc test(Field: typedesc, Iters: static int, gen: static RandomGen) =
        var aInv, r{.noInit.}: Field

        for _ in 0 ..< Iters:
          let a = rng.random_elem(Field, gen)
          aInv.inv(a)
          r.prod(a, aInv)
          check: bool(r.isOne())
          r.prod(aInv, a)
          check: bool(r.isOne())

      staticFor(curve, TestCurves):
        test(ExtField(ExtDegree, curve), Iters, gen = Uniform)
        test(ExtField(ExtDegree, curve), Iters, gen = HighHammingWeight)
        test(ExtField(ExtDegree, curve), Iters, gen = Long01Sequence)

    test "0 does not have a multiplicative inverse and should return 0 for projective/jacobian => affine coordinates conversion":
      proc test(Field: typedesc) =
        var z: Field
        z.setZero()

        var zInv{.noInit.}: Field

        zInv.inv(z)
        check: bool zInv.isZero()

      staticFor(curve, TestCurves):
        test(ExtField(ExtDegree, curve))
