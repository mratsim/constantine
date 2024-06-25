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
  constantine/platforms/abstractions,
  constantine/math/arithmetic,
  constantine/math/io/[io_bigints, io_fields],
  constantine/named/algebras,
  # Test utilities
  helpers/prng_unsafe

const Iters = 24

var rng: RngState
let seed = uint32(getTime().toUnix() and (1'i64 shl 32 - 1)) # unixTime mod 2^32
rng.seed(seed)
echo "\n------------------------------------------------------\n"
echo "test_fr xoshiro512** seed: ", seed

proc sanity(Name: static Algebra) =
  test "Fr: Squaring 0,1,2 with "& $Fr[Name] & " [FastSquaring = " & $(Fr[Name].getSpareBits() >= 2) & "]":
        block: # 0² mod
          var n: Fr[Name]

          n.fromUint(0'u32)
          let expected = n

          # Out-of-place
          var r: Fr[Name]
          r.square(n)
          # In-place
          n.square()

          check:
            bool(r == expected)
            bool(n == expected)

        block: # 1² mod
          var n: Fr[Name]

          n.fromUint(1'u32)
          let expected = n

          # Out-of-place
          var r: Fr[Name]
          r.square(n)
          # In-place
          n.square()

          check:
            bool(r == expected)
            bool(n == expected)

        block: # 2² mod
          var n, expected: Fr[Name]

          n.fromUint(2'u32)
          expected.fromUint(4'u32)

          # Out-of-place
          var r: Fr[Name]
          r.square(n)
          # In-place
          n.square()

          check:
            bool(r == expected)
            bool(n == expected)

proc mainSanity() =
  suite "Fr: Modular squaring is consistent with multiplication on special elements" & " [" & $WordBitWidth & "-bit words]":
    sanity BN254_Snarks
    sanity BLS12_381

mainSanity()

proc randomCurve(Name: static Algebra) =
  let a = rng.random_unsafe(Fr[Name])

  var r_mul, r_sqr: Fr[Name]

  r_mul.prod(a, a)
  r_sqr.square(a)

  doAssert bool(r_mul == r_sqr)

proc randomHighHammingWeight(Name: static Algebra) =
  let a = rng.random_highHammingWeight(Fr[Name])

  var r_mul, r_sqr: Fr[Name]

  r_mul.prod(a, a)
  r_sqr.square(a)

  doAssert bool(r_mul == r_sqr)

proc random_long01Seq(Name: static Algebra) =
  let a = rng.random_long01Seq(Fr[Name])

  var r_mul, r_sqr: Fr[Name]

  r_mul.prod(a, a)
  r_sqr.square(a)

  doAssert bool(r_mul == r_sqr)

suite "Fr: Random Modular Squaring is consistent with Modular Multiplication" & " [" & $WordBitWidth & "-bit words]":
  test "Random squaring mod r_BN254_Snarks [FastSquaring = " & $(Fr[BN254_Snarks].getSpareBits() >= 2) & "]":
    for _ in 0 ..< Iters:
      randomCurve(BN254_Snarks)
    for _ in 0 ..< Iters:
      randomHighHammingWeight(BN254_Snarks)
    for _ in 0 ..< Iters:
      random_long01Seq(BN254_Snarks)

  test "Random squaring mod r_BLS12_381 [FastSquaring = " & $(Fr[BLS12_381].getSpareBits() >= 2) & "]":
    for _ in 0 ..< Iters:
      randomCurve(BLS12_381)
    for _ in 0 ..< Iters:
      randomHighHammingWeight(BLS12_381)
    for _ in 0 ..< Iters:
      random_long01Seq(BLS12_381)
