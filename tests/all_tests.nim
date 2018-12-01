# hardy
# Copyright (c) 2018 Status Research & Development GmbH
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import  unittest, random, math,
        ../hardy

# Random seed for reproducibility
randomize(0xDEADBEEF)

template undistinct[T](x: HardBase[T]): T =
  T(x)

suite "Hardened unsigned integers":
  test "High - getting the biggest representable number":
    check:
      high(HardBase[byte]).undistinct == 0xFF.byte
      high(HardBase[uint8]).undistinct == 0xFF.uint8

      high(HardBase[uint16]).undistinct == 0xFFFF.uint16
      high(HardBase[uint32]).undistinct == 0xFFFFFFFF.uint32
      high(HardBase[uint64]).undistinct == 0xFFFFFFFF_FFFFFFFF.uint64

  test "bitwise `and`, `or`, `xor`, `not`":
    let x1 = rand(high(int)).uint64
    let y1 = rand(high(int)).uint64
    let x2 = rand(high(int)).uint64
    let y2 = rand(high(int)).uint64
    let x3 = rand(high(int)).uint64
    let y3 = rand(high(int)).uint64
    template bitwise_check(op: untyped): untyped =
      block:
        check:
          op(hard(0'u32), hard(0'u32)).undistinct == op(0'u32, 0'u32)
          op(hard(0'u32), hard(1'u32)).undistinct == op(0'u32, 1'u32)
          op(hard(1234'u64), hard(5678'u64)).undistinct == op(1234'u64, 5678'u64)

          op(x1.hard, y1.hard).undistinct == op(x1, y1)
          op(x2.hard, y2.hard).undistinct == op(x2, y2)
          op(x3.hard, y3.hard).undistinct == op(x3, y3)
    bitwise_check(`and`)
    bitwise_check(`or`)
    bitwise_check(`xor`)

    block:
      check:
        not(hard(0'u32)).undistinct == not 0'u32
        not(hard(1'u32)).undistinct == not 1'u32
        not(hard(1234'u64)).undistinct == not 1234'u64
        not(hard(5678'u64)).undistinct == not 5678'u32
        not(hard(x1)).undistinct == not x1
        not(hard(x2)).undistinct == not x2
        not(hard(x3)).undistinct == not x3
        not(hard(y1)).undistinct == not y1
        not(hard(y2)).undistinct == not y2
        not(hard(y3)).undistinct == not y3

  test "Logical shifts":
    let x1 = rand(high(int)).uint64
    let y1 = rand(high(int)).uint64
    let x2 = rand(high(int)).uint64
    let y2 = rand(high(int32)).uint64
    let x3 = rand(high(int32)).uint64
    let y3 = rand(high(int32)).uint64

    let s1 = rand(10)
    let s2 = rand(10)
    let s3 = rand(10)

    template shift_check(op: untyped): untyped =
      block:
        check:
          op(hard(0'u32), 1).undistinct == op(0'u32, 1)
          op(hard(1'u32), 2).undistinct == op(1'u32, 2)
          op(hard(1234'u64), 3).undistinct == op(1234'u64, 3)
          op(hard(2'u64^30), 1).undistinct == op(2'u64^30, 1)
          op(hard(2'u64^31 + 1), 1).undistinct == op(2'u64^31 + 1, 1)
          op(hard(2'u64^32), 1).undistinct == op(2'u64^32, 1)

          op(x1.hard, s1).undistinct == op(x1, s1)
          op(x2.hard, s2).undistinct == op(x2, s2)
          op(x3.hard, s3).undistinct == op(x3, s3)


          op(y1.hard, s1).undistinct == op(y1, s1)
          op(y2.hard, s2).undistinct == op(y2, s2)
          op(y3.hard, s3).undistinct == op(y3, s3)

    shift_check(`shl`)
    shift_check(`shr`)


  test "Operators `+`, `-`, `*`":
    let x1 = rand(high(int)).uint64
    let y1 = rand(high(int)).uint64
    let x2 = rand(high(int)).uint64
    let y2 = rand(high(int)).uint64
    let x3 = rand(high(int)).uint64
    let y3 = rand(high(int)).uint64
    template operator_check(op: untyped): untyped =
      block:
        check:
          op(hard(0'u32), hard(0'u32)).undistinct == op(0'u32, 0'u32)
          op(hard(0'u32), hard(1'u32)).undistinct == op(0'u32, 1'u32)
          op(hard(1234'u64), hard(5678'u64)).undistinct == op(1234'u64, 5678'u64)

          op(x1.hard, y1.hard).undistinct == op(x1, y1)
          op(x2.hard, y2.hard).undistinct == op(x2, y2)
          op(x3.hard, y3.hard).undistinct == op(x3, y3)
    operator_check(`+`)
    operator_check(`-`)
    operator_check(`*`)

  test "Unary `-`, returning the 2-complement of an unsigned integer":
    let x1 = rand(high(int)).uint64
    let y1 = rand(high(int)).uint64
    let x2 = rand(high(int)).uint64
    let y2 = rand(high(int)).uint64
    let x3 = rand(high(int)).uint64
    let y3 = rand(high(int)).uint64
    check:
      (-hard(0'u32)).undistinct == 0
      (-high(HardBase[uint32])).undistinct == 1'u32
      (-hard(0x80000000'u32)).undistinct == 0x80000000'u32 # This is low(int32) == 0b10000..0000

      undistinct(-x1.hard) == undistinct(not(x1.hard) + hard(1'u64))
      undistinct(-x2.hard) == undistinct(not(x2.hard) + hard(1'u64))
      undistinct(-x3.hard) == undistinct(not(x3.hard) + hard(1'u64))
      undistinct(-y1.hard) == undistinct(not(y1.hard) + hard(1'u64))
      undistinct(-y2.hard) == undistinct(not(y2.hard) + hard(1'u64))
      undistinct(-y3.hard) == undistinct(not(y3.hard) + hard(1'u64))
