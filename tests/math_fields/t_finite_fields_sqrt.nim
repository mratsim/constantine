# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  # Standard library
  std/[tables, unittest, times],
  # Internal
  constantine/platforms/abstractions,
  constantine/math/arithmetic,
  constantine/math/io/io_fields,
  constantine/named/algebras,
  # Test utilities
  helpers/prng_unsafe


const Iters = 8

var rng: RngState
let seed = uint32(getTime().toUnix() and (1'i64 shl 32 - 1)) # unixTime mod 2^32
rng.seed(seed)
echo "\n------------------------------------------------------\n"
echo "test_finite_fields_sqrt xoshiro512** seed: ", seed

static: doAssert defined(CTT_TEST_CURVES), "This modules requires the -d:CTT_TEST_CURVES compile option"

proc exhaustiveCheck(Name: static Algebra, modulus: static int) =
  test "Exhaustive square root check for " & $Algebra(Name):
    var squares_to_roots: Table[uint16, set[uint16]]

    # Create all squares
    # -------------------------
    for i in 0'u16 ..< modulus:
      var a{.noInit.}: Fp[Name]
      a.fromUint(i)

      a.square()

      var r_bytes: array[8, byte]
      r_bytes.marshal(a, cpuEndian)
      let r = uint16(cast[uint64](r_bytes))

      squares_to_roots.mgetOrPut(r, default(set[uint16])).incl(i)

    # From Euler's criterion
    # there is exactly (p-1)/2 squares in 𝔽p* (without 0)
    # and so (p-1)/2 + 1 in 𝔽p (with 0)
    check: squares_to_roots.len == (modulus-1) div 2 + 1

    # Check squares
    # -------------------------
    for i in 0'u16 ..< modulus:
      var a{.noInit.}: Fp[Name]
      a.fromUint(i)

      if i in squares_to_roots:
        var a2 = a
        check:
          bool a.isSquare()
          bool a.sqrt_if_square()

        # 2 different code paths have the same result
        # (despite 2 square roots existing per square)
        a2.sqrt()
        check: bool(a == a2)

        var r_bytes: array[8, byte]
        r_bytes.marshal(a, cpuEndian)
        let r = uint16(cast[uint64](r_bytes))

        # r is one of the 2 square roots of `i`
        check: r in squares_to_roots[i]

      else:
        let a2 = a

        check:
          bool not a.isSquare()
          bool not a.sqrt_if_square()

template testSqrtImpl(a: untyped): untyped {.dirty.} =
  var na{.noInit.}: typeof(a)
  na.neg(a)

  var a2 = a
  var na2 = na
  a2.square()
  na2.square()
  check:
    bool a2 == na2
    bool a2.isSquare()

  var r, s = a2
  r.sqrt()
  let ok = s.sqrt_if_square()
  check:
    bool ok
    bool(r == s)
    bool(r == a or r == na)

proc randomSqrtCheck(Name: static Algebra) =
  test "Random square root check for " & $Algebra(Name):
    for _ in 0 ..< Iters:
      let a = rng.random_unsafe(Fp[Name])
      testSqrtImpl(a)

    for _ in 0 ..< Iters:
      let a = rng.randomHighHammingWeight(Fp[Name])
      testSqrtImpl(a)

    for _ in 0 ..< Iters:
      let a = rng.random_long01Seq(Fp[Name])
      testSqrtImpl(a)

template testSqrtRatioImpl(u, v: untyped): untyped {.dirty.} =
  var u_over_v, r{.noInit.}: typeof(v)
  u_over_v.inv(v)
  u_over_v *= u

  let qr = r.sqrt_ratio_if_square(u, v)
  check: bool(qr) == bool(u_over_v.isSquare())

  if bool(qr):
    r.square()
    check: bool(r == u_over_v)

proc randomSqrtRatioCheck(Name: static Algebra) =
  test "Random square root check for " & $Algebra(Name):
    for _ in 0 ..< Iters:
      let u = rng.random_unsafe(Fp[Name])
      let v = rng.random_unsafe(Fp[Name])
      testSqrtRatioImpl(u, v)

    for _ in 0 ..< Iters:
      let u = rng.randomHighHammingWeight(Fp[Name])
      let v = rng.randomHighHammingWeight(Fp[Name])
      testSqrtRatioImpl(u, v)

    for _ in 0 ..< Iters:
      let u = rng.random_long01Seq(Fp[Name])
      let v = rng.random_long01Seq(Fp[Name])
      testSqrtRatioImpl(u, v)

proc main() =
  suite "Modular square root" & " [" & $WordBitWidth & "-bit words]":
    exhaustiveCheck Fake103, 103
    # exhaustiveCheck Fake10007, 10007
    # exhaustiveCheck Fake65519, 65519
    randomSqrtCheck BN254_Nogami
    randomSqrtCheck BN254_Snarks
    randomSqrtCheck BLS12_377 # p ≢ 3 (mod 4)
    randomSqrtCheck BLS12_381
    randomSqrtCheck BW6_761
    randomSqrtCheck Edwards25519
    randomSqrtCheck Jubjub
    randomSqrtCheck Bandersnatch
    randomSqrtCheck Pallas
    randomSqrtCheck Vesta

  suite "Modular sqrt(u/v)" & " [" & $WordBitWidth & "-bit words]":
    randomSqrtRatioCheck Edwards25519
    randomSqrtRatioCheck Jubjub
    randomSqrtRatioCheck Bandersnatch
    randomSqrtRatioCheck Pallas
    randomSqrtRatioCheck Vesta

  suite "Modular square root - 32-bit bugs highlighted by property-based testing " & " [" & $WordBitWidth & "-bit words]":
    # test "FKM12_447 - #30": - Deactivated, we don't support the curve as no one uses it.
    #   var a: Fp[FKM12_447]
    #   a.fromHex"0x406e5e74ee09c84fa0c59f2db3ac814a4937e2f57ecd3c0af4265e04598d643c5b772a6549a2d9b825445c34b8ba100fe8d912e61cfda43d"
    #   a.square()
    #   check: bool a.isSquare()

    test "Fused modular square root on 32-bit - inconsistent with isSquare - #42":
      var a: Fp[BLS12_381]
      a.fromHex"0x184d02ce4f24d5e59b4150a57a31b202fd40a4b41d7518c22b84bee475fbcb7763100448ef6b17a6ea603cf062e5db51"
      check:
        bool(not a.isSquare())
        bool(not a.sqrt_if_square())

    test "Fused modular square root on 32-bit - inconsistent with isSquare - #43":
      var a: Fp[BLS12_381]
      a.fromHex"0x0f16d7854229d8804bcadd889f70411d6a482bde840d238033bf868e89558d39d52f9df60b2d745e02584375f16c34a3"
      check:
        bool(not a.isSquare())
        bool(not a.sqrt_if_square())

    test "Fp[2^127 - 1] - #61":
      var a: Fp[Mersenne127]
      a.fromHex"0x75bfffefbfffffff7fd9dfd800000000"
      testSqrtImpl(a)

    test "Fp[2^127 - 1] - #62":
      var a: Fp[Mersenne127]
      a.fromHex"0x7ff7ffffffffffff1dfb7fafc0000000"
      testSqrtImpl(a)

main()
