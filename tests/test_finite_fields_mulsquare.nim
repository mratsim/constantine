# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import  std/unittest, std/times,
        ../constantine/arithmetic/[bigints, finite_fields],
        ../constantine/io/[io_bigints, io_fields],
        ../constantine/config/curves,
        # Test utilities
        ./prng

const Iters = 128

var rng: RngState
let seed = uint32(getTime().toUnix() and (1'i64 shl 32 - 1)) # unixTime mod 2^32
rng.seed(seed)
echo "test_finite_fields_mulsquare xoshiro512** seed: ", seed

static: doAssert defined(testingCurves), "This modules requires the -d:testingCurves compile option"

import ../constantine/config/common

proc mainSanity() =
  suite "Modular squaring is consistent with multiplication on special elements":
    test "Squaring 0,1,2 mod 101 [FastSquaring = " & $Fake101.canUseNoCarryMontySquare & "]":
      block: # 0² mod
        var n: Fp[Fake101]

        n.fromUint(0'u32)
        let expected = n

        var r: Fp[Fake101]
        r.square(n)

        check: bool(r == expected)

      block: # 1² mod
        var n: Fp[Fake101]

        n.fromUint(1'u32)
        let expected = n

        var r: Fp[Fake101]
        r.square(n)

        check: bool(r == expected)

      block: # 2² mod
        var n, expected: Fp[Fake101]

        n.fromUint(2'u32)
        expected.fromUint(4'u32)

        var r: Fp[Fake101]
        r.square(n)

        check: bool(r == expected)

    test "Squaring 0,1,2 mod 2^61-1 [FastSquaring = " & $Mersenne61.canUseNoCarryMontySquare & "]":
      block: # 0² mod
        var n: Fp[Mersenne61]

        n.fromUint(0'u32)
        let expected = n

        var r: Fp[Mersenne61]
        r.square(n)

        check: bool(r == expected)

      block: # 1² mod
        var n: Fp[Mersenne61]

        n.fromUint(1'u32)
        let expected = n

        var r: Fp[Mersenne61]
        r.square(n)

        check: bool(r == expected)

      block: # 2² mod
        var n, expected: Fp[Mersenne61]

        n.fromUint(2'u32)
        expected.fromUint(4'u32)

        var r: Fp[Mersenne61]
        r.square(n)

        check: bool(r == expected)

    test "Squaring 0,1,2 mod 2^127-1 [FastSquaring = " & $Mersenne127.canUseNoCarryMontySquare & "]":
      block: # 0² mod
        var n: Fp[Mersenne127]

        n.fromUint(0'u32)
        let expected = n

        var r: Fp[Mersenne127]
        r.square(n)

        check: bool(r == expected)

      block: # 1² mod
        var n: Fp[Mersenne127]

        n.fromUint(1'u32)
        let expected = n

        var r: Fp[Mersenne127]
        r.square(n)

        check: bool(r == expected)

      block: # 2² mod
        var n, expected: Fp[Mersenne127]

        n.fromUint(2'u32)
        expected.fromUint(4'u32)

        var r: Fp[Mersenne127]
        r.square(n)

        check: bool(r == expected)

    test "Squaring 0,1,2 mod P-224 [FastSquaring = " & $P224.canUseNoCarryMontySquare & "]":
      # P224 can use the fast path in 32-bit mode but not in 64-bit mode
      block: # 0² mod
        var n: Fp[P224]

        n.fromUint(0'u32)
        let expected = n

        var r: Fp[P224]
        r.square(n)

        check: bool(r == expected)

      block: # 1² mod
        var n: Fp[P224]

        n.fromUint(1'u32)
        let expected = n

        var r: Fp[P224]
        r.square(n)

        var r2: Fp[P224]
        r2.prod(n, n)

        check: bool(r == expected)

      block: # 2² mod
        var n, expected: Fp[P224]

        n.fromUint(2'u32)
        expected.fromUint(4'u32)

        var r: Fp[P224]
        r.square(n)

        check: bool(r == expected)

    test "Squaring 0,1,2 mod P-256 [FastSquaring = " & $P256.canUseNoCarryMontySquare & "]":
      block: # 0² mod
        var n: Fp[P256]

        n.fromUint(0'u32)
        let expected = n

        var r: Fp[P256]
        r.square(n)

        check: bool(r == expected)

      block: # 1² mod
        var n: Fp[P256]

        n.fromUint(1'u32)
        let expected = n

        var r: Fp[P256]
        r.square(n)

        var r2: Fp[P256]
        r2.prod(n, n)

        check: bool(r == expected)

      block: # 2² mod
        var n, expected: Fp[P256]

        n.fromUint(2'u32)
        expected.fromUint(4'u32)

        var r: Fp[P256]
        r.square(n)

        check: bool(r == expected)

    test "Squaring 0,1,2 mod BLS12_381 [FastSquaring = " & $BLS12_381.canUseNoCarryMontySquare & "]":
      block: # 0² mod
        var n: Fp[BLS12_381]

        n.fromUint(0'u32)
        let expected = n

        var r: Fp[BLS12_381]
        r.square(n)

        check: bool(r == expected)

      block: # 1² mod
        var n: Fp[BLS12_381]

        n.fromUint(1'u32)
        let expected = n

        var r: Fp[BLS12_381]
        r.square(n)

        var r2: Fp[BLS12_381]
        r2.prod(n, n)

        check: bool(r == expected)

      block: # 2² mod
        var n, expected: Fp[BLS12_381]

        n.fromUint(2'u32)
        expected.fromUint(4'u32)

        var r: Fp[BLS12_381]
        r.square(n)

        check: bool(r == expected)

mainSanity()

proc mainSelectCases() =
  suite "Modular Squaring: selected tricky cases":
    test "P-256 [FastSquaring = " & $P256.canUseNoCarryMontySquare & "]":
      block:
        # Triggered an issue in the (t[N+1], t[N]) = t[N] + (A1, A0)
        # between the squaring and reduction step, with t[N+1] and A1 being carry bits.
        var a: Fp[P256]
        a.fromHex"0xa0da36b4885df98997ee89a22a7ceb64fa431b2ecc87342fc083587da3d6ebc7"

        var r_mul, r_sqr: Fp[P256]

        r_mul.prod(a, a)
        r_sqr.square(a)

        doAssert bool(r_mul == r_sqr)

mainSelectCases()

proc randomCurve(C: static Curve) =
  let a = rng.random(Fp[C])

  var r_mul, r_sqr: Fp[C]

  r_mul.prod(a, a)
  r_sqr.square(a)

  doAssert bool(r_mul == r_sqr)

suite "Random Modular Squaring is consistent with Modular Multiplication":
  test "Random squaring mod P-224 [FastSquaring = " & $P224.canUseNoCarryMontySquare & "]":
    for _ in 0 ..< Iters:
      randomCurve(P224)

  test "Random squaring mod P-256 [FastSquaring = " & $P256.canUseNoCarryMontySquare & "]":
    for _ in 0 ..< Iters:
      randomCurve(P256)

  test "Random squaring mod BLS12_381 [FastSquaring = " & $BLS12_381.canUseNoCarryMontySquare & "]":
    for _ in 0 ..< Iters:
      randomCurve(BLS12_381)
