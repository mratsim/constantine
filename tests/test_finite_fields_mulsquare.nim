# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  # Standard library
  std/[unittest, times],
  # Internal
  ../constantine/arithmetic,
  ../constantine/io/[io_bigints, io_fields],
  ../constantine/config/[curves, common],
  # Test utilities
  ../helpers/prng_unsafe

const Iters = 128

var rng: RngState
let seed = uint32(getTime().toUnix() and (1'i64 shl 32 - 1)) # unixTime mod 2^32
rng.seed(seed)
echo "test_finite_fields_mulsquare xoshiro512** seed: ", seed

static: doAssert defined(testingCurves), "This modules requires the -d:testingCurves compile option"

proc sanity(C: static Curve) =
  test "Squaring 0,1,2 with "& $Curve(C) & " [FastSquaring = " & $C.canUseNoCarryMontySquare & "]":
        block: # 0² mod
          var n: Fp[C]

          n.fromUint(0'u32)
          let expected = n

          # Out-of-place
          var r: Fp[C]
          r.square(n)
          # In-place
          n.square()

          check:
            bool(r == expected)
            bool(n == expected)

        block: # 1² mod
          var n: Fp[C]

          n.fromUint(1'u32)
          let expected = n

          # Out-of-place
          var r: Fp[C]
          r.square(n)
          # In-place
          n.square()

          check:
            bool(r == expected)
            bool(n == expected)

        block: # 2² mod
          var n, expected: Fp[C]

          n.fromUint(2'u32)
          expected.fromUint(4'u32)

          # Out-of-place
          var r: Fp[C]
          r.square(n)
          # In-place
          n.square()

          check:
            bool(r == expected)
            bool(n == expected)

proc mainSanity() =
  suite "Modular squaring is consistent with multiplication on special elements":
    sanity Fake101
    sanity Mersenne61
    sanity Mersenne127
    sanity P224         # P224 uses the fast-path with 64-bit words and the slow path with 32-bit words
    sanity P256
    sanity BLS12_381

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
  let a = rng.random_unsafe(Fp[C])

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
