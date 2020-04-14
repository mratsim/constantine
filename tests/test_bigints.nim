# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import  unittest,
        ../constantine/io/io_bigints,
        ../constantine/arithmetic,
        ../constantine/config/common,
        ../constantine/primitives

proc mainArith() =
  suite "isZero":
    test "isZero for zero":
      var x: BigInt[128]
      check: x.isZero().bool
    test "isZero for non-zero":
      block:
        var x = fromHex(BigInt[128], "0x00000000_00000000_00000000_00000001")
        check: not x.isZero().bool
      block:
        var x = fromHex(BigInt[128], "0x00000000_00000001_00000000_00000000")
        check: not x.isZero().bool
      block:
        var x = fromHex(BigInt[128], "0xFFFFFFFF_FFFFFFFF_FFFFFFFF_FFFFFFFF")
        check: not x.isZero().bool

  suite "Arithmetic operations - Addition":
    test "Adding 2 zeros":
      var a = fromHex(BigInt[128], "0x00000000_00000000_00000000_00000000")
      let b = fromHex(BigInt[128], "0x00000000_00000000_00000000_00000000")
      let carry = a.cadd(b, ctrue(Word))
      check: a.isZero().bool

    test "Adding 1 zero - real addition":
      block:
        var a = fromHex(BigInt[128], "0x00000000_00000000_00000000_00000000")
        let b = fromHex(BigInt[128], "0x00000000_00000000_00000000_00000001")
        let carry = a.cadd(b, ctrue(Word))

        let c = fromHex(BigInt[128], "0x00000000_00000000_00000000_00000001")
        check:
          bool(a == c)
      block:
        var a = fromHex(BigInt[128], "0x00000000_00000000_00000000_00000001")
        let b = fromHex(BigInt[128], "0x00000000_00000000_00000000_00000000")
        let carry = a.cadd(b, ctrue(Word))

        let c = fromHex(BigInt[128], "0x00000000_00000000_00000000_00000001")
        check:
          bool(a == c)

    test "Adding 1 zero - fake addition":
      block:
        var a = fromHex(BigInt[128], "0x00000000_00000000_00000000_00000000")
        let b = fromHex(BigInt[128], "0x00000000_00000000_00000000_00000001")
        let carry = a.cadd(b, cfalse(Word))

        let c = a
        check:
          bool(a == c)
      block:
        var a = fromHex(BigInt[128], "0x00000000_00000000_00000000_00000001")
        let b = fromHex(BigInt[128], "0x00000000_00000000_00000000_00000000")
        let carry = a.cadd(b, cfalse(Word))

        let c = a
        check:
          bool(a == c)

    test "Adding non-zeros - real addition":
      block:
        var a = fromHex(BigInt[128], "0x00000000_00000001_00000000_00000000")
        let b = fromHex(BigInt[128], "0x00000000_00000000_00000000_00000001")
        let carry = a.cadd(b, ctrue(Word))

        let c = fromHex(BigInt[128], "0x00000000_00000001_00000000_00000001")
        check:
          bool(a == c)
      block:
        var a = fromHex(BigInt[128], "0x00000000_00000000_00000000_00000001")
        let b = fromHex(BigInt[128], "0x00000000_00000001_00000000_00000000")
        let carry = a.cadd(b, ctrue(Word))

        let c = fromHex(BigInt[128], "0x00000000_00000001_00000000_00000001")
        check:
          bool(a == c)

    test "Adding non-zeros - fake addition":
      block:
        var a = fromHex(BigInt[128], "0x00000000_00000001_00000000_00000000")
        let b = fromHex(BigInt[128], "0x00000000_00000000_00000000_00000001")
        let carry = a.cadd(b, cfalse(Word))

        let c = a
        check:
          bool(a == c)
      block:
        var a = fromHex(BigInt[128], "0x00000000_00000000_00000000_00000001")
        let b = fromHex(BigInt[128], "0x00000000_00000001_00000000_00000000")
        let carry = a.cadd(b, cfalse(Word))

        let c = a
        check:
          bool(a == c)

    test "Addition limbs carry":
      block:
        var a = fromHex(BigInt[128], "0x00000000_FFFFFFFF_FFFFFFFF_FFFFFFFE")
        let b = fromHex(BigInt[128], "0x00000000_00000000_00000000_00000001")
        let carry = a.cadd(b, ctrue(Word))

        let c = fromHex(BigInt[128], "0x00000000_FFFFFFFF_FFFFFFFF_FFFFFFFF")
        check:
          bool(a == c)
          not bool(carry)

      block:
        var a = fromHex(BigInt[128], "0x00000000_FFFFFFFF_FFFFFFFF_FFFFFFFF")
        let b = fromHex(BigInt[128], "0x00000000_00000000_00000000_00000001")
        let carry = a.cadd(b, ctrue(Word))

        let c = fromHex(BigInt[128], "0x00000001_00000000_00000000_00000000")
        check:
          bool(a == c)
          not bool(carry)

  suite "BigInt + Word":
    test "Addition limbs carry":
      block: # P256 / 2
        var a = BigInt[256].fromhex"0x7fffffff800000008000000000000000000000007fffffffffffffffffffffff"

        let expected = BigInt[256].fromHex"7fffffff80000000800000000000000000000000800000000000000000000000"

        discard a.add(Word 1)
        check: bool(a == expected)

  suite "Modular operations - small modulus":
    # Vectors taken from Stint - https://github.com/status-im/nim-stint
    test "100 mod 13":
      # Test 1 word and more than 1 word
      block:
        let a = BigInt[7].fromUint(100'u32)
        let m = BigInt[4].fromUint(13'u8)

        var r: BigInt[4]
        r.reduce(a, m)
        check:
          bool(r == BigInt[4].fromUint(100'u8 mod 13))

      block: #
        let a = BigInt[32].fromUint(100'u32)
        let m = BigInt[4].fromUint(13'u8)

        var r: BigInt[4]
        r.reduce(a, m)
        check:
          bool(r == BigInt[4].fromUint(100'u8 mod 13))

      block: #
        let a = BigInt[64].fromUint(100'u32)
        let m = BigInt[4].fromUint(13'u8)

        var r: BigInt[4]
        r.reduce(a, m)
        check:
          bool(r == BigInt[4].fromUint(100'u8 mod 13))

    test "2^64 mod 3":
      let a = BigInt[65].fromHex("0x1_00000000_00000000")
      let m = BigInt[8].fromUint(3'u8)

      var r: BigInt[8]
      r.reduce(a, m)
      check:
        bool(r == BigInt[8].fromUint(1'u8))

    test "1234567891234567890 mod 10":
      let a = BigInt[64].fromUint(1234567891234567890'u64)
      let m = BigInt[8].fromUint(10'u8)

      var r: BigInt[8]
      r.reduce(a, m)
      check:
        bool(r == BigInt[8].fromUint(0'u8))

  suite "Modular operations - small modulus - Stint specific failures highlighted by property-based testing":
    # Vectors taken from Stint - https://github.com/status-im/nim-stint
    test "Modulo: 65696211516342324 mod 174261910798982":
      let u = 65696211516342324'u64
      let v = 174261910798982'u64

      let a = BigInt[56].fromUint(u)
      let m = BigInt[48].fromUint(v)

      var r: BigInt[48]
      r.reduce(a, m)

      check:
        bool(r == BigInt[48].fromUint(u mod v))

    test "Modulo: 15080397990160655 mod 600432699691":
      let u = 15080397990160655'u64
      let v = 600432699691'u64

      let a = BigInt[54].fromUint(u)
      let m = BigInt[40].fromUint(v)

      var r: BigInt[40]
      r.reduce(a, m)

      check:
        bool(r == BigInt[40].fromUint(u mod v))

proc mainNeg() =
  suite "Conditional negation":
    test "Conditional negation":
      block:
        var a = fromHex(BigInt[128], "0x12345678_FF11FFAA_00321321_CAFECAFE")
        var b = fromHex(BigInt[128], "0xDEADBEEF_DEADBEEF_DEADBEEF_DEADBEEF")

        let a2 = a
        let b2 = b

        a.cneg(CtTrue)
        b.cneg(CtTrue)

        discard a.add(a2)
        discard b.add(b2)

        check:
          bool(a.isZero)
          bool(b.isZero)

      block:
        var a = fromHex(BigInt[128], "0x12345678_FF11FFAA_00321321_CAFECAFE")
        var b = fromHex(BigInt[128], "0xDEADBEEF_DEADBEEF_DEADBEEF_DEADBEEF")

        let a2 = a
        let b2 = b

        a.cneg(CtFalse)
        b.cneg(CtFalse)

        check:
          bool(a == a2)
          bool(b == b2)

    test "Conditional negation with carries":
      block:
        var a = fromHex(BigInt[128], "0x12345678_FF11FFAA_00321321_FFFFFFFF")
        var b = fromHex(BigInt[128], "0xFFFFFFFF_FFFFFFFF_00000000_00000000")

        let a2 = a
        let b2 = b

        a.cneg(CtTrue)
        b.cneg(CtTrue)

        discard a.add(a2)
        discard b.add(b2)

        check:
          bool(a.isZero)
          bool(b.isZero)

      block:
        var a = fromHex(BigInt[128], "0x12345678_00000000_00321321_FFFFFFFF")
        var b = fromHex(BigInt[128], "0xFFFFFFFF_FFFFFFFF_00000000_00000000")

        let a2 = a
        let b2 = b

        a.cneg(CtFalse)
        b.cneg(CtFalse)

        check:
          bool(a == a2)
          bool(b == b2)

    test "Conditional all-zero bit or all-one bit":
      block:
        var a = fromHex(BigInt[128], "0x00000000_00000000_00000000_00000000")
        var b = fromHex(BigInt[128], "0xFFFFFFFF_FFFFFFFF_FFFFFFFF_FFFFFFFF")

        let a2 = a
        let b2 = b

        a.cneg(CtTrue)
        b.cneg(CtTrue)

        discard a.add(a2)
        discard b.add(b2)

        check:
          bool(a.isZero)
          bool(b.isZero)

      block:
        var a = fromHex(BigInt[128], "0x00000000_00000000_00000000_00000000")
        var b = fromHex(BigInt[128], "0xFFFFFFFF_FFFFFFFF_FFFFFFFF_FFFFFFFF")

        let a2 = a
        let b2 = b

        a.cneg(CtFalse)
        b.cneg(CtFalse)

        check:
          bool(a == a2)
          bool(b == b2)

proc mainCopySwap() =
  suite "Copy and Swap":
    test "Conditional copy":
      block:
        var a = fromHex(BigInt[128], "0x12345678_FF11FFAA_00321321_CAFECAFE")
        let b = fromHex(BigInt[128], "0xDEADBEEF_DEADBEEF_DEADBEEF_DEADBEEF")

        var expected = a
        a.ccopy(b, CtFalse)

        check: bool(expected == a)

      block:
        var a = fromHex(BigInt[128], "0x00000000_FFFFFFFF_FFFFFFFF_FFFFFFFF")
        let b = fromHex(BigInt[128], "0x00000000_00000000_00000000_00000001")

        var expected = b
        a.ccopy(b, CtTrue)

        check: bool(expected == b)

    test "Conditional swap":
      block:
        var a = fromHex(BigInt[128], "0x12345678_FF11FFAA_00321321_CAFECAFE")
        var b = fromHex(BigInt[128], "0xDEADBEEF_DEADBEEF_DEADBEEF_DEADBEEF")

        let eA = a
        let eB = b

        a.cswap(b, CtFalse)
        check:
          bool(eA == a)
          bool(eB == b)

      block:
        var a = fromHex(BigInt[128], "0x00000000_FFFFFFFF_FFFFFFFF_FFFFFFFF")
        var b = fromHex(BigInt[128], "0x00000000_00000000_00000000_00000001")

        let eA = b
        let eB = a

        a.cswap(b, CtTrue)
        check:
          bool(eA == a)
          bool(eB == b)

proc mainModularInverse() =
  suite "Modular Inverse (with odd modulus)":
    # Note: We don't define multi-precision multiplication
    #       because who needs it when you have Montgomery?
    #       ¯\_(ツ)_/¯
    test "42^-1 (mod 2017) = 1969":
      block: # small int
        let a = BigInt[16].fromUint(42'u16)
        let M = BigInt[16].fromUint(2017'u16)

        var mp1div2 = M
        discard mp1div2.add(Word 1)
        mp1div2.shiftRight(1)

        let expected = BigInt[16].fromUint(1969'u16)
        var r {.noInit.}: BigInt[16]

        r.invmod(a, M, mp1div2)

        check: bool(r == expected)

      block: # huge int
        let a = BigInt[381].fromUint(42'u16)
        let M = BigInt[381].fromUint(2017'u16)

        var mp1div2 = M
        discard mp1div2.add(Word 1)
        mp1div2.shiftRight(1)

        let expected = BigInt[381].fromUint(1969'u16)
        var r {.noInit.}: BigInt[381]

        r.invmod(a, M, mp1div2)

        check: bool(r == expected)

    test "271^-1 (mod 383) = 106":
      block: # small int
        let a = BigInt[16].fromUint(271'u16)
        let M = BigInt[16].fromUint(383'u16)

        var mp1div2 = M
        discard mp1div2.add(Word 1)
        mp1div2.shiftRight(1)

        let expected = BigInt[16].fromUint(106'u16)
        var r {.noInit.}: BigInt[16]

        r.invmod(a, M, mp1div2)

        check: bool(r == expected)

      block: # huge int
        let a = BigInt[381].fromUint(271'u16)
        let M = BigInt[381].fromUint(383'u16)

        var mp1div2 = M
        discard mp1div2.add(Word 1)
        mp1div2.shiftRight(1)

        let expected = BigInt[381].fromUint(106'u16)
        var r {.noInit.}: BigInt[381]

        r.invmod(a, M, mp1div2)

        check: bool(r == expected)

    test "BN254_Modulus^-1 (mod BLS12_381)":
      let a = BigInt[381].fromHex("0x30644e72e131a029b85045b68181585d97816a916871ca8d3c208c16d87cfd47")
      let M = BigInt[381].fromHex("0x1a0111ea397fe69a4b1ba7b6434bacd764774b84f38512bf6730d2a0f6b0f6241eabfffeb153ffffb9feffffffffaaab")

      var mp1div2 = M
      discard mp1div2.add(Word 1)
      mp1div2.shiftRight(1)

      let expected = BigInt[381].fromHex("0x0636759a0f3034fa47174b2c0334902f11e9915b7bd89c6a2b3082b109abbc9837da17201f6d8286fe6203caa1b9d4c8")

      var r {.noInit.}: BigInt[381]
      r.invmod(a, M, mp1div2)

      check: bool(r == expected)

    test "0^-1 (mod any) = 0 (need for tower of extension fields)":
      block:
        let a = BigInt[16].fromUint(0'u16)
        let M = BigInt[16].fromUint(2017'u16)

        var mp1div2 = M
        mp1div2.shiftRight(1)
        discard mp1div2.add(Word 1)

        let expected = BigInt[16].fromUint(0'u16)
        var r {.noInit.}: BigInt[16]

        r.invmod(a, M, mp1div2)

        check: bool(r == expected)

      block:
        let a = BigInt[381].fromUint(0'u16)
        let M = BigInt[381].fromHex("0x1a0111ea397fe69a4b1ba7b6434bacd764774b84f38512bf6730d2a0f6b0f6241eabfffeb153ffffb9feffffffffaaab")

        var mp1div2 = M
        mp1div2.shiftRight(1)
        discard mp1div2.add(Word 1)

        let expected = BigInt[381].fromUint(0'u16)
        var r {.noInit.}: BigInt[381]

        r.invmod(a, M, mp1div2)

        check: bool(r == expected)

mainArith()
mainNeg()
mainCopySwap()
mainModularInverse()
