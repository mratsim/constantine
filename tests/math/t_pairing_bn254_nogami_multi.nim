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
  ../../constantine/platforms/abstractions,
  ../../constantine/math/[arithmetic, extension_fields, ec_shortweierstrass],
  ../../constantine/math/io/io_extfields,
  ../../constantine/math/config/curves,
  ../../constantine/math/pairing/pairing_bn,
  # Test utilities
  ../../helpers/prng_unsafe

# Testing multipairing
# ----------------------------------------------

var rng: RngState
let timeseed = uint32(toUnix(getTime()) and (1'i64 shl 32 - 1)) # unixTime mod 2^32
seed(rng, timeseed)
echo "\n------------------------------------------------------\n"
echo "test_pairing_bn254_nogami_multi xoshiro512** seed: ", timeseed

proc testMultiPairing(rng: var RngState, N: static int) =
  var
    Ps {.noInit.}: array[N, ECP_ShortW_Aff[Fp[BN254_Nogami], G1]]
    Qs {.noInit.}: array[N, ECP_ShortW_Aff[Fp2[BN254_Nogami], G2]]

    GTs {.noInit.}: array[N, Fp12[BN254_Nogami]]

  for i in 0 ..< N:
    Ps[i] = rng.random_unsafe(typeof(Ps[0]))
    Qs[i] = rng.random_unsafe(typeof(Qs[0]))

  # Simple pairing
  let clockSimpleStart = cpuTime()
  var GTsimple {.noInit.}: Fp12[BN254_Nogami]
  for i in 0 ..< N:
    GTs[i].pairing_bn(Ps[i], Qs[i])

  GTsimple = GTs[0]
  for i in 1 ..< N:
    GTsimple *= GTs[i]
  let clockSimpleStop = cpuTime()

  # Multipairing
  let clockMultiStart = cpuTime()
  var GTmulti {.noInit.}: Fp12[BN254_Nogami]
  GTmulti.pairing_bn(Ps, Qs)
  let clockMultiStop = cpuTime()

  echo &"N={N}, Simple: {clockSimpleStop - clockSimpleStart:>4.4f}s, Multi: {clockMultiStop - clockMultiStart:>4.4f}s"
  doAssert bool GTsimple == GTmulti

staticFor i, 1, 17:
  rng.testMultiPairing(N = i)
