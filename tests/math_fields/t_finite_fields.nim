# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import  std/unittest,
        constantine/math/arithmetic,
        constantine/math/arithmetic/limbs_montgomery,
        constantine/math/io/[io_bigints, io_fields],
        constantine/named/algebras,
        constantine/platforms/abstractions

static: doAssert defined(CTT_TEST_CURVES), "This modules requires the -d:CTT_TEST_CURVES compile option"

echo "\n------------------------------------------------------\n"

proc main() =
  suite "Basic arithmetic over finite fields":
    test "Addition mod 101":
      block:
        var x, y, z: Fp[Fake101]

        x.fromUint(80'u32)
        y.fromUint(10'u32)
        z.fromUint(90'u32)

        x += y

        var x_bytes: array[8, byte]
        x_bytes.marshal(x, cpuEndian)

        check:
          # Check equality in the Montgomery domain
          bool(z == x)
          # Check equality when converting back to natural domain
          90'u64 == cast[uint64](x_bytes)

      block:
        var x, y, z: Fp[Fake101]

        x.fromUint(80'u32)
        y.fromUint(21'u32)
        z.fromUint(0'u32)

        x += y

        var x_bytes: array[8, byte]
        x_bytes.marshal(x, cpuEndian)

        check:
          # Check equality in the Montgomery domain
          bool(z == x)
          # Check equality when converting back to natural domain
          0'u64 == cast[uint64](x_bytes)

      block:
        var x, y, z: Fp[Fake101]

        x.fromUint(80'u32)
        y.fromUint(22'u32)
        z.fromUint(1'u32)

        x += y

        var x_bytes: array[8, byte]
        x_bytes.marshal(x, cpuEndian)

        check:
          # Check equality in the Montgomery domain
          bool(z == x)
          # Check equality when converting back to natural domain
          1'u64 == cast[uint64](x_bytes)

    test "Substraction mod 101":
      block:
        var x, y, z: Fp[Fake101]

        x.fromUint(80'u32)
        y.fromUint(10'u32)
        z.fromUint(70'u32)

        x -= y

        var x_bytes: array[8, byte]
        x_bytes.marshal(x, cpuEndian)

        check:
          # Check equality in the Montgomery domain
          bool(z == x)
          # Check equality when converting back to natural domain
          70'u64 == cast[uint64](x_bytes)

      block:
        var x, y, z: Fp[Fake101]

        x.fromUint(80'u32)
        y.fromUint(80'u32)
        z.fromUint(0'u32)

        x -= y

        var x_bytes: array[8, byte]
        x_bytes.marshal(x, cpuEndian)

        check:
          # Check equality in the Montgomery domain
          bool(z == x)
          # Check equality when converting back to natural domain
          0'u64 == cast[uint64](x_bytes)

      block:
        var x, y, z: Fp[Fake101]

        x.fromUint(80'u32)
        y.fromUint(81'u32)
        z.fromUint(100'u32)

        x -= y

        var x_bytes: array[8, byte]
        x_bytes.marshal(x, cpuEndian)

        check:
          # Check equality in the Montgomery domain
          bool(z == x)
          # Check equality when converting back to natural domain
          100'u64 == cast[uint64](x_bytes)

    test "Multiplication mod 101":
      block:
        var x, y, z, r: Fp[Fake101]

        x.fromUint(10'u32)
        y.fromUint(10'u32)
        z.fromUint(100'u32)

        r.prod(x, y)

        var r_bytes: array[8, byte]
        r_bytes.marshal(r, cpuEndian)

        check:
          # Check equality in the Montgomery domain
          bool(z == r)
          # Check equality when converting back to natural domain
          100'u64 == cast[uint64](r_bytes)

      block:
        var x, y, z, r: Fp[Fake101]

        x.fromUint(10'u32)
        y.fromUint(11'u32)
        z.fromUint(9'u32)

        r.prod(x, y)

        var r_bytes: array[8, byte]
        r_bytes.marshal(r, cpuEndian)

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
        x_bytes.marshal(x, cpuEndian)
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
        x_bytes.marshal(x, cpuEndian)
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
        x_bytes.marshal(x, cpuEndian)
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
        x_bytes.marshal(x, cpuEndian)
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
        x_bytes.marshal(x, cpuEndian)
        let new_x = cast[uint64](x_bytes)

        check:
          # Check equality in the Montgomery domain
          bool(z == x)
          # Check equality when converting back to natural domain
          new_x == 1'u64 shl 61 - 2

    test "Multiplication mod 2^61 - 1":
      block:
        var x, y, z, r: Fp[Mersenne61]

        x.fromUint(10'u32)
        y.fromUint(10'u32)
        z.fromUint(100'u32)

        r.prod(x, y)

        var r_bytes: array[8, byte]
        r_bytes.marshal(r, cpuEndian)
        let new_r = cast[uint64](r_bytes)

        check:
          # Check equality in the Montgomery domain
          bool(z == r)
          # Check equality when converting back to natural domain
          new_r == 100'u64

      block:
        var x, y, z, r: Fp[Mersenne61]

        x.fromUint(1'u32 shl 31)
        y.fromUint(1'u32 shl 31)
        z.fromUint(2'u32)

        r.prod(x, y)

        var r_bytes: array[8, byte]
        r_bytes.marshal(r, cpuEndian)
        let new_r = cast[uint64](r_bytes)

        check:
          # Check equality in the Montgomery domain
          bool(z == r)
          # Check equality when converting back to natural domain
          new_r == 2'u64


main()

proc largeField() =
  suite "Large field":
    test "Negate 0 returns 0 (unique Montgomery repr)":
      # https://github.com/mratsim/constantine/issues/136
      # and https://github.com/mratsim/constantine/issues/114
      # The assembly implementation of neg didn't check
      # after M-a if a was zero and so while in mod M
      # M ≡ 0 (mod M), the `==` doesn't support unreduced representation.
      var a: Fp[BN254_Snarks]
      var r {.noInit.}: Fp[BN254_Snarks]
      r.neg(a)

      check: bool r.isZero()

    # Outdated tests as Crandall primes / Pseudo-Mersenne primes
    # don't use Montgomery representaiton anymore

    # test "fromMont doesn't need a final substraction with 256-bit prime (full word used)":
    #   block:
    #     let a = Fp[Secp256k1].getMinusOne()
    #     let expected = BigInt[256].fromHex"0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEFFFFFC2E"

    #     var r: BigInt[256]
    #     r.fromField(a)

    #     check: bool(r == expected)
    #   block:
    #     var a: Fp[Secp256k1]
    #     var d: FpDbl[Secp256k1]

    #     # Set Montgomery repr to the largest field element in Montgomery Residue form
    #     a.mres    = BigInt[256].fromHex"0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEFFFFFC2E"
    #     d.limbs2x = (BigInt[512].fromHex"0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEFFFFFC2E").limbs

    #     var r, expected: BigInt[256]

    #     r.fromField(a)
    #     expected.limbs.redc2xMont(d.limbs2x, Fp[Secp256k1].getModulus().limbs, Fp[Secp256k1].getNegInvModWord(), Fp[Secp256k1].getSpareBits())

    #     check: bool(r == expected)

    # test "fromMont doesn't need a final substraction with 255-bit prime (1 spare bit)":
    #   block:
    #     let a = Fp[Edwards25519].getMinusOne()
    #     let expected = BigInt[255].fromHex"0x7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffec"

    #     var r: BigInt[255]
    #     r.fromField(a)

    #     check: bool(r == expected)
    #   block:
    #     var a: Fp[Edwards25519]
    #     var d: FpDbl[Edwards25519]

    #     # Set Montgomery repr to the largest field element in Montgomery Residue form
    #     a.mres    = BigInt[255].fromHex"0x7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffec"
    #     d.limbs2x = (BigInt[512].fromHex"0x7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffec").limbs

    #     var r, expected: BigInt[255]

    #     r.fromField(a)
    #     expected.limbs.redc2xMont(d.limbs2x, Fp[Edwards25519].getModulus().limbs, Fp[Edwards25519].getNegInvModWord(), Fp[Edwards25519].getSpareBits())

    #     check: bool(r == expected)

largeField()
