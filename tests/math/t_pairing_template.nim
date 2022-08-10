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
  ../../constantine/platforms/abstractions,
  ../../constantine/math/arithmetic,
  ../../constantine/math/extension_fields,
  ../../constantine/math/config/curves,
  ../../constantine/math/elliptic/[ec_shortweierstrass_affine, ec_shortweierstrass_projective],
  ../../constantine/math/constants/[zoo_subgroups, zoo_pairings],
  ../../constantine/math/pairing/cyclotomic_subgroup,
  ../../constantine/math/io/io_extfields,

  # Test utilities
  ../../helpers/prng_unsafe

export
  prng_unsafe, times, unittest,
  ec_shortweierstrass_affine, ec_shortweierstrass_projective,
  arithmetic, extension_fields,
  io_extfields,
  cyclotomic_subgroup,
  abstractions, curves

type
  RandomGen* = enum
    Uniform
    HighHammingWeight
    Long01Sequence

template affineType[F; G: static Subgroup](
    ec: ECP_ShortW_Prj[F, G]): type =
  ECP_ShortW_Aff[F, G]

func clearCofactor[F; G: static Subgroup](
       ec: var ECP_ShortW_Aff[F, G]) =
  # For now we don't have any affine operation defined
  var t {.noInit.}: ECP_ShortW_Prj[F, G]
  t.fromAffine(ec)
  t.clearCofactor()
  ec.affine(t)

func random_point*(rng: var RngState, EC: typedesc, randZ: bool, gen: RandomGen): EC {.noInit.} =
  if gen == Uniform:
    result = rng.random_unsafe(EC)
    result.clearCofactor()
  elif gen == HighHammingWeight:
    result = rng.random_highHammingWeight(EC)
    result.clearCofactor()
  else:
    result = rng.random_long01Seq(EC)
    result.clearCofactor()

template runPairingTests*(Iters: static int, C: static Curve, G1, G2, GT: typedesc, pairing_fn: untyped): untyped {.dirty.}=
  bind affineType

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

      var Pa {.noInit.}, Pa2 {.noInit.}: affineType(P)
      var Qa {.noInit.}, Qa2 {.noInit.}: affineType(Q)

      Pa.affine(P)
      Pa2.affine(P2)
      Qa.affine(Q)
      Qa2.affine(Q2)

      r.pairing_fn(Pa, Qa)
      r.square()
      r2.pairing_fn(Pa2, Qa)
      r3.pairing_fn(Pa, Qa2)

      doAssert bool(not r.isZero())
      doAssert bool(not r.isOne())
      doAssert bool(r == r2)
      doAssert bool(r == r3)
      doAssert bool(r2 == r3)

  suite "Pairing - Optimal Ate on " & $C & " [" & $WordBitwidth & "-bit mode]":
    test "Bilinearity e([2]P, Q) = e(P, [2]Q) = e(P, Q)^2":
      test_bilinearity_double_impl(randZ = false, gen = Uniform)
      test_bilinearity_double_impl(randZ = false, gen = HighHammingWeight)
      test_bilinearity_double_impl(randZ = false, gen = Long01Sequence)

func random_elem*(rng: var RngState, F: typedesc, gen: RandomGen): F {.inline, noInit.} =
  if gen == Uniform:
    result = rng.random_unsafe(F)
  elif gen == HighHammingWeight:
    result = rng.random_highHammingWeight(F)
  else:
    result = rng.random_long01Seq(F)

template runGTsubgroupTests*(Iters: static int, GT: typedesc, finalExpHard_fn: untyped): untyped {.dirty.}=
  bind affineType

  var rng: RngState
  let timeseed = uint32(toUnix(getTime()) and (1'i64 shl 32 - 1)) # unixTime mod 2^32
  seed(rng, timeseed)
  echo "\n------------------------------------------------------\n"
  echo "test_pairing_",$GT.C,"_gt xoshiro512** seed: ", timeseed

  proc test_gt_impl(gen: RandomGen) =
    stdout.write "    "
    for _ in 0 ..< Iters:
      let a = rng.random_elem(GT, gen)
      doAssert not bool a.isInCyclotomicSubgroup(), "The odds of generating randomly such an element are too low a: " & a.toHex()
      var a2 = a
      a2.finalExpEasy()
      doAssert bool a2.isInCyclotomicSubgroup()
      doAssert not bool a2.isInPairingSubgroup(), "The odds of generating randomly such an element are too low a2: " & a.toHex()
      var a3 = a2
      finalExpHard_fn(a3)
      doAssert bool a3.isInCyclotomicSubgroup()
      doAssert bool a3.isInPairingSubgroup()
      stdout.write '.'

    stdout.write '\n'

  suite "Pairing - GT subgroup " & $GT.C & " [" & $WordBitwidth & "-bit mode]":
    test "Final Exponentiation and GT-subgroup membership":
      test_gt_impl(gen = Uniform)
      test_gt_impl(gen = HighHammingWeight)
      test_gt_impl(gen = Long01Sequence)