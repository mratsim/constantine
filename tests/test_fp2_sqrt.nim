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
  ../constantine/[arithmetic, primitives],
  ../constantine/towers,
  ../constantine/config/curves,
  # Test utilities
  ../helpers/prng_unsafe

const Iters = 128

var rng: RngState
let seed = uint32(getTime().toUnix() and (1'i64 shl 32 - 1)) # unixTime mod 2^32
rng.seed(seed)
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
  suite "Modular square root":
    randomSqrtCheck_p3mod4 BN254_Snarks
    randomSqrtCheck_p3mod4 BLS12_381

main()
