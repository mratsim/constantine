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
  Iters = 2
  TestCurves = [
    BN254_Snarks,
    BLS12_381
  ]

type
  RandomGen = enum
    Uniform
    HighHammingWeight
    Long01Sequence

var rng: RngState
let seed = uint32(getTime().toUnix() and (1'i64 shl 32 - 1)) # unixTime mod 2^32
rng.seed(seed)
echo "\n------------------------------------------------------\n"
echo "test_fp12_exponentiation xoshiro512** seed: ", seed

func random_elem(rng: var RngState, F: typedesc, gen: RandomGen): F {.inline, noInit.} =
  if gen == Uniform:
    result = rng.random_unsafe(F)
  elif gen == HighHammingWeight:
    result = rng.random_highHammingWeight(F)
  else:
    result = rng.random_long01Seq(F)

proc test_sameBaseProduct(Name: static Algebra, gen: RandomGen) =
  ## xᴬ xᴮ = xᴬ⁺ᴮ - product of power
  let x = rng.random_elem(Fp12[Name], gen)

  var a = rng.random_elem(BigInt[128], gen)
  var b = rng.random_elem(BigInt[128], gen)
  # div by 2 to ensure their sum doesn't overflow
  # 128 bits
  a.div2()
  b.div2()

  var xa = x
  xa.pow_vartime(a, window = 3)

  var xb = x
  xb.pow_vartime(b, window = 3)

  var xapb = x
  var apb: BigInt[128]
  discard apb.sum(a, b)
  xapb.pow_vartime(apb, window = 3)

  xa *= xb
  doAssert: bool(xa == xapb)

proc test_powpow(Name: static Algebra, gen: RandomGen) =
  ## (xᴬ)ᴮ = xᴬᴮ - power of power
  var x = rng.random_elem(Fp12[Name], gen)

  var a = rng.random_elem(BigInt[128], gen)
  var b = rng.random_elem(BigInt[128], gen)

  var ab: BigInt[256]
  ab.prod(a, b)

  var y = x

  x.pow_vartime(a, window = 3)
  x.pow_vartime(b, window = 3)

  y.pow_vartime(ab, window = 3)
  doAssert: bool(x == y)

proc test_powprod(Name: static Algebra, gen: RandomGen) =
  ## (xy)ᴬ = xᴬyᴬ - power of product
  var x = rng.random_elem(Fp12[Name], gen)
  var y = rng.random_elem(Fp12[Name], gen)

  let a = rng.random_elem(BigInt[128], gen)

  var xy{.noInit.}: Fp12[Name]
  xy.prod(x, y)

  xy.pow_vartime(a, window=3)

  x.pow_vartime(a, window=3)
  y.pow_vartime(a, window=3)

  x *= y

  doAssert: bool(x == xy)

proc test_pow0(Name: static Algebra, gen: RandomGen) =
  ## x⁰ = 1
  var x = rng.random_elem(Fp12[Name], gen)
  var a: BigInt[128] # 0-init

  x.pow_vartime(a, window=3)
  doAssert: bool x.isOne()

proc test_0pow0(Name: static Algebra, gen: RandomGen) =
  ## 0⁰ = 1
  var x: Fp12[Name] # 0-init
  var a: BigInt[128] # 0-init

  x.pow_vartime(a, window=3)
  doAssert: bool x.isOne()

proc test_powinv(Name: static Algebra, gen: RandomGen) =
  ## xᴬ / xᴮ = xᴬ⁻ᴮ - quotient of power
  let x = rng.random_elem(Fp12[Name], gen)

  var a = rng.random_elem(BigInt[128], gen)
  var b = rng.random_elem(BigInt[128], gen)
  # div by 2 to ensure their sum doesn't overflow
  # 128 bits
  a.div2()
  b.div2()
  # Ensure a > b
  cswap(a, b, a < b)

  var xa = x
  xa.pow_vartime(a, window = 3)

  var xb = x
  xb.pow_vartime(b, window = 3)

  xb.inv()
  xa *= xb

  var xamb = x
  var amb: BigInt[128]
  discard amb.diff(a, b)
  xamb.pow_vartime(amb, window = 3)

  doAssert: bool(xa == xamb)

proc test_invpow(Name: static Algebra, gen: RandomGen) =
  ## (x / y)ᴬ = xᴬ / yᴬ - power of quotient
  let x = rng.random_elem(Fp12[Name], gen)
  let y = rng.random_elem(Fp12[Name], gen)

  var a = rng.random_elem(BigInt[128], gen)

  var xa = x
  xa.pow_vartime(a, window = 3)

  var ya = y
  ya.pow_vartime(a, window = 3)
  ya.inv()
  xa *= ya

  var xqya = x
  var invy = y
  invy.inv()
  xqya *= invy
  xqya.pow_vartime(a, window = 3)

  doAssert: bool(xa == xqya)

suite "Exponentiation in 𝔽p12" & " [" & $WordBitWidth & "-bit words]":
  staticFor(curve, TestCurves):
    test "xᴬ xᴮ = xᴬ⁺ᴮ on " & $curve:
      test_sameBaseProduct(curve, gen = Uniform)
      test_sameBaseProduct(curve, gen = HighHammingWeight)
      test_sameBaseProduct(curve, gen = Long01Sequence)

  staticFor(curve, TestCurves):
    test "(xᴬ)ᴮ = xᴬᴮ on " & $curve:
      test_powpow(curve, gen = Uniform)
      test_powpow(curve, gen = HighHammingWeight)
      test_powpow(curve, gen = Long01Sequence)

  staticFor(curve, TestCurves):
    test "(xy)ᴬ = xᴬyᴬ on " & $curve:
      test_powprod(curve, gen = Uniform)
      test_powprod(curve, gen = HighHammingWeight)
      test_powprod(curve, gen = Long01Sequence)

  staticFor(curve, TestCurves):
    test "x⁰ = 1 on " & $curve:
      test_pow0(curve, gen = Uniform)
      test_pow0(curve, gen = HighHammingWeight)
      test_pow0(curve, gen = Long01Sequence)

  staticFor(curve, TestCurves):
    test "0⁰ = 1 on " & $curve:
      test_0pow0(curve, gen = Uniform)
      test_0pow0(curve, gen = HighHammingWeight)
      test_0pow0(curve, gen = Long01Sequence)

  staticFor(curve, TestCurves):
    test "xᴬ / xᴮ = xᴬ⁻ᴮ on " & $curve:
      test_powinv(curve, gen = Uniform)
      test_powinv(curve, gen = HighHammingWeight)
      test_powinv(curve, gen = Long01Sequence)

  staticFor(curve, TestCurves):
    test "(x / y)ᴬ = xᴬ / yᴬ on " & $curve:
      test_invpow(curve, gen = Uniform)
      test_invpow(curve, gen = HighHammingWeight)
      test_invpow(curve, gen = Long01Sequence)
