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
  ../constantine/config/common,
  ../constantine/[arithmetic, primitives],
  ../constantine/towers,
  ../constantine/config/curves,
  ../constantine/io/io_towers,
  ../constantine/pairing/[
    lines_projective,
    mul_fp12_by_lines
  ],
  # Test utilities
  ../helpers/[prng_unsafe, static_for]

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
        let b = Fp4[C](c1: y)

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
        let b = Fp6[C](c1: y)

        var r {.noInit.}, r2 {.noInit.}: Fp6[C]

        r.prod(a, b)
        r2.mul_sparse_by_0y0(a, y)

        check: bool(r == r2)

    staticFor(curve, TestCurves):
      test_fp6_0y0(curve, gen = Uniform)
      test_fp6_0y0(curve, gen = HighHammingWeight)
      test_fp6_0y0(curve, gen = Long01Sequence)

  test "Dense 𝔽p6 by Sparse xy0":
    proc test_fp6_0y0(C: static Curve, gen: static RandomGen) =
      for _ in 0 ..< Iters:
        let a = rng.random_elem(Fp6[C], gen)
        let x = rng.random_elem(Fp2[C], gen)
        let y = rng.random_elem(Fp2[C], gen)
        let b = Fp6[C](c0: x, c1: y)
        let line = Line[Fp2[C]](x: x, y: y)

        var r {.noInit.}, r2 {.noInit.}: Fp6[C]

        r.prod(a, b)
        r2.mul_by_line_xy0(a, line)

        check: bool(r == r2)

    staticFor(curve, TestCurves):
      test_fp6_0y0(curve, gen = Uniform)
      test_fp6_0y0(curve, gen = HighHammingWeight)
      test_fp6_0y0(curve, gen = Long01Sequence)

  when Fp12[BN254_Snarks]().c0.typeof is Fp6:
    test "Sparse 𝔽p12/𝔽p6 resulting from xy00z0 line function":
      proc test_fp12_xy00z0(C: static Curve, gen: static RandomGen) =
        for _ in 0 ..< Iters:
          var a = rng.random_elem(Fp12[C], gen)
          var a2 = a

          var x = rng.random_elem(Fp2[C], gen)
          var y = rng.random_elem(Fp2[C], gen)
          var z = rng.random_elem(Fp2[C], gen)

          let line = Line[Fp2[C]](x: x, y: y, z: z)
          let b = Fp12[C](
            c0: Fp6[C](c0: x, c1: y),
            c1: Fp6[C](c1: z)
          )

          a *= b
          a2.mul_sparse_by_line_xy00z0(line)

          check: bool(a == a2)

      staticFor(curve, TestCurves):
        test_fp12_xy00z0(curve, gen = Uniform)
        test_fp12_xy00z0(curve, gen = HighHammingWeight)
        test_fp12_xy00z0(curve, gen = Long01Sequence)

    test "Sparse 𝔽p12/𝔽p6 resulting from xyz000 line function":
      proc test_fp12_xyz000(C: static Curve, gen: static RandomGen) =
        for _ in 0 ..< Iters:
          var a = rng.random_elem(Fp12[C], gen)
          var a2 = a

          var x = rng.random_elem(Fp2[C], gen)
          var y = rng.random_elem(Fp2[C], gen)
          var z = rng.random_elem(Fp2[C], gen)

          let line = Line[Fp2[C]](x: x, y: y, z: z)
          let b = Fp12[C](
            c0: Fp6[C](c0: x, c1: y, c2: z)
          )

          a *= b
          a2.mul_sparse_by_line_xyz000(line)

          check: bool(a == a2)

      staticFor(curve, TestCurves):
        test_fp12_xyz000(curve, gen = Uniform)
        test_fp12_xyz000(curve, gen = HighHammingWeight)
        test_fp12_xyz000(curve, gen = Long01Sequence)
  else:
    static: doAssert Fp12[BN254_Snarks]().c0.typeof is Fp4

    test "Sparse 𝔽p12/𝔽p4 resulting from xy000z line function (M-twist only)":
      proc test_fp12_xy000z(C: static Curve, gen: static RandomGen) =
        when C.getSexticTwist() == M_Twist:
          for _ in 0 ..< Iters:
            var a = rng.random_elem(Fp12[C], gen)
            var a2 = a

            var x = rng.random_elem(Fp2[C], gen)
            var y = rng.random_elem(Fp2[C], gen)
            var z = rng.random_elem(Fp2[C], gen)

            let line = Line[Fp2[C]](x: x, y: y, z: z)
            let b = Fp12[C](
              c0: Fp4[C](c0: x, c1: y),
              # c1
              c2: Fp4[C](       c1: z),
            )

            a *= b
            a2.mul_sparse_by_line_xy000z(line)

            check: bool(a == a2)

      staticFor(curve, TestCurves):
        test_fp12_xy000z(curve, gen = Uniform)
        test_fp12_xy000z(curve, gen = HighHammingWeight)
        test_fp12_xy000z(curve, gen = Long01Sequence)

    test "Sparse 𝔽p12/𝔽p4 resulting from xyz000 line function (D-twist only)":
      proc test_fp12_xy000z(C: static Curve, gen: static RandomGen) =
        when C.getSexticTwist() == D_Twist:
          for _ in 0 ..< Iters:
            var a = rng.random_elem(Fp12[C], gen)
            var a2 = a

            var x = rng.random_elem(Fp2[C], gen)
            var y = rng.random_elem(Fp2[C], gen)
            var z = rng.random_elem(Fp2[C], gen)

            let line = Line[Fp2[C]](x: x, y: y, z: z)
            let b = Fp12[C](
              c0: Fp4[C](c0: x, c1: y),
              c1: Fp4[C](c0: z       ),
              # c2:
            )

            a *= b
            a2.mul_sparse_by_line_xyz000(line)

            check: bool(a == a2)

      staticFor(curve, TestCurves):
        test_fp12_xy000z(curve, gen = Uniform)
        test_fp12_xy000z(curve, gen = HighHammingWeight)
        test_fp12_xy000z(curve, gen = Long01Sequence)
