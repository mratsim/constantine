# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  # Standard library
  std/[tables, unittest, times],
  # Internals
  constantine/platforms/abstractions,
  constantine/math/arithmetic,
  constantine/math/extension_fields,
  constantine/named/algebras,
  constantine/math/io/io_extfields,
  constantine/math/pairings/lines_eval,
  # Test utilities
  helpers/prng_unsafe

const
  Iters = 8
  TestCurves = [
    BN254_Nogami,
    BN254_Snarks,
    BLS12_377,
    BLS12_381
  ]

type
  RandomGen = enum
    Uniform
    HighHammingWeight
    Long01Sequence

var rng: RngState
let seed = uint32(getTime().toUnix() and (1'i64 shl 32 - 1)) # unixTime mod 2^32
rng.seed(seed)
echo "\n------------------------------------------------------\n"
echo "test_pairing_fp12_sparse xoshiro512** seed: ", seed

func random_elem(rng: var RngState, F: typedesc, gen: RandomGen): F {.inline, noInit.} =
  if gen == Uniform:
    result = rng.random_unsafe(F)
  elif gen == HighHammingWeight:
    result = rng.random_highHammingWeight(F)
  else:
    result = rng.random_long01Seq(F)

suite "Pairing - Sparse 𝔽p12 multiplication by line function is consistent with dense 𝔽p12 mul":
  test "Dense 𝔽p4 by Sparse 0y":
    proc test_fp4_0y(Name: static Algebra, gen: static RandomGen) =
      for _ in 0 ..< Iters:
        let a = rng.random_elem(Fp4[Name], gen)
        let y = rng.random_elem(Fp2[Name], gen)
        let b = Fp4[Name](coords: [Fp2[Name](), y])

        var r, r2: Fp4[Name]

        r.prod(a, b)
        r2.mul_sparse_by_0y(a, y)

        check: bool(r == r2)

    staticFor(curve, TestCurves):
      test_fp4_0y(curve, gen = Uniform)
      test_fp4_0y(curve, gen = HighHammingWeight)
      test_fp4_0y(curve, gen = Long01Sequence)

  test "Dense 𝔽p6 by Sparse 0y0":
    proc test_fp6_0y0(Name: static Algebra, gen: static RandomGen) =
      for _ in 0 ..< Iters:
        let a = rng.random_elem(Fp6[Name], gen)
        let y = rng.random_elem(Fp2[Name], gen)
        let b = Fp6[Name](coords: [Fp2[Name](), y, Fp2[Name]()])

        var r, r2: Fp6[Name]

        r.prod(a, b)
        r2.mul_sparse_by_0y0(a, y)

        check: bool(r == r2)

    staticFor(curve, TestCurves):
      test_fp6_0y0(curve, gen = Uniform)
      test_fp6_0y0(curve, gen = HighHammingWeight)
      test_fp6_0y0(curve, gen = Long01Sequence)

  test "Dense 𝔽p6 by Sparse xy0":
    proc test_fp6_xy0(Name: static Algebra, gen: static RandomGen) =
      for _ in 0 ..< Iters:
        let a = rng.random_elem(Fp6[Name], gen)
        let x = rng.random_elem(Fp2[Name], gen)
        let y = rng.random_elem(Fp2[Name], gen)
        let b = Fp6[Name](coords: [x, y, Fp2[Name]()])

        var r, r2: Fp6[Name]

        r.prod(a, b)
        r2.mul_sparse_by_xy0(a, x, y)

        check: bool(r == r2)

    staticFor(curve, TestCurves):
      test_fp6_xy0(curve, gen = Uniform)
      test_fp6_xy0(curve, gen = HighHammingWeight)
      test_fp6_xy0(curve, gen = Long01Sequence)

  test "Dense 𝔽p6 by Sparse 0yz":
    proc test_fp6_0yz(Name: static Algebra, gen: static RandomGen) =
      for _ in 0 ..< Iters:
        let a = rng.random_elem(Fp6[Name], gen)
        let y = rng.random_elem(Fp2[Name], gen)
        let z = rng.random_elem(Fp2[Name], gen)
        let b = Fp6[Name](coords: [Fp2[Name](), y, z])

        var r, r2: Fp6[Name]

        r.prod(a, b)
        r2.mul_sparse_by_0yz(a, y, z)

        check: bool(r == r2)

    staticFor(curve, TestCurves):
      test_fp6_0yz(curve, gen = Uniform)
      test_fp6_0yz(curve, gen = HighHammingWeight)
      test_fp6_0yz(curve, gen = Long01Sequence)

  when Fp12[BN254_Snarks]().c0.typeof is Fp6:
    # =========== Towering 𝔽p12/𝔽p6 ======================================

    test "Sparse 𝔽p12/𝔽p6 resulting from a00bc0 line function":
      proc test_fp12_a00bc0(Name: static Algebra, gen: static RandomGen) =
        when Name.getSexticTwist() == D_Twist:
          for _ in 0 ..< Iters:
            var a = rng.random_elem(Fp12[Name], gen)
            var a2 = a

            var x = rng.random_elem(Fp2[Name], gen)
            var y = rng.random_elem(Fp2[Name], gen)
            var z = rng.random_elem(Fp2[Name], gen)

            let line = Line[Fp2[Name]](a: x, b: y, c: z)
            let b = Fp12[Name]( coords: [
              Fp6[Name](coords: [ x, Fp2[Name](), Fp2[Name]()]),
              Fp6[Name](coords: [ y,        z, Fp2[Name]()])
            ])

            a *= b
            a2.mul_sparse_by_line_a00bc0(line)

            check: bool(a == a2)

        staticFor(curve, TestCurves):
          test_fp12_a00bc0(curve, gen = Uniform)
          test_fp12_a00bc0(curve, gen = HighHammingWeight)
          test_fp12_a00bc0(curve, gen = Long01Sequence)

    test "Sparse 𝔽p12/𝔽p6 resulting from cb00a0 line function":
      proc test_fp12_cb00a0(Name: static Algebra, gen: static RandomGen) =
        when Name.getSexticTwist() == M_Twist:
          for _ in 0 ..< Iters:
            var a = rng.random_elem(Fp12[Name], gen)
            var a2 = a

            var x = rng.random_elem(Fp2[Name], gen)
            var y = rng.random_elem(Fp2[Name], gen)
            var z = rng.random_elem(Fp2[Name], gen)

            let line = Line[Fp2[Name]](a: x, b: y, c: z)
            let b = Fp12[Name](coords: [
              Fp6[Name](coords: [       z, y, Fp2[Name]()]),
              Fp6[Name](coords: [Fp2[Name](), x, Fp2[Name]()])
            ])

            a *= b
            a2.mul_sparse_by_line_cb00a0(line)

            check: bool(a == a2)

        staticFor(curve, TestCurves):
          test_fp12_cb00a0(curve, gen = Uniform)
          test_fp12_cb00a0(curve, gen = HighHammingWeight)
          test_fp12_cb00a0(curve, gen = Long01Sequence)

    test "Somewhat-sparse 𝔽p12/𝔽p6 resulting from a00bc0*a00bc0 line functions (D-twist only)":
      proc test_fp12_a00bc0_a00bc0(Name: static Algebra, gen: static RandomGen) =
        when Name.getSexticTwist() == D_Twist:
          for _ in 0 ..< Iters:
            var x0 = rng.random_elem(Fp2[Name], gen)
            var y0 = rng.random_elem(Fp2[Name], gen)
            var z0 = rng.random_elem(Fp2[Name], gen)

            let line0 = Line[Fp2[Name]](a: x0, b: y0, c: z0)
            let f0 = Fp12[Name]( coords: [
              Fp6[Name](coords: [ x0, Fp2[Name](), Fp2[Name]()]),
              Fp6[Name](coords: [ y0,       z0, Fp2[Name]()])
            ])


            var x1 = rng.random_elem(Fp2[Name], gen)
            var y1 = rng.random_elem(Fp2[Name], gen)
            var z1 = rng.random_elem(Fp2[Name], gen)

            let line1 = Line[Fp2[Name]](a: x1, b: y1, c: z1)
            let f1 = Fp12[Name]( coords: [
              Fp6[Name](coords: [ x1, Fp2[Name](), Fp2[Name]()]),
              Fp6[Name](coords: [ y1,       z1, Fp2[Name]()])
            ])

            var r: Fp12[Name]
            r.prod(f0, f1)

            var rl: Fp12[Name]
            rl.prod_x00yz0_x00yz0_into_abcdefghij00(line0, line1)

            check: bool(r == rl)

      staticFor(curve, TestCurves):
        test_fp12_a00bc0_a00bc0(curve, gen = Uniform)
        test_fp12_a00bc0_a00bc0(curve, gen = HighHammingWeight)
        test_fp12_a00bc0_a00bc0(curve, gen = Long01Sequence)

    test "Somewhat-sparse 𝔽p12/𝔽p6 resulting from cb00a0*cb00a0 line functions (M-twist only)":
      proc test_fp12_cb00a0_cb00a0(Name: static Algebra, gen: static RandomGen) =
        when Name.getSexticTwist() == M_Twist:
          for _ in 0 ..< Iters:
            var x0 = rng.random_elem(Fp2[Name], gen)
            var y0 = rng.random_elem(Fp2[Name], gen)
            var z0 = rng.random_elem(Fp2[Name], gen)

            let line0 = Line[Fp2[Name]](a: x0, b: y0, c: z0)
            let f0 = Fp12[Name](coords: [
              Fp6[Name](coords: [      z0, y0, Fp2[Name]()]),
              Fp6[Name](coords: [Fp2[Name](), x0, Fp2[Name]()])
            ])

            var x1 = rng.random_elem(Fp2[Name], gen)
            var y1 = rng.random_elem(Fp2[Name], gen)
            var z1 = rng.random_elem(Fp2[Name], gen)

            let line1 = Line[Fp2[Name]](a: x1, b: y1, c: z1)
            let f1 = Fp12[Name](coords: [
              Fp6[Name](coords: [      z1, y1, Fp2[Name]()]),
              Fp6[Name](coords: [Fp2[Name](), x1, Fp2[Name]()])
            ])

            var r: Fp12[Name]
            r.prod(f0, f1)

            var rl: Fp12[Name]
            rl.prod_zy00x0_zy00x0_into_abcdef00ghij(line0, line1)

            check: bool(r == rl)

      staticFor(curve, TestCurves):
        test_fp12_cb00a0_cb00a0(curve, gen = Uniform)
        test_fp12_cb00a0_cb00a0(curve, gen = HighHammingWeight)
        test_fp12_cb00a0_cb00a0(curve, gen = Long01Sequence)

    test "Somewhat-sparse 𝔽p12/𝔽p6 mul by the product a00bc0*a00bc0 of line functions (D-twist only)":
      proc test_fp12_abcdefghij00(Name: static Algebra, gen: static RandomGen) =
        when Name.getSexticTwist() == D_Twist:
          for _ in 0 ..< Iters:
            var x0 = rng.random_elem(Fp2[Name], gen)
            var y0 = rng.random_elem(Fp2[Name], gen)
            var z0 = rng.random_elem(Fp2[Name], gen)

            let line0 = Line[Fp2[Name]](a: x0, b: y0, c: z0)
            let f0 = Fp12[Name]( coords: [
              Fp6[Name](coords: [ x0, Fp2[Name](), Fp2[Name]()]),
              Fp6[Name](coords: [ y0,       z0, Fp2[Name]()])
            ])


            var x1 = rng.random_elem(Fp2[Name], gen)
            var y1 = rng.random_elem(Fp2[Name], gen)
            var z1 = rng.random_elem(Fp2[Name], gen)

            let line1 = Line[Fp2[Name]](a: x1, b: y1, c: z1)
            let f1 = Fp12[Name]( coords: [
              Fp6[Name](coords: [ x1, Fp2[Name](), Fp2[Name]()]),
              Fp6[Name](coords: [ y1,       z1, Fp2[Name]()])
            ])


            var r: Fp12[Name]
            r.prod(f0, f1)

            var rl: Fp12[Name]
            rl.prod_x00yz0_x00yz0_into_abcdefghij00(line0, line1)

            var f = rng.random_elem(Fp12[Name], gen)
            var f2 = f

            f *= rl
            f2.mul_sparse_by_abcdefghij00_quad_over_cube(rl)

            check: bool(f == f2)

      staticFor(curve, TestCurves):
        test_fp12_abcdefghij00(curve, gen = Uniform)
        test_fp12_abcdefghij00(curve, gen = HighHammingWeight)
        test_fp12_abcdefghij00(curve, gen = Long01Sequence)

    test "Somewhat-sparse 𝔽p12/𝔽p6 mul by the product (cb00a0*cb00a0) of line functions (M-twist only)":
      proc test_fp12_abcdef00ghij(Name: static Algebra, gen: static RandomGen) =
        when Name.getSexticTwist() == M_Twist:
          for _ in 0 ..< Iters:
            var x0 = rng.random_elem(Fp2[Name], gen)
            var y0 = rng.random_elem(Fp2[Name], gen)
            var z0 = rng.random_elem(Fp2[Name], gen)

            let line0 = Line[Fp2[Name]](a: x0, b: y0, c: z0)
            let f0 = Fp12[Name](coords: [
              Fp6[Name](coords: [      z0, y0, Fp2[Name]()]),
              Fp6[Name](coords: [Fp2[Name](), x0, Fp2[Name]()])
            ])

            var x1 = rng.random_elem(Fp2[Name], gen)
            var y1 = rng.random_elem(Fp2[Name], gen)
            var z1 = rng.random_elem(Fp2[Name], gen)

            let line1 = Line[Fp2[Name]](a: x1, b: y1, c: z1)
            let f1 = Fp12[Name](coords: [
              Fp6[Name](coords: [      z1, y1, Fp2[Name]()]),
              Fp6[Name](coords: [Fp2[Name](), x1, Fp2[Name]()])
            ])

            var r: Fp12[Name]
            r.prod(f0, f1)

            var rl: Fp12[Name]
            rl.prod_zy00x0_zy00x0_into_abcdef00ghij(line0, line1)

            var f = rng.random_elem(Fp12[Name], gen)
            var f2 = f

            f *= rl
            f2.mul_sparse_by_abcdef00ghij_quad_over_cube(rl)

            check: bool(f == f2)

      staticFor(curve, TestCurves):
        test_fp12_abcdef00ghij(curve, gen = Uniform)
        test_fp12_abcdef00ghij(curve, gen = HighHammingWeight)
        test_fp12_abcdef00ghij(curve, gen = Long01Sequence)

  else: # =========== Towering 𝔽p12/𝔽p4 ======================================
    static: doAssert Fp12[BN254_Snarks]().c0.typeof is Fp4

    test "Sparse 𝔽p12/𝔽p4 resulting from ca00b0 line function (M-twist only)":
      proc test_fp12_ca00b0(Name: static Algebra, gen: static RandomGen) =
        when Name.getSexticTwist() == M_Twist:
          for _ in 0 ..< Iters:
            var a = rng.random_elem(Fp12[Name], gen)
            var a2 = a

            var x = rng.random_elem(Fp2[Name], gen)
            var y = rng.random_elem(Fp2[Name], gen)
            var z = rng.random_elem(Fp2[Name], gen)

            let line = Line[Fp2[Name]](a: x, b: y, c: z)
            let b = Fp12[Name](
              coords: [
                Fp4[Name](coords: [z, x]),
                Fp4[Name](),
                Fp4[Name](coords: [y, Fp2[Name]()])
              ]
            )

            a *= b
            a2.mul_sparse_by_line_ca00b0(line)

            check: bool(a == a2)

      staticFor(curve, TestCurves):
        test_fp12_ca00b0(curve, gen = Uniform)
        test_fp12_ca00b0(curve, gen = HighHammingWeight)
        test_fp12_ca00b0(curve, gen = Long01Sequence)

    test "Sparse 𝔽p12/𝔽p4 resulting from xyz000 line function (D-twist only)":
      proc test_fp12_acb000(Name: static Algebra, gen: static RandomGen) =
        when Name.getSexticTwist() == D_Twist:
          for _ in 0 ..< Iters:
            var a = rng.random_elem(Fp12[Name], gen)
            var a2 = a

            var x = rng.random_elem(Fp2[Name], gen)
            var y = rng.random_elem(Fp2[Name], gen)
            var z = rng.random_elem(Fp2[Name], gen)

            let line = Line[Fp2[Name]](a: x, b: y, c: z)
            let b = Fp12[Name](
              coords: [
                Fp4[Name](coords: [x, z]),
                Fp4[Name](coords: [y, Fp2[Name]()]),
                Fp4[Name]()
              ]
            )

            a *= b
            a2.mul_sparse_by_line_acb000(line)

            check: bool(a == a2)

      staticFor(curve, TestCurves):
        test_fp12_acb000(curve, gen = Uniform)
        test_fp12_acb000(curve, gen = HighHammingWeight)
        test_fp12_acb000(curve, gen = Long01Sequence)

    test "Somewhat-sparse 𝔽p12/𝔽p4 resulting from ca00b0*ca00b0 line functions (M-twist only)":
      proc test_fp12_ca00b0_ca00b0(Name: static Algebra, gen: static RandomGen) =
        when Name.getSexticTwist() == M_Twist:
          for _ in 0 ..< Iters:
            var x0 = rng.random_elem(Fp2[Name], gen)
            var y0 = rng.random_elem(Fp2[Name], gen)
            var z0 = rng.random_elem(Fp2[Name], gen)

            let line0 = Line[Fp2[Name]](a: x0, b: y0, c: z0)
            let f0 = Fp12[Name](
              coords: [
                Fp4[Name](coords: [z0, x0]),
                Fp4[Name](),
                Fp4[Name](coords: [y0, Fp2[Name]()])
              ]
            )

            var x1 = rng.random_elem(Fp2[Name], gen)
            var y1 = rng.random_elem(Fp2[Name], gen)
            var z1 = rng.random_elem(Fp2[Name], gen)

            let line1 = Line[Fp2[Name]](a: x1, b: y1, c: z1)
            let f1 = Fp12[Name](
              coords: [
                Fp4[Name](coords: [z1, x1]),
                Fp4[Name](),
                Fp4[Name](coords: [y1, Fp2[Name]()])
              ]
            )

            var r: Fp12[Name]
            r.prod(f0, f1)

            var rl: Fp12[Name]
            rl.prod_zx00y0_zx00y0_into_abcd00efghij(line0, line1)

            check: bool(r == rl)

      staticFor(curve, TestCurves):
        test_fp12_ca00b0_ca00b0(curve, gen = Uniform)
        test_fp12_ca00b0_ca00b0(curve, gen = HighHammingWeight)
        test_fp12_ca00b0_ca00b0(curve, gen = Long01Sequence)

    test "Somewhat-sparse 𝔽p12/𝔽p4 resulting from acb000*acb000 line functions (D-twist only)":
      proc test_fp12_acb000_acb000(Name: static Algebra, gen: static RandomGen) =
        when Name.getSexticTwist() == D_Twist:
          for _ in 0 ..< Iters:
            var x0 = rng.random_elem(Fp2[Name], gen)
            var y0 = rng.random_elem(Fp2[Name], gen)
            var z0 = rng.random_elem(Fp2[Name], gen)

            let line0 = Line[Fp2[Name]](a: x0, b: y0, c: z0)
            let f0 = Fp12[Name](
              coords: [
                Fp4[Name](coords: [x0, z0]),
                Fp4[Name](coords: [y0, Fp2[Name]()]),
                Fp4[Name]()
              ]
            )

            var x1 = rng.random_elem(Fp2[Name], gen)
            var y1 = rng.random_elem(Fp2[Name], gen)
            var z1 = rng.random_elem(Fp2[Name], gen)

            let line1 = Line[Fp2[Name]](a: x1, b: y1, c: z1)
            let f1 = Fp12[Name](
              coords: [
                Fp4[Name](coords: [x1, z1]),
                Fp4[Name](coords: [y1, Fp2[Name]()]),
                Fp4[Name]()
              ]
            )

            var r: Fp12[Name]
            r.prod(f0, f1)

            var rl: Fp12[Name]
            rl.prod_xzy000_xzy000_into_abcdefghij00(line0, line1)

            check: bool(r == rl)

      staticFor(curve, TestCurves):
        test_fp12_acb000_acb000(curve, gen = Uniform)
        test_fp12_acb000_acb000(curve, gen = HighHammingWeight)
        test_fp12_acb000_acb000(curve, gen = Long01Sequence)

    test "Somewhat-sparse 𝔽p12/𝔽p4 mul by the product (acb000*acb000) of line functions (D-twist only)":
      proc test_fp12_abcdefghij00(Name: static Algebra, gen: static RandomGen) =
        when Name.getSexticTwist() == D_Twist:
          for _ in 0 ..< Iters:
            var x0 = rng.random_elem(Fp2[Name], gen)
            var y0 = rng.random_elem(Fp2[Name], gen)
            var z0 = rng.random_elem(Fp2[Name], gen)

            let line0 = Line[Fp2[Name]](a: x0, b: y0, c: z0)
            let f0 = Fp12[Name](
              coords: [
                Fp4[Name](coords: [x0, z0]),
                Fp4[Name](coords: [y0, Fp2[Name]()]),
                Fp4[Name]()
              ]
            )

            var x1 = rng.random_elem(Fp2[Name], gen)
            var y1 = rng.random_elem(Fp2[Name], gen)
            var z1 = rng.random_elem(Fp2[Name], gen)

            let line1 = Line[Fp2[Name]](a: x1, b: y1, c: z1)
            let f1 = Fp12[Name](
              coords: [
                Fp4[Name](coords: [x1, z1]),
                Fp4[Name](coords: [y1, Fp2[Name]()]),
                Fp4[Name]()
              ]
            )

            var r: Fp12[Name]
            r.prod(f0, f1)

            var rl: Fp12[Name]
            rl.prod_xzy000_xzy000_into_abcdefghij00(line0, line1)

            var f = rng.random_elem(Fp12[Name], gen)
            var f2 = f

            f *= rl
            f2.mul_sparse_by_abcdefghij00_cube_over_quad(rl)

            check: bool(f == f2)

      staticFor(curve, TestCurves):
        test_fp12_abcdefghij00(curve, gen = Uniform)
        test_fp12_abcdefghij00(curve, gen = HighHammingWeight)
        test_fp12_abcdefghij00(curve, gen = Long01Sequence)

    test "Somewhat-sparse 𝔽p12/𝔽p4 mul by the product (ca00b0*ca00b0) of line functions (M-twist only)":
      proc test_fp12_abcdef00ghij(Name: static Algebra, gen: static RandomGen) =
        when Name.getSexticTwist() == M_Twist:
          for _ in 0 ..< Iters:
            var x0 = rng.random_elem(Fp2[Name], gen)
            var y0 = rng.random_elem(Fp2[Name], gen)
            var z0 = rng.random_elem(Fp2[Name], gen)

            let line0 = Line[Fp2[Name]](a: x0, b: y0, c: z0)
            let f0 = Fp12[Name](
              coords: [
                Fp4[Name](coords: [z0, x0]),
                Fp4[Name](),
                Fp4[Name](coords: [y0, Fp2[Name]()])
              ]
            )

            var x1 = rng.random_elem(Fp2[Name], gen)
            var y1 = rng.random_elem(Fp2[Name], gen)
            var z1 = rng.random_elem(Fp2[Name], gen)

            let line1 = Line[Fp2[Name]](a: x1, b: y1, c: z1)
            let f1 = Fp12[Name](
              coords: [
                Fp4[Name](coords: [z1, x1]),
                Fp4[Name](),
                Fp4[Name](coords: [y1, Fp2[Name]()])
              ]
            )

            var r: Fp12[Name]
            r.prod(f0, f1)

            var rl: Fp12[Name]
            rl.prod_zx00y0_zx00y0_into_abcd00efghij(line0, line1)

            var f = rng.random_elem(Fp12[Name], gen)
            var f2 = f

            f *= rl
            f2.mul_sparse_by_abcd00efghij_cube_over_quad(rl)

            check: bool(f == f2)

      staticFor(curve, TestCurves):
        test_fp12_abcdef00ghij(curve, gen = Uniform)
        test_fp12_abcdef00ghij(curve, gen = HighHammingWeight)
        test_fp12_abcdef00ghij(curve, gen = Long01Sequence)
