# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  # Standard library
  std/[unittest, times, os, strutils],
  # Internals
  ../constantine/math/config/curves,
  ../constantine/math/extension_fields,
  ../constantine/math/ec_shortweierstrass,
  ../constantine/hash_to_curve/hash_to_curve,
  ../constantine/hashes,
  ../constantine/math/constants/zoo_subgroups,
  # Test utilities
  ../helpers/prng_unsafe

const Iters = 6

# Random seed for reproducibility
var rng: RngState
let seed = uint32(getTime().toUnix() and (1'i64 shl 32 - 1)) # unixTime mod 2^32
rng.seed(seed)
echo "\n------------------------------------------------------\n"
echo "Hash-to-curve (randomized) xoshiro512** seed: ", seed

proc testH2C_consistency[EC: ECP_ShortW](curve: typedesc[EC]) =
  var P{.noInit.}: EC
  let msg = rng.random_byte_seq(32)
  sha256.hashToCurve(
    k = 128,
    output = P,
    augmentation = "",
    message = msg,
    domainSepTag = "H2C-CONSTANTINE-TESTSUITE"
  )

  doAssert bool isOnCurve(P.x, P.y,  EC.G)
  doAssert bool isInSubgroup(P)

suite "Hash-to-curve produces points on curve and in correct subgroup":
  test "BLS12-381 G1":
    for i in 0 ..< Iters:
      testH2C_consistency(ECP_ShortW_Aff[Fp[BLS12_381], G1])
  test "BLS12-381 G2":
    for i in 0 ..< Iters:
      testH2C_consistency(ECP_ShortW_Aff[Fp2[BLS12_381], G2])
  test "BN254_Snarks G1":
    for i in 0 ..< Iters:
      testH2C_consistency(ECP_ShortW_Aff[Fp[BN254_Snarks], G1])
  test "BN254_Snarks G2":
    for i in 0 ..< Iters:
      testH2C_consistency(ECP_ShortW_Aff[Fp2[BN254_Snarks], G2])