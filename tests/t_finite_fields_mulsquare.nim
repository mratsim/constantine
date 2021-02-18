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
  ../constantine/config/[curves, common, type_bigint],
  # Test utilities
  ../helpers/prng_unsafe

const Iters = 24

var rng: RngState
let seed = uint32(getTime().toUnix() and (1'i64 shl 32 - 1)) # unixTime mod 2^32
rng.seed(seed)
echo "\n------------------------------------------------------\n"
echo "test_finite_fields_mulsquare xoshiro512** seed: ", seed

static: doAssert defined(testingCurves), "This modules requires the -d:testingCurves compile option"

proc sanity(C: static Curve) =
  test "Squaring 0,1,2 with "& $Curve(C) & " [FastSquaring = " & $(Fp[C].getSpareBits() >= 2) & "]":
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
  suite "Modular squaring is consistent with multiplication on special elements" & " [" & $WordBitwidth & "-bit mode]":
    sanity Fake101
    sanity Mersenne61
    sanity Mersenne127
    sanity P224         # P224 uses the fast-path with 64-bit words and the slow path with 32-bit words
    sanity P256
    sanity BLS12_381

mainSanity()

proc mainSelectCases() =
  suite "Modular Squaring: selected tricky cases" & " [" & $WordBitwidth & "-bit mode]":
    test "P-256 [FastSquaring = " & $(Fp[P256].getSpareBits() >= 2) & "]":
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

proc randomHighHammingWeight(C: static Curve) =
  let a = rng.random_highHammingWeight(Fp[C])

  var r_mul, r_sqr: Fp[C]

  r_mul.prod(a, a)
  r_sqr.square(a)

  doAssert bool(r_mul == r_sqr)

proc random_long01Seq(C: static Curve) =
  let a = rng.random_long01Seq(Fp[C])

  var r_mul, r_sqr: Fp[C]

  r_mul.prod(a, a)
  r_sqr.square(a)

  doAssert bool(r_mul == r_sqr)

suite "Random Modular Squaring is consistent with Modular Multiplication" & " [" & $WordBitwidth & "-bit mode]":
  test "Random squaring mod P-224 [FastSquaring = " & $(Fp[P224].getSpareBits() >= 2) & "]":
    for _ in 0 ..< Iters:
      randomCurve(P224)
    for _ in 0 ..< Iters:
      randomHighHammingWeight(P224)
    for _ in 0 ..< Iters:
      random_long01Seq(P224)

  test "Random squaring mod P-256 [FastSquaring = " & $(Fp[P256].getSpareBits() >= 2) & "]":
    for _ in 0 ..< Iters:
      randomCurve(P256)
    for _ in 0 ..< Iters:
      randomHighHammingWeight(P256)
    for _ in 0 ..< Iters:
      random_long01Seq(P256)

  test "Random squaring mod BLS12_381 [FastSquaring = " & $(Fp[BLS12_381].getSpareBits() >= 2) & "]":
    for _ in 0 ..< Iters:
      randomCurve(BLS12_381)
    for _ in 0 ..< Iters:
      randomHighHammingWeight(BLS12_381)
    for _ in 0 ..< Iters:
      random_long01Seq(BLS12_381)

suite "Modular squaring - bugs highlighted by property-based testing":
  test "a² == (-a)² on for Fp[2^127 - 1] - #61":
    var a{.noInit.}: Fp[Mersenne127]
    a.fromHex"0x75bfffefbfffffff7fd9dfd800000000"

    var na{.noInit.}: Fp[Mersenne127]

    na.neg(a)

    a.square()
    na.square()

    doAssert bool(a == na),
      "\n   a² : " & a.mres.limbs.toString() &
      "\n (-a)²: " & na.mres.limbs.toString()

    var a2{.noInit.}, na2{.noInit.}: Fp[Mersenne127]
    a2.fromHex"0x75bfffefbfffffff7fd9dfd800000000"
    na2.neg(a2)

    a2 *= a2
    na2 *= na2

    doAssert(
      bool(a2 == na2) and
      bool(a2 == a) and
      bool(a2 == na),
        "\n   a*a:     " & a2.mres.limbs.toString() &
        "\n (-a)*(-a): " & na2.mres.limbs.toString()
    )

  test "a² == (-a)² on for Fp[2^127 - 1] - #62":
    var a{.noInit.}: Fp[Mersenne127]
    a.fromHex"0x7ff7ffffffffffff1dfb7fafc0000000"

    var na{.noInit.}: Fp[Mersenne127]

    na.neg(a)

    a.square()
    na.square()

    doAssert bool(a == na),
      "\n   a² : " & a.mres.limbs.toString() &
      "\n (-a)²: " & na.mres.limbs.toString()

    var a2{.noInit.}, na2{.noInit.}: Fp[Mersenne127]
    a2.fromHex"0x7ff7ffffffffffff1dfb7fafc0000000"
    na2.neg(a2)

    a2 *= a2
    na2 *= na2

    doAssert(
      bool(a2 == na2) and
      bool(a2 == a) and
      bool(a2 == na),
        "\n   a*a:     " & a2.mres.limbs.toString() &
        "\n (-a)*(-a): " & na2.mres.limbs.toString()
    )

  test "32-bit fast squaring on BLS12-381 - #42":
    # x = -(2^63 + 2^62 + 2^60 + 2^57 + 2^48 + 2^16)
    # p = (x - 1)^2 * (x^4 - x^2 + 1)//3 + x
    # Fp       = GF(p)
    # a = Fp(Integer('0x091F02EFA1C9B99C004329E94CD3C6B308164CBE02037333D78B6C10415286F7C51B5CD7F917F77B25667AB083314B1B'))
    # a2 = a*a
    # print('a²: ' + Integer(a2).hex())

    var a{.noInit.}, expected{.noInit.}: Fp[BLS12_381]
    a.fromHex"0x091F02EFA1C9B99C004329E94CD3C6B308164CBE02037333D78B6C10415286F7C51B5CD7F917F77B25667AB083314B1B"
    expected.fromHex"0x129e84715b197f76766c8604002cfc287fbe3d16774e18c599853ce48d03dc26bf882e159323ee3d25e52e4809ff4ccc"

    var a2mul = a
    var a2sqr = a

    a2mul.prod(a, a)
    a2sqr.square(a)

    check:
      bool(a2mul == expected)
      bool(a2sqr == expected)

  test "32-bit fast squaring on BLS12-381 - #43":
    # x = -(2^63 + 2^62 + 2^60 + 2^57 + 2^48 + 2^16)
    # p = (x - 1)^2 * (x^4 - x^2 + 1)//3 + x
    # Fp       = GF(p)
    # a = Fp(Integer('0x0B7C8AFE5D43E9A973AF8649AD8C733B97D06A78CFACD214CBE9946663C3F682362E0605BC8318714305B249B505AFD9'))
    # a2 = a*a
    # print('a²: ' + Integer(a2).hex())

    var a{.noInit.}, expected{.noInit.}: Fp[BLS12_381]
    a.fromHex"0x0B7C8AFE5D43E9A973AF8649AD8C733B97D06A78CFACD214CBE9946663C3F682362E0605BC8318714305B249B505AFD9"
    expected.fromHex"0x94b12b599042198a4ad5ad05ed4da1a3332fe50518b6eb718d258d7e3c60a48a89f7417a0b413b92537c24c9e94e038"

    var a2mul = a
    var a2sqr = a

    a2mul.prod(a, a)
    a2sqr.square(a)

    check:
      bool(a2mul == expected)
      bool(a2sqr == expected)
