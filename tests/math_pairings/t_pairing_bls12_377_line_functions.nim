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
  constantine/platforms/abstractions,
  constantine/math/arithmetic,
  constantine/math/extension_fields,
  constantine/named/algebras,
  constantine/math/io/io_extfields,
  constantine/math/elliptic/[
    ec_shortweierstrass_affine,
    ec_shortweierstrass_projective,
    ec_scalar_mul],
  constantine/math/pairings/lines_eval,
  # Test utilities
  helpers/prng_unsafe

const
  Iters = 4
  TestCurves = [
    BLS12_377
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
echo "test_pairing_bls12_377_line_functions xoshiro512** seed: ", seed

func random_point*(rng: var RngState, EC: typedesc, gen: RandomGen): EC {.noInit.} =
  if gen == Uniform:
    result = rng.random_unsafe(EC)
  elif gen == HighHammingWeight:
    result = rng.random_highHammingWeight(EC)
  else:
    result = rng.random_long01Seq(EC)

func random_point*(rng: var RngState, EC: typedesc, randZ: bool, gen: RandomGen): EC {.noInit.} =
  if not randZ:
    if gen == Uniform:
      result = rng.random_unsafe(EC)
    elif gen == HighHammingWeight:
      result = rng.random_highHammingWeight(EC)
    else:
      result = rng.random_long01Seq(EC)
  else:
    if gen == Uniform:
      result = rng.random_unsafe_with_randZ(EC)
    elif gen == HighHammingWeight:
      result = rng.random_highHammingWeight_with_randZ(EC)
    else:
      result = rng.random_long01Seq_with_randZ(EC)

suite "Pairing - Line Functions on BLS12-377" & " [" & $WordBitWidth & "-bit words]":
  test "Line double - lt,t(P)":
    proc test_line_double(Name: static Algebra, randZ: bool, gen: RandomGen) =
      for _ in 0 ..< Iters:
        let P = rng.random_point(EC_ShortW_Aff[Fp[Name], G1], gen)
        var T = rng.random_point(EC_ShortW_Prj[Fp2[Name], G2], randZ, gen)
        let Q = rng.random_point(EC_ShortW_Prj[Fp2[Name], G2], randZ, gen)
        var l: Line[Fp2[Name]]

        var T2: typeof(Q)
        T2.double(T)
        l.line_double(T, P)

        doAssert: bool(T == T2)

    staticFor(curve, TestCurves):
      test_line_double(curve, randZ = false, gen = Uniform)
      test_line_double(curve, randZ = true, gen = Uniform)
      test_line_double(curve, randZ = false, gen = HighHammingWeight)
      test_line_double(curve, randZ = true, gen = HighHammingWeight)
      test_line_double(curve, randZ = false, gen = Long01Sequence)
      test_line_double(curve, randZ = true, gen = Long01Sequence)

  test "Line add - lt,q(P)":
    proc test_line_add(Name: static Algebra, randZ: bool, gen: RandomGen) =
      for _ in 0 ..< Iters:
        let P = rng.random_point(EC_ShortW_Aff[Fp[Name], G1], gen)
        let Q = rng.random_point(EC_ShortW_Prj[Fp2[Name], G2], randZ, gen)
        var T = rng.random_point(EC_ShortW_Prj[Fp2[Name], G2], randZ, gen)
        var l: Line[Fp2[Name]]

        var TQ{.noInit.}: typeof(T)
        TQ.sum(T, Q)

        var Qaff{.noInit.}: EC_ShortW_Aff[Fp2[Name], G2]
        Qaff.affine(Q)
        l.line_add(T, Qaff, P)

        doAssert: bool(T == TQ)

    staticFor(curve, TestCurves):
      test_line_add(curve, randZ = false, gen = Uniform)
      test_line_add(curve, randZ = true, gen = Uniform)
      test_line_add(curve, randZ = false, gen = HighHammingWeight)
      test_line_add(curve, randZ = true, gen = HighHammingWeight)
      test_line_add(curve, randZ = false, gen = Long01Sequence)
      test_line_add(curve, randZ = true, gen = Long01Sequence)
