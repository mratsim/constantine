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
  # Internals
  constantine/platforms/abstractions,
  constantine/math/arithmetic,
  constantine/math/extension_fields,
  constantine/named/algebras,
  constantine/math/io/io_extfields,
  # Test utilities
  helpers/prng_unsafe

const
  Iters = 8
  TestCurves = [
    BN254_Nogami,
    BN254_Snarks,
    BLS12_377,
    BLS12_381
  ]

type
  RandomGen = enum
    Uniform
    HighHammingWeight
    Long01Sequence

var rng: RngState
let seed = 1611432811 # uint32(getTime().toUnix() and (1'i64 shl 32 - 1)) # unixTime mod 2^32
rng.seed(seed)
echo "\n------------------------------------------------------\n"
echo "test_fp2_sqrt xoshiro512** seed: ", seed

func random_elem(rng: var RngState, F: typedesc, gen: RandomGen): F {.inline, noInit.} =
  if gen == Uniform:
    result = rng.random_unsafe(F)
  elif gen == HighHammingWeight:
    result = rng.random_highHammingWeight(F)
  else:
    result = rng.random_long01Seq(F)

proc randomSqrtCheck(Name: static Algebra, gen: RandomGen) =
  for _ in 0 ..< Iters:
    let a = rng.random_elem(Fp2[Name], gen)
    var na{.noInit.}: Fp2[Name]
    na.neg(a)

    var a2 = a
    var na2 = na
    a2.square()
    na2.square()
    check:
      bool a2 == na2
      bool a2.isSquare()

    var r, s = a2
    # r.sqrt()
    let ok = s.sqrt_if_square()
    check:
      bool ok
      # bool(r == s)
      bool(s == a or s == na)

proc main() =
  suite "Modular square root" & " [" & $WordBitWidth & "-bit words]":
    staticFor(curve, TestCurves):
      test "[𝔽p2] Random square root check for " & $curve:
        randomSqrtCheck(curve, gen = Uniform)
        randomSqrtCheck(curve, gen = HighHammingWeight)
        randomSqrtCheck(curve, gen = Long01Sequence)

  suite "Modular square root - 32-bit bugs highlighted by property-based testing " & " [" & $WordBitWidth & "-bit words]":
    test "sqrt_if_square invalid square BLS12_381 - #64":
      var a: Fp2[BLS12_381]
      a.fromHex(
        "0x09f7034e1d37628dec7be400ddd098110c9160e1de63637d73bd93796f311fb50d438ef357a9349d245fbcfcb6fccf01",
        "0x033c9b2f17988d8bea494fde020f54fb33cc780bba53e4f6746783ac659d472d9f616516fcf87f0d9a980243d38afeee"
      )
      check:
        bool not a.isSquare()
        bool not a.sqrt_if_square()

    test "sqrt_if_square invalid square BLS12_381 - #65-3":
      var a: Fp2[BLS12_381]
      a.fromHex(
        "0x061bd0f645de26f928386c9393711ba30cabcee5b493f1c3502b33d1cf4e80ed6a9433fe51ec48ce3b28fa748a5cbf93",
        "0x105eddcc7fca28805a016b5a01723c632bad32dd8d5de66457dfe73807e226772e653b3e37c3dea0248f98847efa9a85"
      )
      check:
        bool not a.isSquare()
        bool not a.sqrt_if_square()

  suite "Modular square root - Assembly bugs highlighted by property-based testing " & " [" & $WordBitWidth & "-bit words]":
    test "Don't set Neg(Zero) fields to modulus (non-unique Montgomery repr) - #136":
      # https://github.com/mratsim/constantine/issues/136
      # and https://github.com/mratsim/constantine/issues/114
      # The assembly implementation of neg didn't check
      # after M-a if a was zero and so while in mod M
      # M ≡ 0 (mod M), the `==` doesn't support unreduced representation.
      # Seed: 1611432811
      let a = Fp2[BN254_Snarks].fromHex(
        "0x0e097bc0990edfae676ba36f7879462c09b7eb28f6450b6dd3de438dc58f0d9c",
        "0x0000000000000000000000000000000000000000000000000000000000000000"
      )
      var na{.noInit.}: Fp2[BN254_Snarks]
      na.neg(a)

      var a2 = a
      var na2 = na
      a2.square()
      na2.square()
      check:
        bool a2 == na2
        bool a2.isSquare()

      var r, s = a2
      # r.sqrt()
      let ok = s.sqrt_if_square()

      check:
        bool ok
        # bool(r == s)
        bool(s == a or s == na)
main()
