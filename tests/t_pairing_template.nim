# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  # Standard library
  std/unittest, times,
  # Internals
  ../constantine/config/common,
  ../constantine/[arithmetic, primitives],
  ../constantine/towers,
  ../constantine/config/curves,
  ../constantine/elliptic/ec_shortweierstrass_projective,
  ../constantine/hash_to_curve/cofactors,
  # Test utilities
  ../helpers/prng_unsafe

export
  prng_unsafe, times, unittest,
  ec_shortweierstrass_projective, arithmetic, towers,
  primitives

type
  RandomGen* = enum
    Uniform
    HighHammingWeight
    Long01Sequence

func random_point*(rng: var RngState, EC: typedesc, randZ: bool, gen: RandomGen): EC {.noInit.} =
  if not randZ:
    if gen == Uniform:
      result = rng.random_unsafe(EC)
      result.clearCofactorReference()
    elif gen == HighHammingWeight:
      result = rng.random_highHammingWeight(EC)
      result.clearCofactorReference()
    else:
      result = rng.random_long01Seq(EC)
      result.clearCofactorReference()
  else:
    if gen == Uniform:
      result = rng.random_unsafe_with_randZ(EC)
      result.clearCofactorReference()
    elif gen == HighHammingWeight:
      result = rng.random_highHammingWeight_with_randZ(EC)
      result.clearCofactorReference()
    else:
      result = rng.random_long01Seq_with_randZ(EC)
      result.clearCofactorReference()

template runPairingTests*(Iters: static int, C: static Curve, G1, G2, GT: typedesc, pairing_fn: untyped): untyped {.dirty.}=
  var rng: RngState
  let timeseed = uint32(toUnix(getTime()) and (1'i64 shl 32 - 1)) # unixTime mod 2^32
  seed(rng, timeseed)
  echo "\n------------------------------------------------------\n"
  echo "test_pairing_",$C,"_optate xoshiro512** seed: ", timeseed

  proc test_bilinearity_double_impl(randZ: bool, gen: RandomGen) =
    for _ in 0 ..< Iters:
      let P = rng.random_point(G1, randZ, gen)
      let Q = rng.random_point(G2, randZ, gen)
      var P2: typeof(P)
      var Q2: typeof(Q)

      var r {.noInit.}, r2 {.noInit.}, r3 {.noInit.}: GT

      P2.double(P)
      Q2.double(Q)

      r.pairing_fn(P, Q)
      r.square()
      r2.pairing_fn(P2, Q)
      r3.pairing_fn(P, Q2)

      doAssert bool(not r.isZero())
      doAssert bool(not r.isOne())
      doAssert bool(r == r2)
      doAssert bool(r == r3)
      doAssert bool(r2 == r3)

  suite "Pairing - Optimal Ate on " & $C & " [" & $WordBitwidth & "-bit mode]":
    test "Bilinearity e([2]P, Q) = e(P, [2]Q) = e(P, Q)^2":
      test_bilinearity_double_impl(randZ = false, gen = Uniform)
      test_bilinearity_double_impl(randZ = true, gen = Uniform)
      test_bilinearity_double_impl(randZ = false, gen = HighHammingWeight)
      test_bilinearity_double_impl(randZ = true, gen = HighHammingWeight)
      test_bilinearity_double_impl(randZ = false, gen = Long01Sequence)
      test_bilinearity_double_impl(randZ = true, gen = Long01Sequence)
