# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import  unittest, random,
        ../constantine/[io, bigints, word_types]

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
