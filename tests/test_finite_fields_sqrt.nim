# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import  ../constantine/[arithmetic, primitives],
        ../constantine/io/[io_fields],
        ../constantine/config/[curves, common],
        # Test utilities
        ../helpers/prng,
        # Standard library
        std/tables,
        std/unittest, std/times

const Iters = 128

var rng: RngState
let seed = uint32(getTime().toUnix() and (1'i64 shl 32 - 1)) # unixTime mod 2^32
rng.seed(seed)
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
          bool a.sqrt_if_square_p3mod4()

        # 2 different code paths have the same result
        # (despite 2 square roots existing per square)
        a2.sqrt_p3mod4()
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
          bool not a.sqrt_if_square_p3mod4()
          bool (a == a2) # a shouldn't be modified

proc randomSqrtCheck_p3mod4(C: static Curve) =
  test "Random square root check for p ≡ 3 (mod 4) on " & $Curve(C):
    for _ in 0 ..< Iters:
      let a = rng.random(Fp[C])
      var na{.noInit.}: Fp[C]
      na.neg(a)

      var a2 = a
      var na2 = na
      a2.square()
      na2.square()
      check:
        bool a2 == na2
        bool a2.isSquare()

      var r, s = a2
      r.sqrt_p3mod4()
      let ok = s.sqrt_if_square_p3mod4()
      check:
        bool ok
        bool(r == s)
        bool(r == a or r == na)

proc main() =
  suite "Modular square root":
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

main()
