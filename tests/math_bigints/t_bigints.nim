# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  # Standard library
  std/unittest,
  # Internal
  constantine/named/algebras,
  constantine/math/io/io_bigints,
  constantine/math/arithmetic,
  constantine/platforms/abstractions,
  # Test utilities,
  support/canaries

echo "\n------------------------------------------------------\n"

proc mainArith() =
  suite "isZero" & " [" & $WordBitWidth & "-bit words]":
    test "isZero for zero":
      var x: BigInt[128]
      check: x.isZero().bool
    test "isZero for non-zero":
      block:
        let x = fromHex(BigInt[128], "0x00000000000000000000000000000001")
        check: not x.isZero().bool
      block:
        let x = fromHex(BigInt[128], "0x00000000000000010000000000000000")
        check: not x.isZero().bool
      block:
        let x = fromHex(BigInt[128], "0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF")
        check: not x.isZero().bool

    test "isZero for zero (compile-time)":
      const x = BigInt[128]()
      check: static(x.isZero().bool)
    test "isZero for non-zero (compile-time)":
      block:
        const x = fromHex(BigInt[128], "0x00000000000000000000000000000001")
        check: static(not x.isZero().bool)
      block:
        const x = fromHex(BigInt[128], "0x00000000000000010000000000000000")
        check: static(not x.isZero().bool)
      block:
        const x = fromHex(BigInt[128], "0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF")
        check: static(not x.isZero().bool)


  suite "Arithmetic operations - Addition" & " [" & $WordBitWidth & "-bit words]":
    test "Adding 2 zeros":
      var a = fromHex(BigInt[128], "0x00000000000000000000000000000000")
      let b = fromHex(BigInt[128], "0x00000000000000000000000000000000")
      let carry = a.cadd(b, CtTrue)
      check: a.isZero().bool

    test "Adding 1 zero - real addition":
      block:
        var a = fromHex(BigInt[128], "0x00000000000000000000000000000000")
        let b = fromHex(BigInt[128], "0x00000000000000000000000000000001")
        let carry = a.cadd(b, CtTrue)

        let c = fromHex(BigInt[128], "0x00000000000000000000000000000001")
        check:
          bool(a == c)
      block:
        var a = fromHex(BigInt[128], "0x00000000000000000000000000000001")
        let b = fromHex(BigInt[128], "0x00000000000000000000000000000000")
        let carry = a.cadd(b, CtTrue)

        let c = fromHex(BigInt[128], "0x00000000000000000000000000000001")
        check:
          bool(a == c)

    test "Adding 1 zero - fake addition":
      block:
        var a = fromHex(BigInt[128], "0x00000000000000000000000000000000")
        let b = fromHex(BigInt[128], "0x00000000000000000000000000000001")
        let carry = a.cadd(b, CtFalse)

        let c = a
        check:
          bool(a == c)
      block:
        var a = fromHex(BigInt[128], "0x00000000000000000000000000000001")
        let b = fromHex(BigInt[128], "0x00000000000000000000000000000000")
        let carry = a.cadd(b, CtFalse)

        let c = a
        check:
          bool(a == c)

    test "Adding non-zeros - real addition":
      block:
        var a = fromHex(BigInt[128], "0x00000000000000010000000000000000")
        let b = fromHex(BigInt[128], "0x00000000000000000000000000000001")
        let carry = a.cadd(b, CtTrue)

        let c = fromHex(BigInt[128], "0x00000000000000010000000000000001")
        check:
          bool(a == c)
      block:
        var a = fromHex(BigInt[128], "0x00000000000000000000000000000001")
        let b = fromHex(BigInt[128], "0x00000000000000010000000000000000")
        let carry = a.cadd(b, CtTrue)

        let c = fromHex(BigInt[128], "0x00000000000000010000000000000001")
        check:
          bool(a == c)

    test "Adding non-zeros - fake addition":
      block:
        var a = fromHex(BigInt[128], "0x00000000000000010000000000000000")
        let b = fromHex(BigInt[128], "0x00000000000000000000000000000001")
        let carry = a.cadd(b, CtFalse)

        let c = a
        check:
          bool(a == c)
      block:
        var a = fromHex(BigInt[128], "0x00000000000000000000000000000001")
        let b = fromHex(BigInt[128], "0x00000000000000010000000000000000")
        let carry = a.cadd(b, CtFalse)

        let c = a
        check:
          bool(a == c)

    test "Addition limbs carry":
      block:
        var a = fromHex(BigInt[128], "0x00000000FFFFFFFFFFFFFFFFFFFFFFFE")
        let b = fromHex(BigInt[128], "0x00000000000000000000000000000001")
        let carry = a.cadd(b, CtTrue)

        let c = fromHex(BigInt[128], "0x00000000FFFFFFFFFFFFFFFFFFFFFFFF")
        check:
          bool(a == c)
          not bool(carry)

      block:
        var a = fromHex(BigInt[128], "0x00000000FFFFFFFFFFFFFFFFFFFFFFFF")
        let b = fromHex(BigInt[128], "0x00000000000000000000000000000001")
        let carry = a.cadd(b, CtTrue)

        let c = fromHex(BigInt[128], "0x00000001000000000000000000000000")
        check:
          bool(a == c)
          not bool(carry)

  suite "BigInt + SecretWord" & " [" & $WordBitWidth & "-bit words]":
    test "Addition limbs carry":
      block: # P256 / 2
        var a = BigInt[256].fromhex"0x7fffffff800000008000000000000000000000007fffffffffffffffffffffff"

        let expected = BigInt[256].fromHex"7fffffff80000000800000000000000000000000800000000000000000000000"

        discard a.add(One)
        check: bool(a == expected)

proc mainMul() =
  suite "Multi-precision multiplication" & " [" & $WordBitWidth & "-bit words]":
    test "Same size operand into double size result":
      block:
        var r = canary(BigInt[256])
        let a = BigInt[128].fromHex"0x12345678FF11FFAA00321321CAFECAFE"
        let b = BigInt[128].fromHex"0xDEADBEEFDEADBEEFDEADBEEFDEADBEEF"

        let expected = BigInt[256].fromHex"fd5bdef43d64113f371ab5d8843beca889c07fd549b84d8a5001a8f102e0722"

        r.prod(a, b)
        check: bool(r == expected)
        r.prod(b, a)
        check: bool(r == expected)

    test "Different size into large result":
      block:
        var r = canary(BigInt[200])
        let a = BigInt[29].fromHex"0x12345678"
        let b = BigInt[128].fromHex"0xDEADBEEFDEADBEEFDEADBEEFDEADBEEF"

        let expected = BigInt[200].fromHex"fd5bdee65f787f665f787f665f787f65621ca08"

        r.prod(a, b)
        check: bool(r == expected)
        r.prod(b, a)
        check: bool(r == expected)

    test "Destination is properly zero-padded if multiplicands are too short":
      block:
        var r = BigInt[200].fromHex"0xDEADBEEFDEADBEEFDEADBEEFDEADBEEFDEADBEEFDEADBEEFDE"
        let a = BigInt[29].fromHex"0x12345678"
        let b = BigInt[128].fromHex"0xDEADBEEFDEADBEEFDEADBEEFDEADBEEF"

        let expected = BigInt[200].fromHex"fd5bdee65f787f665f787f665f787f65621ca08"

        r.prod(a, b)
        check: bool(r == expected)
        r.prod(b, a)
        check: bool(r == expected)

proc mainMulHigh() =
  suite "Multi-precision multiplication keeping only high words" & " [" & $WordBitWidth & "-bit words]":
    test "Same size operand into double size result - discard first word":
      block:
        var r = canary(BigInt[256])
        let a = BigInt[128].fromHex"0x12345678FF11FFAA00321321CAFECAFE"
        let b = BigInt[128].fromHex"0xDEADBEEFDEADBEEFDEADBEEFDEADBEEF"

        when WordBitWidth == 32:
          let expected = BigInt[256].fromHex"fd5bdef43d64113f371ab5d8843beca889c07fd549b84d8a5001a8f"
        else:
          let expected = BigInt[256].fromHex"fd5bdef43d64113f371ab5d8843beca889c07fd549b84d8"

        r.prodhighwords(a, b, 1)
        check: bool(r == expected)
        r.prodhighwords(b, a, 1)
        check: bool(r == expected)

    test "Same size operand into double size result - discard first 3 words":
      block:
        var r = canary(BigInt[256])
        let a = BigInt[128].fromHex"0x12345678FF11FFAA00321321CAFECAFE"
        let b = BigInt[128].fromHex"0xDEADBEEFDEADBEEFDEADBEEFDEADBEEF"

        when WordBitWidth == 32:
          let expected = BigInt[256].fromHex"fd5bdef43d64113f371ab5d8843beca889c07fd"
        else:
          let expected = BigInt[256].fromHex"fd5bdef43d64113"

        r.prodhighwords(a, b, 3)
        check: bool(r == expected)
        r.prodhighwords(b, a, 3)
        check: bool(r == expected)

    test "All lower words trigger a carry":
      block:
        var r = canary(BigInt[256])
        let a = BigInt[256].fromHex"0xFFFFF000FFFFF111FFFFFFFAFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF"
        let b = BigInt[256].fromHex"0xFFFFFFFFFFFFF222FFFFFFFBFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF"

        # Full product:
        # fffff000ffffe33500ddc21a00cf39720000810900000013fffffffffffffffe
        # 00000fff00001ccb000000090000000000000000000000000000000000000001
        let expected = BigInt[256].fromHex"0xfffff000ffffe33500ddc21a00cf39720000810900000013fffffffffffffffe"
        when WordBitWidth == 32:
          const startWord = 8
        else:
          const startWord = 4

        r.prodhighwords(a, b, startWord)
        check: bool(r == expected)
        r.prodhighwords(b, a, startWord)
        check: bool(r == expected)

    test "Different size into large result":
      block:
        var r = canary(BigInt[200])
        let a = BigInt[29].fromHex"0x12345678"
        let b = BigInt[128].fromHex"0xDEADBEEFDEADBEEFDEADBEEFDEADBEEF"

        when WordBitWidth == 32:
          let expected = BigInt[200].fromHex"fd5bdee65f787f665f787f6"
        else:
          let expected = BigInt[200].fromHex"fd5bdee"

        r.prodhighwords(a, b, 2)
        check: bool(r == expected)
        r.prodhighwords(b, a, 2)
        check: bool(r == expected)

    test "Destination is properly zero-padded if multiplicands are too short":
      block:
        var r = BigInt[200].fromHex"0xDEADBEEFDEADBEEFDEADBEEFDEADBEEFDEADBEEFDEADBEEFDE"
        let a = BigInt[29].fromHex"0x12345678"
        let b = BigInt[128].fromHex"0xDEADBEEFDEADBEEFDEADBEEFDEADBEEF"

        when WordBitWidth == 32:
          let expected = BigInt[200].fromHex"fd5bdee65f787f665f787f6"
        else:
          let expected = BigInt[200].fromHex"fd5bdee"

        r.prodhighwords(a, b, 2)
        check: bool(r == expected)
        r.prodhighwords(b, a, 2)
        check: bool(r == expected)

proc mainSquare() =
  suite "Multi-precision multiplication" & " [" & $WordBitWidth & "-bit words]":
    test "Squaring is consistent with multiplication (rBits = 2*aBits)":
      block:
        let a = BigInt[200].fromHex"0xDEADBEEFDEADBEEFDEADBEEFDEADBEEFDEADBEEFDEADBEEFDE"

        var rmul, rsqr: BigInt[400]

        rmul.prod(a, a)
        rsqr.square(a)
        check: bool(rmul == rsqr)

    test "Squaring is consistent with multiplication (truncated)":
      block:
        let a = BigInt[200].fromHex"0xDEADBEEFDEADBEEFDEADBEEFDEADBEEFDEADBEEFDEADBEEFDE"

        var rmul, rsqr: BigInt[256]

        rmul.prod(a, a)
        rsqr.square(a)
        check: bool(rmul == rsqr)

proc mainModular() =
  suite "Modular operations - small modulus" & " [" & $WordBitWidth & "-bit words]":
    # Vectors taken from Stint - https://github.com/status-im/nim-stint
    test "100 mod 13":
      # Test 1 word and more than 1 word
      block:
        let a = BigInt[7].fromUint(100'u32)
        let m = BigInt[4].fromUint(13'u8)

        var r = canary(BigInt[4])
        r.reduce(a, m)
        let expected = BigInt[4].fromUint(100'u8 mod 13)
        doAssert bool(r == expected),
          "\n  r (low-level repr): " & $r &
          "\n  expected (ll repr): " & $expected

      block: #
        let a = BigInt[32].fromUint(100'u32)
        let m = BigInt[4].fromUint(13'u8)

        var r = canary(BigInt[4])
        r.reduce(a, m)
        let expected = BigInt[4].fromUint(100'u8 mod 13)
        doAssert bool(r == expected),
          "\n  r (low-level repr): " & $r &
          "\n  expected (ll repr): " & $expected

      block: #
        let a = BigInt[64].fromUint(100'u32)
        let m = BigInt[4].fromUint(13'u8)

        var r = canary(BigInt[4])
        r.reduce(a, m)
        let expected = BigInt[4].fromUint(100'u8 mod 13)
        doAssert bool(r == expected),
          "\n  r (low-level repr): " & $r &
          "\n  expected (ll repr): " & $expected

    test "2^64 mod 3":
      let a = BigInt[65].fromHex("0x10000000000000000")
      let m = BigInt[8].fromUint(3'u8)

      var r = canary(BigInt[8])
      r.reduce(a, m)
      let expected = BigInt[8].fromUint(1'u8)
      doAssert bool(r == expected),
        "\n  r (low-level repr): " & $r &
        "\n  expected (ll repr): " & $expected

    test "1234567891234567890 mod 10":
      let a = BigInt[64].fromUint(1234567891234567890'u64)
      let m = BigInt[8].fromUint(10'u8)

      var r = canary(BigInt[8])
      r.reduce(a, m)
      let expected = BigInt[8].fromUint(0'u8)
      doAssert bool(r == expected),
        "\n  r (low-level repr): " & $r &
        "\n  expected (ll repr): " & $expected

  suite "Modular operations - small modulus - Stint specific failures highlighted by property-based testing" & " [" & $WordBitWidth & "-bit words]":
    # Vectors taken from Stint - https://github.com/status-im/nim-stint
    test "Modulo: 65696211516342324 mod 174261910798982":
      let u = 65696211516342324'u64
      let v = 174261910798982'u64

      let a = BigInt[56].fromUint(u)
      let m = BigInt[48].fromUint(v)

      var r = canary(BigInt[48])
      r.reduce(a, m)

      let expected = BigInt[48].fromUint(u mod v)
      doAssert bool(r == expected),
        "\n  r (low-level repr): " & $r &
        "\n  expected (ll repr): " & $expected

    test "Modulo: 15080397990160655 mod 600432699691":
      let u = 15080397990160655'u64
      let v = 600432699691'u64

      let a = BigInt[54].fromUint(u)
      let m = BigInt[40].fromUint(v)

      var r = canary(BigInt[40])
      r.reduce(a, m)

      let expected = BigInt[40].fromUint(u mod v)
      doAssert bool(r == expected),
        "\n  r (low-level repr): " & $r &
        "\n  expected (ll repr): " & $expected

proc mainNeg() =
  suite "Conditional negation" & " [" & $WordBitWidth & "-bit words]":
    test "Conditional negation":
      block:
        var a = fromHex(BigInt[128], "0x12345678FF11FFAA00321321CAFECAFE")
        var b = fromHex(BigInt[128], "0xDEADBEEFDEADBEEFDEADBEEFDEADBEEF")

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
        var a = fromHex(BigInt[128], "0x12345678FF11FFAA00321321CAFECAFE")
        var b = fromHex(BigInt[128], "0xDEADBEEFDEADBEEFDEADBEEFDEADBEEF")

        let a2 = a
        let b2 = b

        a.cneg(CtFalse)
        b.cneg(CtFalse)

        check:
          bool(a == a2)
          bool(b == b2)

    test "Conditional negation with carries":
      block:
        var a = fromHex(BigInt[128], "0x12345678FF11FFAA00321321FFFFFFFF")
        var b = fromHex(BigInt[128], "0xFFFFFFFFFFFFFFFF0000000000000000")

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
        var a = fromHex(BigInt[128], "0x123456780000000000321321FFFFFFFF")
        var b = fromHex(BigInt[128], "0xFFFFFFFFFFFFFFFF0000000000000000")

        let a2 = a
        let b2 = b

        a.cneg(CtFalse)
        b.cneg(CtFalse)

        check:
          bool(a == a2)
          bool(b == b2)

    test "Conditional all-zero bit or all-one bit":
      block:
        var a = fromHex(BigInt[128], "0x00000000000000000000000000000000")
        var b = fromHex(BigInt[128], "0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF")

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
        var a = fromHex(BigInt[128], "0x00000000000000000000000000000000")
        var b = fromHex(BigInt[128], "0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF")

        let a2 = a
        let b2 = b

        a.cneg(CtFalse)
        b.cneg(CtFalse)

        check:
          bool(a == a2)
          bool(b == b2)

proc mainCopySwap() =
  suite "Copy and Swap" & " [" & $WordBitWidth & "-bit words]":
    test "Conditional copy":
      block:
        var a = fromHex(BigInt[128], "0x12345678FF11FFAA00321321CAFECAFE")
        let b = fromHex(BigInt[128], "0xDEADBEEFDEADBEEFDEADBEEFDEADBEEF")

        var expected = a
        a.ccopy(b, CtFalse)

        check: bool(expected == a)

      block:
        var a = fromHex(BigInt[128], "0x00000000FFFFFFFFFFFFFFFFFFFFFFFF")
        let b = fromHex(BigInt[128], "0x00000000000000000000000000000001")

        var expected = b
        a.ccopy(b, CtTrue)

        check: bool(expected == b)

    test "Conditional swap":
      block:
        var a = fromHex(BigInt[128], "0x12345678FF11FFAA00321321CAFECAFE")
        var b = fromHex(BigInt[128], "0xDEADBEEFDEADBEEFDEADBEEFDEADBEEF")

        let eA = a
        let eB = b

        a.cswap(b, CtFalse)
        check:
          bool(eA == a)
          bool(eB == b)

      block:
        var a = fromHex(BigInt[128], "0x00000000FFFFFFFFFFFFFFFFFFFFFFFF")
        var b = fromHex(BigInt[128], "0x00000000000000000000000000000001")

        let eA = b
        let eB = a

        a.cswap(b, CtTrue)
        check:
          bool(eA == a)
          bool(eB == b)

proc mainModularInverse() =
  suite "Modular Inverse (with odd modulus)" & " [" & $WordBitWidth & "-bit words]":
    # Note: We don't define multi-precision multiplication
    #       because who needs it when you have Montgomery?
    #       ¯\(ツ)/¯
    test "42^-1 (mod 2017) = 1969":
      block: # small int
        let a = BigInt[16].fromUint(42'u16)
        let M = BigInt[16].fromUint(2017'u16)

        let expected = BigInt[16].fromUint(1969'u16)
        var r = canary(BigInt[16])
        var r2 = canary(BigInt[16])

        r.invmod(a, M)
        r2.invmod_vartime(a, M)

        check:
          bool(r == expected)
          bool(r2 == expected)

      block: # huge int
        let a = BigInt[381].fromUint(42'u16)
        let M = BigInt[381].fromUint(2017'u16)

        let expected = BigInt[381].fromUint(1969'u16)
        var r = canary(BigInt[381])
        var r2 = canary(BigInt[381])

        r.invmod(a, M)
        r2.invmod_vartime(a, M)

        check:
          bool(r == expected)
          bool(r2 == expected)

    test "271^-1 (mod 383) = 106":
      block: # small int
        let a = BigInt[16].fromUint(271'u16)
        let M = BigInt[16].fromUint(383'u16)

        let expected = BigInt[16].fromUint(106'u16)
        var r = canary(BigInt[16])
        var r2 = canary(BigInt[16])

        r.invmod(a, M)
        r2.invmod_vartime(a, M)

        check:
          bool(r == expected)
          bool(r2 == expected)

      block: # huge int
        let a = BigInt[381].fromUint(271'u16)
        let M = BigInt[381].fromUint(383'u16)

        let expected = BigInt[381].fromUint(106'u16)
        var r = canary(BigInt[381])
        var r2 = canary(BigInt[381])

        r.invmod(a, M)
        r2.invmod_vartime(a, M)

        check:
          bool(r == expected)
          bool(r2 == expected)

    test "BN254_Modulus^-1 (mod BLS12_381)":
      let a = BigInt[381].fromHex("0x30644e72e131a029b85045b68181585d97816a916871ca8d3c208c16d87cfd47")
      let M = BigInt[381].fromHex("0x1a0111ea397fe69a4b1ba7b6434bacd764774b84f38512bf6730d2a0f6b0f6241eabfffeb153ffffb9feffffffffaaab")

      let expected = BigInt[381].fromHex("0x0636759a0f3034fa47174b2c0334902f11e9915b7bd89c6a2b3082b109abbc9837da17201f6d8286fe6203caa1b9d4c8")

      var r = canary(BigInt[381])
      var r2 = canary(BigInt[381])

      r.invmod(a, M)
      r2.invmod_vartime(a, M)

      check:
        bool(r == expected)
        bool(r2 == expected)

    test "0^-1 (mod any) = 0 (need for tower of extension fields)":
      block:
        let a = BigInt[16].fromUint(0'u16)
        let M = BigInt[16].fromUint(2017'u16)

        let expected = BigInt[16].fromUint(0'u16)
        var r = canary(BigInt[16])
        var r2 = canary(BigInt[16])

        r.invmod(a, M)
        r2.invmod_vartime(a, M)

        check:
          bool(r == expected)
          bool(r2 == expected)

      block:
        let a = BigInt[381].fromUint(0'u16)
        let M = BigInt[381].fromHex("0x1a0111ea397fe69a4b1ba7b6434bacd764774b84f38512bf6730d2a0f6b0f6241eabfffeb153ffffb9feffffffffaaab")

        let expected = BigInt[381].fromUint(0'u16)
        var r = canary(BigInt[381])
        var r2 = canary(BigInt[381])

        r.invmod(a, M)
        r2.invmod_vartime(a, M)

        check:
          bool(r == expected)
          bool(r2 == expected)

    test "#433 -  CryptoFuzz / Oss-Fuzz bug with unit inversion":
      block:
        let a = BigInt[255].fromUint(1'u)
        let M = BLS12_381.scalarFieldModulus()
        let F = Fr[BLS12_381].getR2modP()

        var r = canary(BigInt[255])
        var r2 = canary(BigInt[255])

        r.invmod(a, F, M)
        r2.invmod_vartime(a, F, M)

        check:
          bool(r == F)
          bool(r2 == F)

mainArith()
mainMul()
mainMulHigh()
mainSquare()
mainModular()
mainNeg()
mainCopySwap()
mainModularInverse()
