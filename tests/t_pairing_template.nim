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
  ../constantine/[arithmetic, primitives],
  ../constantine/towers,
  ../constantine/config/curves,
  ../constantine/elliptic/ec_weierstrass_projective,
  ../constantine/hash_to_curve/cofactors,
  # Test utilities
  ../helpers/[prng_unsafe, static_for]

export
  prng_unsafe, times, unittest,
  ec_weierstrass_projective, arithmetic, towers,
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

template runPairingTests*(Iters: static int, C: static Curve, pairing_fn: untyped): untyped {.dirty.}=
  var rng: RngState
  let timeseed = uint32(toUnix(getTime()) and (1'i64 shl 32 - 1)) # unixTime mod 2^32
  seed(rng, timeseed)
  echo "\n------------------------------------------------------\n"
  echo "test_pairing_",$C,"_optate xoshiro512** seed: ", timeseed

  proc test_bilinearity_double_impl(randZ: bool, gen: RandomGen) =
    for _ in 0 ..< Iters:
      let P = rng.random_point(ECP_SWei_Proj[Fp[C]], randZ, gen)
      let Q = rng.random_point(ECP_SWei_Proj[Fp2[C]], randZ, gen)
      var P2: typeof(P)
      var Q2: typeof(Q)

      var r {.noInit.}, r2 {.noInit.}, r3 {.noInit.}: Fp12[C]

      P2.double(P)
      Q2.double(Q)

      r.pairing_fn(P, Q)
      r.square()
      r2.pairing_fn(P2, Q)
      r3.pairing_fn(P, Q2)

      check:
        bool(not r.isZero())
        bool(not r.isOne())
        bool(r == r2)
        bool(r == r3)
        bool(r2 == r3)

  suite "Pairing - Optimal Ate on " & $C:
    test "Bilinearity e([2]P, Q) = e(P, [2]Q) = e(P, Q)^2":
      test_bilinearity_double_impl(randZ = false, gen = Uniform)
      test_bilinearity_double_impl(randZ = true, gen = Uniform)
      test_bilinearity_double_impl(randZ = false, gen = HighHammingWeight)
      test_bilinearity_double_impl(randZ = true, gen = HighHammingWeight)
      test_bilinearity_double_impl(randZ = false, gen = Long01Sequence)
      test_bilinearity_double_impl(randZ = true, gen = Long01Sequence)
