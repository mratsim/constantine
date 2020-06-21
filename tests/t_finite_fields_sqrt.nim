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
  ../constantine/[arithmetic, primitives],
  ../constantine/io/[io_fields],
  ../constantine/config/[curves, common],
  # Test utilities
  ../helpers/prng_unsafe


const Iters = 128

var rng: RngState
let seed = uint32(getTime().toUnix() and (1'i64 shl 32 - 1)) # unixTime mod 2^32
rng.seed(seed)
echo "\n------------------------------------------------------\n"
echo "test_finite_fields_sqrt xoshiro512** seed: ", seed

static: doAssert defined(testingCurves), "This modules requires the -d:testingCurves compile option"

proc exhaustiveCheck_p3mod4(C: static Curve, modulus: static int) =
  test "Exhaustive square root check for p ≡ 3 (mod 4) on " & $Curve(C):
    var squares_to_roots: Table[uint16, set[uint16]]

    # Create all squares
    # -------------------------
    for i in 0'u16 ..< modulus:
      var a{.noInit.}: Fp[C]
      a.fromUint(i)

      a.square()

      var r_bytes: array[8, byte]
      r_bytes.exportRawUint(a, cpuEndian)
      let r = uint16(cast[uint64](r_bytes))

      squares_to_roots.mgetOrPut(r, default(set[uint16])).incl(i)

    # From Euler's criterion
    # there is exactly (p-1)/2 squares in 𝔽p* (without 0)
    # and so (p-1)/2 + 1 in 𝔽p (with 0)
    check: squares_to_roots.len == (modulus-1) div 2 + 1

    # Check squares
    # -------------------------
    for i in 0'u16 ..< modulus:
      var a{.noInit.}: Fp[C]
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
        r_bytes.exportRawUint(a, cpuEndian)
        let r = uint16(cast[uint64](r_bytes))

        # r is one of the 2 square roots of `i`
        check: r in squares_to_roots[i]

      else:
        let a2 = a

        check:
          bool not a.isSquare()
          bool not a.sqrt_if_square()
          bool (a == a2) # a shouldn't be modified

template testImpl(a: untyped): untyped {.dirty.} =
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

proc randomSqrtCheck_p3mod4(C: static Curve) =
  test "Random square root check for p ≡ 3 (mod 4) on " & $Curve(C):
    for _ in 0 ..< Iters:
      let a = rng.random_unsafe(Fp[C])
      testImpl(a)

    for _ in 0 ..< Iters:
      let a = rng.randomHighHammingWeight(Fp[C])
      testImpl(a)

    for _ in 0 ..< Iters:
      let a = rng.random_long01Seq(Fp[C])
      testImpl(a)

proc main() =
  suite "Modular square root" & " [" & $WordBitwidth & "-bit mode]":
    exhaustiveCheck_p3mod4 Fake103, 103
    exhaustiveCheck_p3mod4 Fake10007, 10007
    exhaustiveCheck_p3mod4 Fake65519, 65519
    randomSqrtCheck_p3mod4 Mersenne61
    randomSqrtCheck_p3mod4 Mersenne127
    randomSqrtCheck_p3mod4 BN254_Nogami
    randomSqrtCheck_p3mod4 BN254_Snarks
    randomSqrtCheck_p3mod4 P256
    randomSqrtCheck_p3mod4 Secp256k1
    randomSqrtCheck_p3mod4 BLS12_381
    randomSqrtCheck_p3mod4 BN446
    randomSqrtCheck_p3mod4 FKM12_447
    randomSqrtCheck_p3mod4 BLS12_461
    randomSqrtCheck_p3mod4 BN462

  suite "Modular square root - 32-bit bugs highlighted by property-based testing " & " [" & $WordBitwidth & "-bit mode]":
    test "FKM12_447 - #30":
      var a: Fp[FKM12_447]
      a.fromHex"0x406e5e74ee09c84fa0c59f2db3ac814a4937e2f57ecd3c0af4265e04598d643c5b772a6549a2d9b825445c34b8ba100fe8d912e61cfda43d"
      a.square()
      check: bool a.isSquare()

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
      testImpl(a)

    test "Fp[2^127 - 1] - #62":
      var a: Fp[Mersenne127]
      a.fromHex"0x7ff7ffffffffffff1dfb7fafc0000000"
      testImpl(a)

main()
