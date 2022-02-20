# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  # Standard library
  std/[os, times, strformat],
  # Internals
  ../../constantine/backend/config/common,
  ../../constantine/backend/[
    arithmetic, primitives,
    towers, ec_shortweierstrass
  ],
  ../../constantine/backend/io/io_towers,
  ../../constantine/backend/config/curves,
  ../../constantine/backend/pairing/pairing_bls12,
  # Test utilities
  ../../helpers/prng_unsafe

# Testing multipairing
# ----------------------------------------------

var rng: RngState
let timeseed = uint32(toUnix(getTime()) and (1'i64 shl 32 - 1)) # unixTime mod 2^32
seed(rng, timeseed)
echo "\n------------------------------------------------------\n"
echo "test_pairing_bls12_381_multi xoshiro512** seed: ", timeseed

proc testMultiPairing(rng: var RngState, N: static int) =
  var
    Ps {.noInit.}: array[N, ECP_ShortW_Aff[Fp[BLS12_381], G1]]
    Qs {.noInit.}: array[N, ECP_ShortW_Aff[Fp2[BLS12_381], G2]]

    GTs {.noInit.}: array[N, Fp12[BLS12_381]]

  for i in 0 ..< N:
    Ps[i] = rng.random_unsafe(typeof(Ps[0]))
    Qs[i] = rng.random_unsafe(typeof(Qs[0]))

  # Simple pairing
  let clockSimpleStart = cpuTime()
  var GTsimple {.noInit.}: Fp12[BLS12_381]
  for i in 0 ..< N:
    GTs[i].pairing_bls12(Ps[i], Qs[i])

  GTsimple = GTs[0]
  for i in 1 ..< N:
    GTsimple *= GTs[i]
  let clockSimpleStop = cpuTime()

  # Multipairing
  let clockMultiStart = cpuTime()
  var GTmulti {.noInit.}: Fp12[BLS12_381]
  GTmulti.pairing_bls12(Ps, Qs)
  let clockMultiStop = cpuTime()

  echo &"N={N}, Simple: {clockSimpleStop - clockSimpleStart:>4.4f}s, Multi: {clockMultiStop - clockMultiStart:>4.4f}s"
  doAssert bool GTsimple == GTmulti

staticFor i, 1, 17:
  rng.testMultiPairing(N = i)
