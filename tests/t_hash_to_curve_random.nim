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
  # Internals
  constantine/named/algebras,
  constantine/named/zoo_subgroups,
  constantine/math/extension_fields,
  constantine/math/ec_shortweierstrass,
  constantine/math/io/io_ec,
  constantine/hash_to_curve/hash_to_curve,
  constantine/hashes,
  # Test utilities
  helpers/prng_unsafe

const Iters = 6

# Random seed for reproducibility
var rng: RngState
let seed = uint32(getTime().toUnix() and (1'i64 shl 32 - 1)) # unixTime mod 2^32
rng.seed(seed)
echo "\n------------------------------------------------------\n"
echo "Hash-to-curve (randomized) xoshiro512** seed: ", seed

proc testH2C_consistency[EC: EC_ShortW](curve: typedesc[EC]) =
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
      testH2C_consistency(EC_ShortW_Aff[Fp[BLS12_381], G1])
  test "BLS12-381 G2":
    for i in 0 ..< Iters:
      testH2C_consistency(EC_ShortW_Aff[Fp2[BLS12_381], G2])
  test "BN254_Snarks G1":
    for i in 0 ..< Iters:
      testH2C_consistency(EC_ShortW_Aff[Fp[BN254_Snarks], G1])
  test "BN254_Snarks G2":
    for i in 0 ..< Iters:
      testH2C_consistency(EC_ShortW_Aff[Fp2[BN254_Snarks], G2])

proc testH2C_guidovranken_fuzz_failure_2() =
  # From Guido Vranken differential fuzzing
  # Summing elliptic curve on an isogeny was mistakenly not fully reducing HHH_or_Mpre
  let msg = [
      uint8 0xa7, 0x1b, 0x0a, 0x38, 0xd4, 0x09, 0x2b, 0x3b,
            0xdc, 0x9e, 0x75, 0x0a, 0x27, 0x0a, 0xd5, 0xdd,
            0x16, 0x6f, 0x32, 0x5c, 0x16, 0xf5, 0x6d, 0x2f,
            0x87, 0xbb, 0x6b, 0xf5, 0xd2]
  let dst = [
      uint8 0x5a, 0x59, 0xae, 0x59, 0x04, 0x8a, 0x29, 0x0f,
            0x9a, 0xc1, 0x80, 0x26, 0xba, 0x6d, 0xd8, 0x7f,
            0x54, 0xf0, 0x5a, 0x01, 0x49, 0xad, 0x2b, 0x95,
            0xfe]
  let aug = [
      uint8 0x70, 0x20, 0xde, 0x7c, 0x51, 0x88, 0x88, 0x54,
            0xf1, 0xaf, 0xa5, 0x06, 0x78, 0x80, 0xde, 0xf0,
            0x0d, 0xdf]

  var r{.noInit}: EC_ShortW_Jac[Fp[BLS12_381], G1]
  sha256.hashToCurve(128, r, aug, msg, dst)

  let expected = EC_ShortW_Jac[Fp[BLS12_381], G1].fromHex(
    x = "0x48f2bbee30aa236feaa7fb924d8a3de3090ff160f9972a8afda302bd248248527dcc59ce195cd5f5a1488417cfc64cc",
    y = "0xe91b0a3cdea4981741791c8e9b4287d2f693c6626d8e4408ecaaa473e6ff2f691f5f23f8b7b46bdf3560e7cca67e5bc"
  )

  doAssert bool(r == expected)

suite "Hash-to-curve anti-regression":
  test "BLS12-381 G1 - Fuzzing Failure 2":
    testH2C_guidovranken_fuzz_failure_2()
