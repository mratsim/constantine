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
  ../constantine/config/common,
  ../constantine/[arithmetic, primitives],
  ../constantine/towers,
  ../constantine/config/curves,
  ../constantine/io/io_towers,
  # Test utilities
  ../helpers/prng_unsafe

const Iters = 128

var rng: RngState
let seed = uint32(getTime().toUnix() and (1'i64 shl 32 - 1)) # unixTime mod 2^32
rng.seed(seed)
echo "\n------------------------------------------------------\n"
echo "test_fp2_sqrt xoshiro512** seed: ", seed

proc randomSqrtCheck_p3mod4(C: static Curve) =
  test "[𝔽p2] Random square root check for p ≡ 3 (mod 4) on " & $Curve(C):
    for _ in 0 ..< Iters:
      let a = rng.random_unsafe(Fp2[C])
      var na{.noInit.}: Fp2[C]
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
  suite "Modular square root" & " [" & $WordBitwidth & "-bit mode]":
    randomSqrtCheck_p3mod4 BN254_Snarks
    randomSqrtCheck_p3mod4 BLS12_381

  suite "Modular square root - 32-bit bugs highlighted by property-based testing " & " [" & $WordBitwidth & "-bit mode]":
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

main()
