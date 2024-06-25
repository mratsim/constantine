# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import  std/[unittest, times, math],
        constantine/platforms/abstractions,
        helpers/prng_unsafe

# Random seed for reproducibility
var rng: RngState
let seed = uint32(getTime().toUnix() and (1'i64 shl 32 - 1)) # unixTime mod 2^32
rng.seed(seed)
echo "\n------------------------------------------------------\n"
echo "test_primitives xoshiro512** seed: ", seed

template undistinct[T](x: Ct[T]): T =
  T(x)

proc main() =
  suite "Constant-time unsigned integers" & " [" & $WordBitWidth & "-bit words]":
    test "High - getting the biggest representable number":
      check:
        high(Ct[byte]).undistinct == 0xFF.byte
        high(Ct[uint8]).undistinct == 0xFF'u8

        high(Ct[uint16]).undistinct == 0xFFFF'u16
        high(Ct[uint32]).undistinct == 0xFFFFFFFF'u32
        high(Ct[uint64]).undistinct == 0xFFFFFFFF_FFFFFFFF'u64

    test "bitwise `and`, `or`, `xor`, `not`":
      let x1 = rng.random_unsafe(uint64)
      let y1 = rng.random_unsafe(uint64)
      let x2 = rng.random_unsafe(uint64)
      let y2 = rng.random_unsafe(uint64)
      let x3 = rng.random_unsafe(uint64)
      let y3 = rng.random_unsafe(uint64)
      template bitwise_check(op: untyped): untyped =
        block:
          check:
            op(ct(0'u32), ct(0'u32)).undistinct == op(0'u32, 0'u32)
            op(ct(0'u32), ct(1'u32)).undistinct == op(0'u32, 1'u32)
            op(ct(1234'u64), ct(5678'u64)).undistinct == op(1234'u64, 5678'u64)

            op(x1.ct, y1.ct).undistinct == op(x1, y1)
            op(x2.ct, y2.ct).undistinct == op(x2, y2)
            op(x3.ct, y3.ct).undistinct == op(x3, y3)
      bitwise_check(`and`)
      bitwise_check(`or`)
      bitwise_check(`xor`)

      block:
        check:
          not(ct(0'u32)).undistinct == not 0'u32
          not(ct(1'u32)).undistinct == not 1'u32
          not(ct(1234'u64)).undistinct == not 1234'u64
          not(ct(5678'u64)).undistinct == not 5678'u64
          not(ct(x1)).undistinct == not x1
          not(ct(x2)).undistinct == not x2
          not(ct(x3)).undistinct == not x3
          not(ct(y1)).undistinct == not y1
          not(ct(y2)).undistinct == not y2
          not(ct(y3)).undistinct == not y3

    test "Logical shifts":
      let x1 = rng.random_unsafe(uint64)
      let y1 = rng.random_unsafe(uint64)
      let x2 = rng.random_unsafe(uint64)
      let y2 = rng.random_unsafe(uint64)
      let x3 = rng.random_unsafe(uint64)
      let y3 = rng.random_unsafe(uint64)

      let s1 = uint64 rng.random_unsafe(10)
      let s2 = uint64 rng.random_unsafe(10)
      let s3 = uint64 rng.random_unsafe(10)

      template shift_check(op: untyped): untyped =
        block:
          check:
            op(ct(0'u32), 1).undistinct == op(0'u32, 1)
            op(ct(1'u32), 2).undistinct == op(1'u32, 2)
            op(ct(1234'u64), 3).undistinct == op(1234'u64, 3)
            op(ct(2'u64^30), 1).undistinct == op(2'u64^30, 1)
            op(ct(2'u64^31 + 1), 1).undistinct == op(2'u64^31 + 1, 1)
            op(ct(2'u64^32), 1).undistinct == op(2'u64^32, 1)

            op(x1.ct, s1).undistinct == op(x1, s1)
            op(x2.ct, s2).undistinct == op(x2, s2)
            op(x3.ct, s3).undistinct == op(x3, s3)


            op(y1.ct, s1).undistinct == op(y1, s1)
            op(y2.ct, s2).undistinct == op(y2, s2)
            op(y3.ct, s3).undistinct == op(y3, s3)

      shift_check(`shl`)
      shift_check(`shr`)


    test "Operators `+`, `-`, `*`":
      let x1 = rng.random_unsafe(uint64)
      let y1 = rng.random_unsafe(uint64)
      let x2 = rng.random_unsafe(uint64)
      let y2 = rng.random_unsafe(uint64)
      let x3 = rng.random_unsafe(uint64)
      let y3 = rng.random_unsafe(uint64)
      template operator_check(op: untyped): untyped =
        block:
          check:
            op(ct(0'u32), ct(0'u32)).undistinct == op(0'u32, 0'u32)
            op(ct(0'u32), ct(1'u32)).undistinct == op(0'u32, 1'u32)
            op(ct(1234'u64), ct(5678'u64)).undistinct == op(1234'u64, 5678'u64)

            op(x1.ct, y1.ct).undistinct == op(x1, y1)
            op(x2.ct, y2.ct).undistinct == op(x2, y2)
            op(x3.ct, y3.ct).undistinct == op(x3, y3)
      operator_check(`+`)
      operator_check(`-`)
      operator_check(`*`)

    test "Unary `-`, returning the 2-complement of an unsigned integer":
      let x1 = rng.random_unsafe(uint64)
      let y1 = rng.random_unsafe(uint64)
      let x2 = rng.random_unsafe(uint64)
      let y2 = rng.random_unsafe(uint64)
      let x3 = rng.random_unsafe(uint64)
      let y3 = rng.random_unsafe(uint64)
      check:
        (-ct(0'u32)).undistinct == 0
        (-high(Ct[uint32])).undistinct == 1'u32
        (-ct(0x80000000'u32)).undistinct == 0x80000000'u32 # This is low(int32) == 0b10000..0000

        undistinct(-x1.ct) == undistinct(not(x1.ct) + ct(1'u64))
        undistinct(-x2.ct) == undistinct(not(x2.ct) + ct(1'u64))
        undistinct(-x3.ct) == undistinct(not(x3.ct) + ct(1'u64))
        undistinct(-y1.ct) == undistinct(not(y1.ct) + ct(1'u64))
        undistinct(-y2.ct) == undistinct(not(y2.ct) + ct(1'u64))
        undistinct(-y3.ct) == undistinct(not(y3.ct) + ct(1'u64))

  suite "Constant-time booleans":
    test "Boolean not":
      check:
        not(ctrue(uint32)).bool == false
        not(cfalse(uint32)).bool == true

    test "Comparison":
      check:
        bool(ct(0'u32) != ct(0'u32)) == false
        bool(ct(0'u32) != ct(1'u32)) == true

        bool(ct(10'u32) == ct(10'u32)) == true
        bool(ct(10'u32) != ct(20'u32)) == true

        bool(ct(10'u32) <= ct(10'u32)) == true
        bool(ct(10'u32) <= ct(20'u32)) == true
        bool(ct(10'u32) <= ct(5'u32)) == false
        bool(ct(10'u32) <= ct(0xFFFFFFFF'u32)) == true

        bool(ct(10'u32) < ct(10'u32)) == false
        bool(ct(10'u32) < ct(20'u32)) == true
        bool(ct(10'u32) < ct(5'u32)) == false
        bool(ct(10'u32) < ct(0xFFFFFFFF'u32)) == true

        bool(ct(10'u32) > ct(10'u32)) == false
        bool(ct(10'u32) > ct(20'u32)) == false
        bool(ct(10'u32) > ct(5'u32)) == true
        bool(ct(10'u32) > ct(0xFFFFFFFF'u32)) == false

        bool(ct(10'u32) >= ct(10'u32)) == true
        bool(ct(10'u32) >= ct(20'u32)) == false
        bool(ct(10'u32) >= ct(5'u32)) == true
        bool(ct(10'u32) >= ct(0xFFFFFFFF'u32)) == false

    test "Multiplexer/selector - mux(ctl, x, y) <=> ctl? x: y":
      let u = 10'u32.ct
      let v = 20'u32.ct
      let w = 5'u32.ct

      let y = ctrue(uint32)
      let n = cfalse(uint32)

      check:
        bool(mux(y, u, v) == u)
        bool(mux(n, u, v) == v)

        bool(mux(y, u, w) == u)
        bool(mux(n, u, w) == w)

        bool(mux(y, v, w) == v)
        bool(mux(n, v, w) == w)

main()
