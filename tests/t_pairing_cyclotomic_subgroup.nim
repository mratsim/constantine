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
  ../constantine/pairing/cyclotomic_subgroup,
  ../constantine/isogeny/frobenius,
  # Test utilities
  ../helpers/[prng_unsafe, static_for]

const
  Iters = 4
  TestCurves = [
    BN254_Nogami,
    BN254_Snarks,
    BLS12_377,
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
echo "test_pairing_fp12_sparse xoshiro512** seed: ", seed

func random_elem(rng: var RngState, F: typedesc, gen: RandomGen): F {.inline, noInit.} =
  if gen == Uniform:
    result = rng.random_unsafe(F)
  elif gen == HighHammingWeight:
    result = rng.random_highHammingWeight(F)
  else:
    result = rng.random_long01Seq(F)

suite "Pairing - Cyclotomic subgroup - GΦ₁₂(p) = {α ∈ Fp¹² : α^Φ₁₂(p) ≡ 1 (mod p¹²)}" & " [" & $WordBitwidth & "-bit mode]":
  test "Easy part of the final exponentiation maps to the cyclotomic subgroup":
    proc test_final_exp_easy_cycl(C: static Curve, gen: static RandomGen) =
      for _ in 0 ..< Iters:
        var f = rng.random_elem(Fp12[C], gen)

        f.finalExpEasy()

        var f4, minus_f2: typeof(f)
        minus_f2.frobenius_map(f, 2)  # f^p²
        f4.frobenius_map(minus_f2, 2) # f^p⁴
        minus_f2.conj()               # f^⁻²p

        f *= f4
        f *= minus_f2                 # f^(p⁴-p²+1) = f^Φ₁₂(p)

        check: bool(f.isOne())

    staticFor(curve, TestCurves):
      test_final_exp_easy_cycl(curve, gen = Uniform)
      test_final_exp_easy_cycl(curve, gen = HighHammingWeight)
      test_final_exp_easy_cycl(curve, gen = Long01Sequence)

  test "Cyclotomic inverse":
    proc test_cycl_inverse(C: static Curve, gen: static RandomGen) =
      for _ in 0 ..< Iters:
        var f = rng.random_elem(Fp12[C], gen)

        f.finalExpEasy()
        var g = f

        f.cyclotomic_inv()
        f *= g

        check: bool(f.isOne())

    staticFor(curve, TestCurves):
      test_cycl_inverse(curve, gen = Uniform)
      test_cycl_inverse(curve, gen = HighHammingWeight)
      test_cycl_inverse(curve, gen = Long01Sequence)

  test "Cyclotomic squaring":
    proc test_cycl_squaring_in_place(C: static Curve, gen: static RandomGen) =
      for _ in 0 ..< Iters:
        var f = rng.random_elem(Fp12[C], gen)

        f.finalExpEasy()
        var g = f

        f.square()
        g.cyclotomic_square()

        check: bool(f == g)

    staticFor(curve, TestCurves):
      test_cycl_squaring_in_place(curve, gen = Uniform)
      test_cycl_squaring_in_place(curve, gen = HighHammingWeight)
      test_cycl_squaring_in_place(curve, gen = Long01Sequence)

    proc test_cycl_squaring_out_place(C: static Curve, gen: static RandomGen) =
      for _ in 0 ..< Iters:
        var f = rng.random_elem(Fp12[C], gen)

        f.finalExpEasy()
        var g = f
        var r: typeof(f)

        f.square()
        r.cyclotomic_square(g)

        check: bool(f == r)

    staticFor(curve, TestCurves):
      test_cycl_squaring_out_place(curve, gen = Uniform)
      test_cycl_squaring_out_place(curve, gen = HighHammingWeight)
      test_cycl_squaring_out_place(curve, gen = Long01Sequence)
