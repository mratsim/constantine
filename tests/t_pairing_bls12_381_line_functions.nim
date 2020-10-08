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
  ../constantine/elliptic/[
    ec_shortweierstrass_affine,
    ec_shortweierstrass_projective,
    ec_scalar_mul],
  ../constantine/pairing/lines_projective,
  # Test utilities
  ../helpers/[prng_unsafe, static_for]

const
  Iters = 4
  TestCurves = [
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
echo "test_pairing_bls12_381_line_functions xoshiro512** seed: ", seed

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

suite "Pairing - Line Functions on BLS12-381" & " [" & $WordBitwidth & "-bit mode]":
  test "Line double - lt,t(P)":
    proc test_line_double(C: static Curve, randZ: bool, gen: RandomGen) =
      for _ in 0 ..< Iters:
        let P = rng.random_point(ECP_ShortW_Aff[Fp[C], NotOnTwist], gen)
        var T = rng.random_point(ECP_ShortW_Proj[Fp2[C], OnTwist], randZ, gen)
        let Q = rng.random_point(ECP_ShortW_Proj[Fp2[C], OnTwist], randZ, gen)
        var l: Line[Fp2[C], C.getSexticTwist()]

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
    proc test_line_add(C: static Curve, randZ: bool, gen: RandomGen) =
      for _ in 0 ..< Iters:
        let P = rng.random_point(ECP_ShortW_Aff[Fp[C], NotOnTwist], gen)
        let Q = rng.random_point(ECP_ShortW_Proj[Fp2[C], OnTwist], randZ, gen)
        var T = rng.random_point(ECP_ShortW_Proj[Fp2[C], OnTwist], randZ, gen)
        var l: Line[Fp2[C], C.getSexticTwist()]

        var TQ{.noInit.}: typeof(T)
        TQ.sum(T, Q)

        var Qaff{.noInit.}: ECP_ShortW_Aff[Fp2[C], OnTwist]
        Qaff.affineFromProjective(Q)
        l.line_add(T, Qaff, P)

        doAssert: bool(T == TQ)

    staticFor(curve, TestCurves):
      test_line_add(curve, randZ = false, gen = Uniform)
      test_line_add(curve, randZ = true, gen = Uniform)
      test_line_add(curve, randZ = false, gen = HighHammingWeight)
      test_line_add(curve, randZ = true, gen = HighHammingWeight)
      test_line_add(curve, randZ = false, gen = Long01Sequence)
      test_line_add(curve, randZ = true, gen = Long01Sequence)
