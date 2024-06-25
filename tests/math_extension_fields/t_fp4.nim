# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  # Internals
  constantine/math/io/io_extfields,
  constantine/named/algebras,
  # Test utilities
  ./t_fp_tower_template

const TestCurves = [
    BN254_Nogami,
    BN254_Snarks,
    BLS12_377,
    BLS12_381,
    BW6_761
  ]

runTowerTests(
  ExtDegree = 4,
  Iters = 12,
  TestCurves = TestCurves,
  moduleName = "test_fp4",
  testSuiteDesc = "𝔽p4 = 𝔽p2[v]"
)

# Fuzzing failure
# Issue when using Fp4Dbl

suite "𝔽p4 - Anti-regression":
  test "Partial reduction (off by p) on double-precision field":
    proc partred1() =
      type F = Fp4[BN254_Snarks]
      var x: F
      x.fromHex(
        "0x0000000000000000000fffffffffffffffffe000000fffffffffcffffff80000",
        "0x000000000000007ffffffffff800000001fffe000000000007ffffffffffffe0",
        "0x000000c0ff0300fcffffffff7f00000000f0ffffffffffffffff00000000e0ff",
        "0x0e0a77c19a07df27e5eea36f7879462c0a7ceb28e5c70b3dd35d438dc58f4d9c"
      )

      # echo "x: ", x.toHex()
      # echo "\n----------------------"

      var s: F
      s.square(x)

      # echo "s: ", s.toHex()
      # echo "\ns raw: ", s

      # echo "\n----------------------"
      var p: F
      p.prod(x, x)

      # echo "p: ", p.toHex()
      # echo "\np raw: ", p

      check: bool(p == s)

    partred1()

    proc partred2() =
      type F = Fp4[BN254_Snarks]
      var x: F
      x.fromHex(
        "0x0660df54c75b67a0c32fc6208f08b13d8cc86cd93084180725a04884e7f45849",
        "0x094185b0915ce1aa3bd3c63d33fd6d9cf3f04ea30fc88efe1e6e9b59117513bb",
        "0x26c20beee711e46406372ab4f0e6d0069c67ded0a494bc0301bbfde48f7a4073",
        "0x23c60254946def07120e46155466cc9b883b5c3d1c17d1d6516a6268a41dcc5d"
      )

      # echo "x: ", x.toHex()
      # echo "\n----------------------"

      var s: F
      s.square(x)

      # echo "s: ", s.toHex()
      # echo "\ns raw: ", s

      # echo "\n----------------------"
      var p: F
      p.prod(x, x)

      # echo "p: ", p.toHex()
      # echo "\np raw: ", p

      check: bool(p == s)

    partred2()


    proc partred3() =
      type F = Fp4[BN254_Snarks]
      var x: F
      x.fromHex(
        "0x233066f735efcf7a0ad6e3ffa3afe4ed39bdfeffffb3f7d8b1fd7eeabfddfb36",
        "0x1caba0b27fdfdfd512bdecf3fffbfebdb939fffffffbff8a14e663f7fef7fc85",
        "0x212a64f0efefff1b7abe2ebe2bffbfc1b9335fb73ffd7c8815ffffffffffff8d",
        "0x212ba4b1ff8feff552a61efff5ffffc5b839f7ffffffff71f477dffe7ffc7e08"
      )

      # echo "x: ", x.toHex()
      # echo "\n----------------------"

      var s: F
      s.square(x)

      # echo "s:  ", s.toHex()
      # echo "\ns raw:  ", s

      # echo "\n----------------------"
      var n, s2: F
      n.neg(x)
      s2.prod(n, n)

      # echo "s2: ", s2.toHex()
      # echo "\ns2 raw: ", s2

      check: bool(s == s2)

    partred3()
