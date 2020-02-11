# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import  unittest, random, strutils,
        ../constantine/io/io,
        ../constantine/math/bigints_checked,
        ../constantine/config/common,
        ../constantine/primitives/constant_time

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
    let carry = a.add(b, ctrue(Word))
    check: a.isZero().bool

  test "Adding 1 zero - real addition":
    block:
      var a = fromHex(BigInt[128], "0x00000000_00000000_00000000_00000000")
      let b = fromHex(BigInt[128], "0x00000000_00000000_00000000_00000001")
      let carry = a.add(b, ctrue(Word))

      let c = fromHex(BigInt[128], "0x00000000_00000000_00000000_00000001")
      check:
        bool(a == c)
    block:
      var a = fromHex(BigInt[128], "0x00000000_00000000_00000000_00000001")
      let b = fromHex(BigInt[128], "0x00000000_00000000_00000000_00000000")
      let carry = a.add(b, ctrue(Word))

      let c = fromHex(BigInt[128], "0x00000000_00000000_00000000_00000001")
      check:
        bool(a == c)

  test "Adding 1 zero - fake addition":
    block:
      var a = fromHex(BigInt[128], "0x00000000_00000000_00000000_00000000")
      let b = fromHex(BigInt[128], "0x00000000_00000000_00000000_00000001")
      let carry = a.add(b, cfalse(Word))

      let c = a
      check:
        bool(a == c)
    block:
      var a = fromHex(BigInt[128], "0x00000000_00000000_00000000_00000001")
      let b = fromHex(BigInt[128], "0x00000000_00000000_00000000_00000000")
      let carry = a.add(b, cfalse(Word))

      let c = a
      check:
        bool(a == c)

  test "Adding non-zeros - real addition":
    block:
      var a = fromHex(BigInt[128], "0x00000000_00000001_00000000_00000000")
      let b = fromHex(BigInt[128], "0x00000000_00000000_00000000_00000001")
      let carry = a.add(b, ctrue(Word))

      let c = fromHex(BigInt[128], "0x00000000_00000001_00000000_00000001")
      check:
        bool(a == c)
    block:
      var a = fromHex(BigInt[128], "0x00000000_00000000_00000000_00000001")
      let b = fromHex(BigInt[128], "0x00000000_00000001_00000000_00000000")
      let carry = a.add(b, ctrue(Word))

      let c = fromHex(BigInt[128], "0x00000000_00000001_00000000_00000001")
      check:
        bool(a == c)

  test "Adding non-zeros - fake addition":
    block:
      var a = fromHex(BigInt[128], "0x00000000_00000001_00000000_00000000")
      let b = fromHex(BigInt[128], "0x00000000_00000000_00000000_00000001")
      let carry = a.add(b, cfalse(Word))

      let c = a
      check:
        bool(a == c)
    block:
      var a = fromHex(BigInt[128], "0x00000000_00000000_00000000_00000001")
      let b = fromHex(BigInt[128], "0x00000000_00000001_00000000_00000000")
      let carry = a.add(b, cfalse(Word))

      let c = a
      check:
        bool(a == c)

  test "Addition limbs carry":
    block:
      var a = fromHex(BigInt[128], "0x00000000_FFFFFFFF_FFFFFFFF_FFFFFFFE")
      let b = fromHex(BigInt[128], "0x00000000_00000000_00000000_00000001")
      let carry = a.add(b, ctrue(Word))

      let c = fromHex(BigInt[128], "0x00000000_FFFFFFFF_FFFFFFFF_FFFFFFFF")
      check:
        bool(a == c)
        not bool(carry)

    block:
      var a = fromHex(BigInt[128], "0x00000000_FFFFFFFF_FFFFFFFF_FFFFFFFF")
      let b = fromHex(BigInt[128], "0x00000000_00000000_00000000_00000001")
      let carry = a.add(b, ctrue(Word))

      let c = fromHex(BigInt[128], "0x00000001_00000000_00000000_00000000")
      check:
        bool(a == c)
        not bool(carry)

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
