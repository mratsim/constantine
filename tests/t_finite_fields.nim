# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import  std/unittest,
        ../constantine/arithmetic,
        ../constantine/io/io_fields,
        ../constantine/config/curves

static: doAssert defined(testingCurves), "This modules requires the -d:testingCurves compile option"

echo "\n------------------------------------------------------\n"

proc main() =
  suite "Basic arithmetic over finite fields":
    test "Addition mod 101":
      block:
        var x, y, z: Fp[Fake101]

        x.fromUint(80'u32)
        y.fromUint(10'u32)
        z.fromUint(90'u32)

        let u = x + y
        x += y

        var x_bytes: array[8, byte]
        x_bytes.exportRawUint(x, cpuEndian)

        check:
          # Check equality in the Montgomery domain
          bool(z == x)
          bool(z == u)
          # Check equality when converting back to natural domain
          90'u64 == cast[uint64](x_bytes)

      block:
        var x, y, z: Fp[Fake101]

        x.fromUint(80'u32)
        y.fromUint(21'u32)
        z.fromUint(0'u32)

        let u = x + y
        x += y

        var x_bytes: array[8, byte]
        x_bytes.exportRawUint(x, cpuEndian)

        check:
          # Check equality in the Montgomery domain
          bool(z == x)
          bool(z == u)
          # Check equality when converting back to natural domain
          0'u64 == cast[uint64](x_bytes)

      block:
        var x, y, z: Fp[Fake101]

        x.fromUint(80'u32)
        y.fromUint(22'u32)
        z.fromUint(1'u32)

        let u = x + y
        x += y

        var x_bytes: array[8, byte]
        x_bytes.exportRawUint(x, cpuEndian)

        check:
          # Check equality in the Montgomery domain
          bool(z == x)
          bool(z == u)
          # Check equality when converting back to natural domain
          1'u64 == cast[uint64](x_bytes)

    test "Substraction mod 101":
      block:
        var x, y, z: Fp[Fake101]

        x.fromUint(80'u32)
        y.fromUint(10'u32)
        z.fromUint(70'u32)

        let u = x - y
        x -= y

        var x_bytes: array[8, byte]
        x_bytes.exportRawUint(x, cpuEndian)

        check:
          # Check equality in the Montgomery domain
          bool(z == x)
          bool(z == u)
          # Check equality when converting back to natural domain
          70'u64 == cast[uint64](x_bytes)

      block:
        var x, y, z: Fp[Fake101]

        x.fromUint(80'u32)
        y.fromUint(80'u32)
        z.fromUint(0'u32)

        let u = x - y
        x -= y

        var x_bytes: array[8, byte]
        x_bytes.exportRawUint(x, cpuEndian)

        check:
          # Check equality in the Montgomery domain
          bool(z == x)
          bool(z == u)
          # Check equality when converting back to natural domain
          0'u64 == cast[uint64](x_bytes)

      block:
        var x, y, z: Fp[Fake101]

        x.fromUint(80'u32)
        y.fromUint(81'u32)
        z.fromUint(100'u32)

        let u = x - y
        x -= y

        var x_bytes: array[8, byte]
        x_bytes.exportRawUint(x, cpuEndian)

        check:
          # Check equality in the Montgomery domain
          bool(z == x)
          bool(z == u)
          # Check equality when converting back to natural domain
          100'u64 == cast[uint64](x_bytes)

    test "Multiplication mod 101":
      block:
        var x, y, z: Fp[Fake101]

        x.fromUint(10'u32)
        y.fromUint(10'u32)
        z.fromUint(100'u32)

        let r = x * y

        var r_bytes: array[8, byte]
        r_bytes.exportRawUint(r, cpuEndian)

        check:
          # Check equality in the Montgomery domain
          bool(z == r)
          # Check equality when converting back to natural domain
          100'u64 == cast[uint64](r_bytes)

      block:
        var x, y, z: Fp[Fake101]

        x.fromUint(10'u32)
        y.fromUint(11'u32)
        z.fromUint(9'u32)

        let r = x * y

        var r_bytes: array[8, byte]
        r_bytes.exportRawUint(r, cpuEndian)

        check:
          # Check equality in the Montgomery domain
          bool(z == r)
          # Check equality when converting back to natural domain
          9'u64 == cast[uint64](r_bytes)

    test "Addition mod 2^61 - 1":
      block:
        var x, y, z: Fp[Mersenne61]

        x.fromUint(80'u64)
        y.fromUint(10'u64)
        z.fromUint(90'u64)

        x += y

        var x_bytes: array[8, byte]
        x_bytes.exportRawUint(x, cpuEndian)
        let new_x = cast[uint64](x_bytes)

        check:
          # Check equality in the Montgomery domain
          bool(z == x)
          # Check equality when converting back to natural domain
          new_x == 90'u64

      block:
        var x, y, z: Fp[Mersenne61]

        x.fromUint(1'u64 shl 61 - 2)
        y.fromUint(1'u32)
        z.fromUint(0'u32)

        x += y

        var x_bytes: array[8, byte]
        x_bytes.exportRawUint(x, cpuEndian)
        let new_x = cast[uint64](x_bytes)

        check:
          # Check equality in the Montgomery domain
          bool(z == x)
          # Check equality when converting back to natural domain
          new_x == 0'u64

      block:
        var x, y, z: Fp[Mersenne61]

        x.fromUint(1'u64 shl 61 - 2)
        y.fromUint(2'u64)
        z.fromUint(1'u64)

        x += y

        var x_bytes: array[8, byte]
        x_bytes.exportRawUint(x, cpuEndian)
        let new_x = cast[uint64](x_bytes)

        check:
          # Check equality in the Montgomery domain
          bool(z == x)
          # Check equality when converting back to natural domain
          new_x == 1'u64

    test "Substraction mod 2^61 - 1":
      block:
        var x, y, z: Fp[Mersenne61]

        x.fromUint(80'u64)
        y.fromUint(10'u64)
        z.fromUint(70'u64)

        x -= y

        var x_bytes: array[8, byte]
        x_bytes.exportRawUint(x, cpuEndian)
        let new_x = cast[uint64](x_bytes)

        check:
          # Check equality in the Montgomery domain
          bool(z == x)
          # Check equality when converting back to natural domain
          new_x == 70'u64

      block:
        var x, y, z: Fp[Mersenne61]

        x.fromUint(0'u64)
        y.fromUint(1'u64)
        z.fromUint(1'u64 shl 61 - 2)

        x -= y

        var x_bytes: array[8, byte]
        x_bytes.exportRawUint(x, cpuEndian)
        let new_x = cast[uint64](x_bytes)

        check:
          # Check equality in the Montgomery domain
          bool(z == x)
          # Check equality when converting back to natural domain
          new_x == 1'u64 shl 61 - 2

    test "Multiplication mod 2^61 - 1":
      block:
        var x, y, z: Fp[Mersenne61]

        x.fromUint(10'u32)
        y.fromUint(10'u32)
        z.fromUint(100'u32)

        let r = x * y

        var r_bytes: array[8, byte]
        r_bytes.exportRawUint(r, cpuEndian)
        let new_r = cast[uint64](r_bytes)

        check:
          # Check equality in the Montgomery domain
          bool(z == r)
          # Check equality when converting back to natural domain
          cast[uint64](r_bytes) == 100'u64

      block:
        var x, y, z: Fp[Mersenne61]

        x.fromUint(1'u32 shl 31)
        y.fromUint(1'u32 shl 31)
        z.fromUint(2'u32)

        let r = x * y

        var r_bytes: array[8, byte]
        r_bytes.exportRawUint(r, cpuEndian)
        let new_r = cast[uint64](r_bytes)

        check:
          # Check equality in the Montgomery domain
          bool(z == r)
          # Check equality when converting back to natural domain
          new_r == 2'u64


main()

proc largeField() =
  suite "Large field":
    test "Negate 0 returns 0":
      var a: Fp[BN254_Snarks]
      var r {.noInit.}: Fp[BN254_Snarks]
      r.neg(a)

      check: bool r.isZero()

largeField()
