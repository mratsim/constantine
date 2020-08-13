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

const Iters = 128

var rng: RngState
let seed = 0 # uint32(getTime().toUnix() and (1'i64 shl 32 - 1)) # unixTime mod 2^32
rng.seed(seed)
echo "\n------------------------------------------------------\n"
echo "test_finite_fields_double_width xoshiro512** seed: ", seed

proc randomCurve(C: static Curve) =
  let a = rng.random_unsafe(Fp[C])
  let b = rng.random_unsafe(Fp[C])

  var r_fp, r_fpDbl: Fp[C]
  var tmpDbl: FpDbl[C]

  r_fp.prod(a, b)
  tmpDbl.mulNoReduce(a, b)
  r_fpDbl.reduce(tmpDbl)

  echo "expected: ", r_fp.mres.limbs.toString
  echo "computed: ", r_fpDbl.mres.limbs.toString

  doAssert bool(r_fp == r_fpDbl)

proc randomHighHammingWeight(C: static Curve) =
  let a = rng.random_highHammingWeight(Fp[C])
  let b = rng.random_highHammingWeight(Fp[C])

  var r_fp, r_fpDbl: Fp[C]
  var tmpDbl: FpDbl[C]

  r_fp.prod(a, b)
  tmpDbl.mulNoReduce(a, b)
  r_fpDbl.reduce(tmpDbl)

  doAssert bool(r_fp == r_fpDbl)

proc random_long01Seq(C: static Curve) =
  let a = rng.random_long01Seq(Fp[C])
  let b = rng.random_long01Seq(Fp[C])

  var r_fp, r_fpDbl: Fp[C]
  var tmpDbl: FpDbl[C]

  r_fp.prod(a, b)
  tmpDbl.mulNoReduce(a, b)
  r_fpDbl.reduce(tmpDbl)

  doAssert bool(r_fp == r_fpDbl)

suite "Field Multiplication via double-width field elements is consistent with single-width." & " [" & $WordBitwidth & "-bit mode]":
  # test "With P-224 field modulus":
  #   for _ in 0 ..< Iters:
  #     randomCurve(P224)
  #   for _ in 0 ..< Iters:
  #     randomHighHammingWeight(P224)
  #   for _ in 0 ..< Iters:
  #     random_long01Seq(P224)

  # test "With P-256 field modulus":
  #   for _ in 0 ..< Iters:
  #     randomCurve(P256)
  #   for _ in 0 ..< Iters:
  #     randomHighHammingWeight(P256)
  #   for _ in 0 ..< Iters:
  #     random_long01Seq(P256)

  test "With BN254_Snarks field modulus":
    for _ in 0 ..< Iters:
      randomCurve(BN254_Snarks)
    for _ in 0 ..< Iters:
      randomHighHammingWeight(BN254_Snarks)
    for _ in 0 ..< Iters:
      random_long01Seq(BN254_Snarks)

  # test "With BLS12_381 field modulus":
  #   for _ in 0 ..< 1:
  #     randomCurve(BLS12_381)
  #   # for _ in 0 ..< Iters:
  #   #   randomHighHammingWeight(BLS12_381)
  #   # for _ in 0 ..< Iters:
  #   #   random_long01Seq(BLS12_381)
