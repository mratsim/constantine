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
  # Internal
  ../constantine/arithmetic,
  ../constantine/io/[io_bigints, io_fields],
  ../constantine/config/[curves, common, type_bigint],
  # Test utilities
  ../helpers/prng_unsafe

const Iters = 24

var rng: RngState
let seed = uint32(getTime().toUnix() and (1'i64 shl 32 - 1)) # unixTime mod 2^32
rng.seed(seed)
echo "\n------------------------------------------------------\n"
echo "test_finite_fields_double_width xoshiro512** seed: ", seed

template mulTest(rng_gen: untyped): untyped =
  proc `mul _ rng_gen`(C: static Curve) =
    let a = rng_gen(rng, Fp[C])
    let b = rng.random_unsafe(Fp[C])

    var r_fp{.noInit.}, r_fpDbl{.noInit.}: Fp[C]
    var tmpDbl{.noInit.}: FpDbl[C]

    r_fp.prod(a, b)
    tmpDbl.mulNoReduce(a, b)
    r_fpDbl.reduce(tmpDbl)

    doAssert bool(r_fp == r_fpDbl)

template sqrTest(rng_gen: untyped): untyped =
  proc `sqr _ rng_gen`(C: static Curve) =
    let a = rng_gen(rng, Fp[C])

    var mulDbl{.noInit.}, sqrDbl{.noInit.}: FpDbl[C]

    mulDbl.mulNoReduce(a, a)
    sqrDbl.squareNoReduce(a)

    doAssert bool(mulDbl == sqrDbl)

mulTest(random_unsafe)
mulTest(randomHighHammingWeight)
mulTest(random_long01Seq)
sqrTest(random_unsafe)
sqrTest(randomHighHammingWeight)
sqrTest(random_long01Seq)

suite "Field Multiplication via double-width field elements is consistent with single-width." & " [" & $WordBitwidth & "-bit mode]":
  test "With P-224 field modulus":
    for _ in 0 ..< Iters:
      mul_random_unsafe(P224)
    for _ in 0 ..< Iters:
      mul_randomHighHammingWeight(P224)
    for _ in 0 ..< Iters:
      mul_random_long01Seq(P224)

  test "With P-256 field modulus":
    for _ in 0 ..< Iters:
      mul_random_unsafe(P256)
    for _ in 0 ..< Iters:
      mul_randomHighHammingWeight(P256)
    for _ in 0 ..< Iters:
      mul_random_long01Seq(P256)

  test "With BN254_Snarks field modulus":
    for _ in 0 ..< Iters:
      mul_random_unsafe(BN254_Snarks)
    for _ in 0 ..< Iters:
      mul_randomHighHammingWeight(BN254_Snarks)
    for _ in 0 ..< Iters:
      mul_random_long01Seq(BN254_Snarks)

  test "With BLS12_381 field modulus":
    for _ in 0 ..< Iters:
      mul_random_unsafe(BLS12_381)
    for _ in 0 ..< Iters:
      mul_randomHighHammingWeight(BLS12_381)
    for _ in 0 ..< Iters:
      mul_random_long01Seq(BLS12_381)

suite "Field Squaring via double-width field elements is consistent with single-width." & " [" & $WordBitwidth & "-bit mode]":
  test "With P-224 field modulus":
    for _ in 0 ..< Iters:
      sqr_random_unsafe(P224)
    for _ in 0 ..< Iters:
      sqr_randomHighHammingWeight(P224)
    for _ in 0 ..< Iters:
      sqr_random_long01Seq(P224)

  test "With P-256 field modulus":
    for _ in 0 ..< Iters:
      sqr_random_unsafe(P256)
    for _ in 0 ..< Iters:
      sqr_randomHighHammingWeight(P256)
    for _ in 0 ..< Iters:
      sqr_random_long01Seq(P256)

  test "With BN254_Snarks field modulus":
    for _ in 0 ..< Iters:
      sqr_random_unsafe(BN254_Snarks)
    for _ in 0 ..< Iters:
      sqr_randomHighHammingWeight(BN254_Snarks)
    for _ in 0 ..< Iters:
      sqr_random_long01Seq(BN254_Snarks)

  test "With BLS12_381 field modulus":
    for _ in 0 ..< Iters:
      sqr_random_unsafe(BLS12_381)
    for _ in 0 ..< Iters:
      sqr_randomHighHammingWeight(BLS12_381)
    for _ in 0 ..< Iters:
      sqr_random_long01Seq(BLS12_381)
