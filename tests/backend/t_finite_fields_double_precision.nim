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
  ../../constantine/backend/arithmetic,
  ../../constantine/backend/io/[io_bigints, io_fields],
  ../../constantine/backend/config/[curves, common, type_bigint],
  # Test utilities
  ../../helpers/prng_unsafe

const Iters = 24

var rng: RngState
let seed = uint32(getTime().toUnix() and (1'i64 shl 32 - 1)) # unixTime mod 2^32
rng.seed(seed)
echo "\n------------------------------------------------------\n"
echo "test_finite_fields_double_precision xoshiro512** seed: ", seed

template addsubnegTest(rng_gen: untyped): untyped =
  proc `addsubneg _ rng_gen`(C: static Curve) =
    # Try to exercise all code paths for in-place/out-of-place add/sum/sub/diff/double/neg
    # (1 - (-a) - b + (-a) - 2a) + (2a + 2b + (-b))  == 1
    let aFp = rng_gen(rng, Fp[C])
    let bFp = rng_gen(rng, Fp[C])
    var accumFp {.noInit.}: Fp[C]
    var OneFp {.noInit.}: Fp[C]
    var accum {.noInit.}, One {.noInit.}, a{.noInit.}, na{.noInit.}, b{.noInit.}, nb{.noInit.}, a2 {.noInit.}, b2 {.noInit.}: FpDbl[C]

    OneFp.setOne()
    One.prod2x(OneFp, OneFp)
    a.prod2x(aFp, OneFp)
    b.prod2x(bFp, OneFp)

    block: # sanity check
      var t: Fp[C]
      t.redc2x(One)
      doAssert bool t.isOne()

    a2.sum2xMod(a, a)
    na.neg2xMod(a)

    block: # sanity check
      var t0, t1: Fp[C]
      t0.redc2x(na)
      t1.neg(aFp)
      doAssert bool(t0 == t1),
        "Beware, if the hex are the same, it means the outputs are the same (mod p),\n" &
        "but one might not be completely reduced\n" &
        "  t0: " & t0.toHex() & "\n" &
        "  t1: " & t1.toHex() & "\n"

    block: # sanity check
      var t0, t1: Fp[C]
      t0.redc2x(a2)
      t1.double(aFp)
      doAssert bool(t0 == t1),
        "Beware, if the hex are the same, it means the outputs are the same (mod p),\n" &
        "but one might not be completely reduced\n" &
        "  t0: " & t0.toHex() & "\n" &
        "  t1: " & t1.toHex() & "\n"

    b2.sum2xMod(b, b)
    nb.neg2xMod(b)

    accum.diff2xMod(One, na)
    accum.diff2xMod(accum, b)
    accum.sum2xMod(accum, na)
    accum.diff2xMod(accum, a2)

    var t{.noInit.}: FpDbl[C]
    t.sum2xMod(a2, b2)
    t.sum2xMod(t, nb)

    accum.sum2xMod(accum, t)
    accumFp.redc2x(accum)
    doAssert bool accumFp.isOne(),
        "Beware, if the hex are the same, it means the outputs are the same (mod p),\n" &
        "but one might not be completely reduced\n" &
        "  accumFp: " & accumFp.toHex()

template mulTest(rng_gen: untyped): untyped =
  proc `mul _ rng_gen`(C: static Curve) =
    let a = rng_gen(rng, Fp[C])
    let b = rng_gen(rng, Fp[C])

    var r_fp{.noInit.}, r_fpDbl{.noInit.}: Fp[C]
    var tmpDbl{.noInit.}: FpDbl[C]

    r_fp.prod(a, b)
    tmpDbl.prod2x(a, b)
    r_fpDbl.redc2x(tmpDbl)

    doAssert bool(r_fp == r_fpDbl)

template sqrTest(rng_gen: untyped): untyped =
  proc `sqr _ rng_gen`(C: static Curve) =
    let a = rng_gen(rng, Fp[C])

    var mulDbl{.noInit.}, sqrDbl{.noInit.}: FpDbl[C]

    mulDbl.prod2x(a, a)
    sqrDbl.square2x(a)

    doAssert bool(mulDbl == sqrDbl),
      "\nOriginal: " & a.mres.limbs.toString() &
      "\n  Mul: " & mulDbl.limbs2x.toString() &
      "\n  Sqr: " & sqrDbl.limbs2x.toString()

addsubnegTest(random_unsafe)
addsubnegTest(randomHighHammingWeight)
addsubnegTest(random_long01Seq)
mulTest(random_unsafe)
mulTest(randomHighHammingWeight)
mulTest(random_long01Seq)
sqrTest(random_unsafe)
sqrTest(randomHighHammingWeight)
sqrTest(random_long01Seq)

suite "Field Addition/Substraction/Negation via double-precision field elements" & " [" & $WordBitwidth & "-bit mode]":
  test "With P-224 field modulus":
    for _ in 0 ..< Iters:
      addsubneg_random_unsafe(P224)
    for _ in 0 ..< Iters:
      addsubneg_randomHighHammingWeight(P224)
    for _ in 0 ..< Iters:
      addsubneg_random_long01Seq(P224)

  test "With P-256 field modulus":
    for _ in 0 ..< Iters:
      addsubneg_random_unsafe(P256)
    for _ in 0 ..< Iters:
      addsubneg_randomHighHammingWeight(P256)
    for _ in 0 ..< Iters:
      addsubneg_random_long01Seq(P256)

  test "With BN254_Snarks field modulus":
    for _ in 0 ..< Iters:
      addsubneg_random_unsafe(BN254_Snarks)
    for _ in 0 ..< Iters:
      addsubneg_randomHighHammingWeight(BN254_Snarks)
    for _ in 0 ..< Iters:
      addsubneg_random_long01Seq(BN254_Snarks)

  test "With BLS12_381 field modulus":
    for _ in 0 ..< Iters:
      addsubneg_random_unsafe(BLS12_381)
    for _ in 0 ..< Iters:
      addsubneg_randomHighHammingWeight(BLS12_381)
    for _ in 0 ..< Iters:
      addsubneg_random_long01Seq(BLS12_381)

  test "With Curve25519 field modulus":
    for _ in 0 ..< Iters:
      addsubneg_random_unsafe(Curve25519)
    for _ in 0 ..< Iters:
      addsubneg_randomHighHammingWeight(Curve25519)
    for _ in 0 ..< Iters:
      addsubneg_random_long01Seq(Curve25519)

  test "With Bandersnatch field modulus":
    for _ in 0 ..< Iters:
      addsubneg_random_unsafe(Bandersnatch)
    for _ in 0 ..< Iters:
      addsubneg_randomHighHammingWeight(Bandersnatch)
    for _ in 0 ..< Iters:
      addsubneg_random_long01Seq(Bandersnatch)

  test "Negate 0 returns 0 (unique Montgomery repr)":
    var a: FpDbl[BN254_Snarks]
    var r {.noInit.}: FpDbl[BN254_Snarks]
    r.neg2xMod(a)

    check: bool r.isZero()

suite "Field Multiplication via double-precision field elements is consistent with single-width." & " [" & $WordBitwidth & "-bit mode]":
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

  test "With Curve25519 field modulus":
    for _ in 0 ..< Iters:
      mul_random_unsafe(Curve25519)
    for _ in 0 ..< Iters:
      mul_randomHighHammingWeight(Curve25519)
    for _ in 0 ..< Iters:
      mul_random_long01Seq(Curve25519)

  test "With Bandersnatch field modulus":
    for _ in 0 ..< Iters:
      mul_random_unsafe(Bandersnatch)
    for _ in 0 ..< Iters:
      mul_randomHighHammingWeight(Bandersnatch)
    for _ in 0 ..< Iters:
      mul_random_long01Seq(Bandersnatch)

suite "Field Squaring via double-precision field elements is consistent with single-width." & " [" & $WordBitwidth & "-bit mode]":
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

  test "With Curve25519 field modulus":
    for _ in 0 ..< Iters:
      sqr_random_unsafe(Curve25519)
    for _ in 0 ..< Iters:
      sqr_randomHighHammingWeight(Curve25519)
    for _ in 0 ..< Iters:
      sqr_random_long01Seq(Curve25519)

  test "With Bandersnatch field modulus":
    for _ in 0 ..< Iters:
      sqr_random_unsafe(Bandersnatch)
    for _ in 0 ..< Iters:
      sqr_randomHighHammingWeight(Bandersnatch)
    for _ in 0 ..< Iters:
      sqr_random_long01Seq(Bandersnatch)