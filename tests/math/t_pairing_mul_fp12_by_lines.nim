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
  ../../constantine/platforms/abstractions,
  ../../constantine/math/arithmetic,
  ../../constantine/math/extension_fields,
  ../../constantine/math/config/curves,
  ../../constantine/math/io/io_extfields,
  ../../constantine/math/pairing/lines_eval,
  # Test utilities
  ../../helpers/[prng_unsafe, static_for]

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
    proc test_fp4_0y(C: static Curve, gen: static RandomGen) =
      for _ in 0 ..< Iters:
        let a = rng.random_elem(Fp4[C], gen)
        let y = rng.random_elem(Fp2[C], gen)
        let b = Fp4[C](coords: [Fp2[C](), y])

        var r {.noInit.}, r2 {.noInit.}: Fp4[C]

        r.prod(a, b)
        r2.mul_sparse_by_0y(a, y)

        check: bool(r == r2)

    staticFor(curve, TestCurves):
      test_fp4_0y(curve, gen = Uniform)
      test_fp4_0y(curve, gen = HighHammingWeight)
      test_fp4_0y(curve, gen = Long01Sequence)

  test "Dense 𝔽p6 by Sparse 0y0":
    proc test_fp6_0y0(C: static Curve, gen: static RandomGen) =
      for _ in 0 ..< Iters:
        let a = rng.random_elem(Fp6[C], gen)
        let y = rng.random_elem(Fp2[C], gen)
        let b = Fp6[C](coords: [Fp2[C](), y, Fp2[C]()])

        var r {.noInit.}, r2 {.noInit.}: Fp6[C]

        r.prod(a, b)
        r2.mul_sparse_by_0y0(a, y)

        check: bool(r == r2)

    staticFor(curve, TestCurves):
      test_fp6_0y0(curve, gen = Uniform)
      test_fp6_0y0(curve, gen = HighHammingWeight)
      test_fp6_0y0(curve, gen = Long01Sequence)

  test "Dense 𝔽p6 by Sparse xy0":
    proc test_fp6_xy0(C: static Curve, gen: static RandomGen) =
      for _ in 0 ..< Iters:
        let a = rng.random_elem(Fp6[C], gen)
        let x = rng.random_elem(Fp2[C], gen)
        let y = rng.random_elem(Fp2[C], gen)
        let b = Fp6[C](coords: [x, y, Fp2[C]()])

        var r {.noInit.}, r2 {.noInit.}: Fp6[C]

        r.prod(a, b)
        r2.mul_by_line_xy0(a, x, y)

        check: bool(r == r2)

    staticFor(curve, TestCurves):
      test_fp6_xy0(curve, gen = Uniform)
      test_fp6_xy0(curve, gen = HighHammingWeight)
      test_fp6_xy0(curve, gen = Long01Sequence)

  when Fp12[BN254_Snarks]().c0.typeof is Fp6:
    test "Sparse 𝔽p12/𝔽p6 resulting from ab00c0 line function":
      proc test_fp12_ab00c0(C: static Curve, gen: static RandomGen) =
        for _ in 0 ..< Iters:
          var a = rng.random_elem(Fp12[C], gen)
          var a2 = a

          var x = rng.random_elem(Fp2[C], gen)
          var y = rng.random_elem(Fp2[C], gen)
          var z = rng.random_elem(Fp2[C], gen)

          let line = Line[Fp2[C]](a: x, b: y, c: z)
          let b = Fp12[C](
            c0: Fp6[C](coords: [       x, y, Fp2[C]()]),
            c1: Fp6[C](coords: [Fp2[C](), z, Fp2[C]()])
          )

          a *= b
          a2.mul_sparse_by_line_ab00c0(line)

          check: bool(a == a2)

      staticFor(curve, TestCurves):
        test_fp12_xy00z0(curve, gen = Uniform)
        test_fp12_xy00z0(curve, gen = HighHammingWeight)
        test_fp12_xy00z0(curve, gen = Long01Sequence)

    test "Sparse 𝔽p12/𝔽p6 resulting from acb000 line function":
      proc test_fp12_acb000(C: static Curve, gen: static RandomGen) =
        for _ in 0 ..< Iters:
          var a = rng.random_elem(Fp12[C], gen)
          var a2 = a

          var x = rng.random_elem(Fp2[C], gen)
          var y = rng.random_elem(Fp2[C], gen)
          var z = rng.random_elem(Fp2[C], gen)

          let line = Line[Fp2[C]](a: x, b: y, c: z)
          let b = Fp12[C](
            c0: Fp6[C](coords: [x, z, y])
          )

          a *= b
          a2.mul_sparse_by_line_xyz000(line)

          check: bool(a == a2)

      staticFor(curve, TestCurves):
        test_fp12_acb000(curve, gen = Uniform)
        test_fp12_acb000(curve, gen = HighHammingWeight)
        test_fp12_acb000(curve, gen = Long01Sequence)
  else:
    static: doAssert Fp12[BN254_Snarks]().c0.typeof is Fp4

    test "Sparse 𝔽p12/𝔽p4 resulting from ca00b0 line function (M-twist only)":
      proc test_fp12_ca00b0(C: static Curve, gen: static RandomGen) =
        when C.getSexticTwist() == M_Twist:
          for _ in 0 ..< Iters:
            var a = rng.random_elem(Fp12[C], gen)
            var a2 = a

            var x = rng.random_elem(Fp2[C], gen)
            var y = rng.random_elem(Fp2[C], gen)
            var z = rng.random_elem(Fp2[C], gen)

            let line = Line[Fp2[C]](a: x, b: y, c: z)
            let b = Fp12[C](
              coords: [
                Fp4[C](coords: [z, x]),
                Fp4[C](),
                Fp4[C](coords: [y, Fp2[C]()])
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
      proc test_fp12_acb000(C: static Curve, gen: static RandomGen) =
        when C.getSexticTwist() == D_Twist:
          for _ in 0 ..< Iters:
            var a = rng.random_elem(Fp12[C], gen)
            var a2 = a

            var x = rng.random_elem(Fp2[C], gen)
            var y = rng.random_elem(Fp2[C], gen)
            var z = rng.random_elem(Fp2[C], gen)

            let line = Line[Fp2[C]](a: x, b: y, c: z)
            let b = Fp12[C](
              coords: [
                Fp4[C](coords: [x, z]),
                Fp4[C](coords: [y, Fp2[C]()]),
                Fp4[C]()
              ]
            )

            a *= b
            a2.mul_sparse_by_line_acb000(line)

            check: bool(a == a2)

      staticFor(curve, TestCurves):
        test_fp12_acb000(curve, gen = Uniform)
        test_fp12_acb000(curve, gen = HighHammingWeight)
        test_fp12_acb000(curve, gen = Long01Sequence)

    # test "Somewhat-sparse 𝔽p12/𝔽p4 resulting from xy000z*xy000z line functions (M-twist only)":
    #   proc test_fp12_xy000z_xy000z(C: static Curve, gen: static RandomGen) =
    #     when C.getSexticTwist() == M_Twist:
    #       for _ in 0 ..< Iters:
    #         var x0 = rng.random_elem(Fp2[C], gen)
    #         var y0 = rng.random_elem(Fp2[C], gen)
    #         var z0 = rng.random_elem(Fp2[C], gen)

    #         let line0 = Line[Fp2[C]](x: x0, y: y0, z: z0)
    #         let f0 = Fp12[C](
    #           coords: [
    #             Fp4[C](coords: [x0, y0]),
    #             Fp4[C](),
    #             Fp4[C](coords: [Fp2[C](), z0])
    #           ]
    #         )

    #         var x1 = rng.random_elem(Fp2[C], gen)
    #         var y1 = rng.random_elem(Fp2[C], gen)
    #         var z1 = rng.random_elem(Fp2[C], gen)

    #         let line1 = Line[Fp2[C]](x: x1, y: y1, z: z1)
    #         let f1 = Fp12[C](
    #           coords: [
    #             Fp4[C](coords: [x1, y1]),
    #             Fp4[C](),
    #             Fp4[C](coords: [Fp2[C](), z1])
    #           ]
    #         )

    #         var r: Fp12[C]
    #         r.prod(f0, f1)

    #         var rl: Fp12[C]
    #         rl.prod_xy000z_xy000z_into_abcd00efghij(line0, line1)

    #         check: bool(r == rl)

    # test "Somewhat-sparse 𝔽p12/𝔽p4 resulting from xyz000*xyz000 line functions (D-twist only)":
    #   proc test_fp12_xyz000_xyz000(C: static Curve, gen: static RandomGen) =
    #     when C.getSexticTwist() == D_Twist:
    #       for _ in 0 ..< Iters:
    #         var x0 = rng.random_elem(Fp2[C], gen)
    #         var y0 = rng.random_elem(Fp2[C], gen)
    #         var z0 = rng.random_elem(Fp2[C], gen)

    #         let line0 = Line[Fp2[C]](x: x0, y: y0, z: z0)
    #         let f0 = Fp12[C](
    #           coords: [
    #             Fp4[C](coords: [x0, y0]),
    #             Fp4[C](coords: [z0, Fp2[C]()]),
    #             Fp4[C]()
    #           ]
    #         )

    #         var x1 = rng.random_elem(Fp2[C], gen)
    #         var y1 = rng.random_elem(Fp2[C], gen)
    #         var z1 = rng.random_elem(Fp2[C], gen)

    #         let line1 = Line[Fp2[C]](x: x1, y: y1, z: z1)
    #         let f1 = Fp12[C](
    #           coords: [
    #             Fp4[C](coords: [x1, y1]),
    #             Fp4[C](coords: [z1, Fp2[C]()]),
    #             Fp4[C]()
    #           ]
    #         )

    #         var r: Fp12[C]
    #         r.prod(f0, f1)

    #         var rl: Fp12[C]
    #         rl.prod_xyz000_xyz000_into_abcdefghij00(line0, line1)

    #         check: bool(r == rl)

    #   staticFor(curve, TestCurves):
    #     test_fp12_xyz000_xyz000(curve, gen = Uniform)
    #     test_fp12_xyz000_xyz000(curve, gen = HighHammingWeight)
    #     test_fp12_xyz000_xyz000(curve, gen = Long01Sequence)

    # test "Somewhat-sparse 𝔽p12/𝔽p4 mul by the product (xyz000*xyz000) of line functions (D-twist only)":
    #   proc test_fp12_abcdefghij00(C: static Curve, gen: static RandomGen) =
    #     when C.getSexticTwist() == D_Twist:
    #       for _ in 0 ..< Iters:
    #         var x0 = rng.random_elem(Fp2[C], gen)
    #         var y0 = rng.random_elem(Fp2[C], gen)
    #         var z0 = rng.random_elem(Fp2[C], gen)

    #         let line0 = Line[Fp2[C]](x: x0, y: y0, z: z0)
    #         let f0 = Fp12[C](
    #           coords: [
    #             Fp4[C](coords: [x0, y0]),
    #             Fp4[C](coords: [z0, Fp2[C]()]),
    #             Fp4[C]()
    #           ]
    #         )

    #         var x1 = rng.random_elem(Fp2[C], gen)
    #         var y1 = rng.random_elem(Fp2[C], gen)
    #         var z1 = rng.random_elem(Fp2[C], gen)

    #         let line1 = Line[Fp2[C]](x: x1, y: y1, z: z1)
    #         let f1 = Fp12[C](
    #           coords: [
    #             Fp4[C](coords: [x1, y1]),
    #             Fp4[C](coords: [z1, Fp2[C]()]),
    #             Fp4[C]()
    #           ]
    #         )

    #         var rl: Fp12[C]
    #         rl.prod_xyz000_xyz000_into_abcdefghij00(line0, line1)

    #         var f = rng.random_elem(Fp12[C], gen)
    #         var f2 = f

    #         f *= rl
    #         f2.mul_sparse_by_abcdefghij00(rl)

    #         check: bool(f == f2)

    #   staticFor(curve, TestCurves):
    #     test_fp12_abcdefghij00(curve, gen = Uniform)
    #     test_fp12_abcdefghij00(curve, gen = HighHammingWeight)
    #     test_fp12_abcdefghij00(curve, gen = Long01Sequence)

    # test "Somewhat-sparse 𝔽p12/𝔽p4 mul by the product (xy000z*xy000z) of line functions (M-twist only)":
    #   proc test_fp12_abcd00efghij(C: static Curve, gen: static RandomGen) =
    #     when C.getSexticTwist() == M_Twist:
    #       for _ in 0 ..< Iters:
    #         var x0 = rng.random_elem(Fp2[C], gen)
    #         var y0 = rng.random_elem(Fp2[C], gen)
    #         var z0 = rng.random_elem(Fp2[C], gen)

    #         let line0 = Line[Fp2[C]](x: x0, y: y0, z: z0)
    #         let f0 = Fp12[C](
    #           coords: [
    #             Fp4[C](coords: [x0, y0]),
    #             Fp4[C](),
    #             Fp4[C](coords: [Fp2[C](), z0])
    #           ]
    #         )

    #         var x1 = rng.random_elem(Fp2[C], gen)
    #         var y1 = rng.random_elem(Fp2[C], gen)
    #         var z1 = rng.random_elem(Fp2[C], gen)

    #         let line1 = Line[Fp2[C]](x: x1, y: y1, z: z1)
    #         let f1 = Fp12[C](
    #           coords: [
    #             Fp4[C](coords: [x1, y1]),
    #             Fp4[C](),
    #             Fp4[C](coords: [Fp2[C](), z1])
    #           ]
    #         )

    #         var rl: Fp12[C]
    #         rl.prod_xy000z_xy000z_into_abcd00efghij(line0, line1)

    #         var f = rng.random_elem(Fp12[C], gen)
    #         var f2 = f

    #         f *= rl
    #         f2.mul_sparse_by_abcd00efghij(rl)

    #         check: bool(f == f2)

    #   staticFor(curve, TestCurves):
    #     test_fp12_abcd00efghij(curve, gen = Uniform)
    #     test_fp12_abcd00efghij(curve, gen = HighHammingWeight)
    #     test_fp12_abcd00efghij(curve, gen = Long01Sequence)
