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
  constantine/platforms/abstractions,
  constantine/math/arithmetic,
  constantine/math/extension_fields,
  constantine/named/algebras,
  constantine/named/[zoo_subgroups, zoo_pairings],
  constantine/math/elliptic/[ec_shortweierstrass_affine, ec_shortweierstrass_projective],
  constantine/math/pairings/[
    cyclotomic_subgroups,
    gt_exponentiations,
    gt_exponentiations_vartime,
    gt_multiexp,
    pairings_generic],
  constantine/math/io/io_extfields,

  # Test utilities
  helpers/prng_unsafe

export
  unittest, # Generic sandwich
  ec_shortweierstrass_affine, ec_shortweierstrass_projective,
  extension_fields,
  algebras

type
  RandomGen* = enum
    Uniform
    HighHammingWeight
    Long01Sequence

template affineType[F; G: static Subgroup](
    ec: EC_ShortW_Prj[F, G]): type =
  EC_ShortW_Aff[F, G]

func clearCofactor[F; G: static Subgroup](
       ec: var EC_ShortW_Aff[F, G]) =
  # For now we don't have any affine operation defined
  var t {.noInit.}: EC_ShortW_Prj[F, G]
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

proc runPairingTests*(Name: static Algebra, G1, G2, GT: typedesc, iters: int) =
  bind affineType

  var rng: RngState
  let timeseed = uint32(toUnix(getTime()) and (1'i64 shl 32 - 1)) # unixTime mod 2^32
  seed(rng, timeseed)
  echo "\n------------------------------------------------------\n"
  echo "test_pairing_",$Name,"_optate xoshiro512** seed: ", timeseed

  proc test_bilinearity_double_impl(randZ: bool, gen: RandomGen, iters: int) =
    for _ in 0 ..< iters:
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

      r.pairing(Pa, Qa)
      r.square()
      r2.pairing(Pa2, Qa)
      r3.pairing(Pa, Qa2)

      doAssert bool(not r.isZero())
      doAssert bool(not r.isOne())
      doAssert bool(r == r2)
      doAssert bool(r == r3)
      doAssert bool(r2 == r3)

  suite "Pairing - Optimal Ate on " & $Name & " [" & $WordBitWidth & "-bit words]":
    test "Bilinearity e([2]P, Q) = e(P, [2]Q) = e(P, Q)^2":
      test_bilinearity_double_impl(randZ = false, gen = Uniform, iters)
      test_bilinearity_double_impl(randZ = false, gen = HighHammingWeight, iters)
      test_bilinearity_double_impl(randZ = false, gen = Long01Sequence, iters)

func random_elem*(rng: var RngState, F: typedesc, gen: RandomGen): F {.noInit.} =
  if gen == Uniform:
    result = rng.random_unsafe(F)
  elif gen == HighHammingWeight:
    result = rng.random_highHammingWeight(F)
  else:
    result = rng.random_long01Seq(F)

proc runGTsubgroupTests*(GT: typedesc, iters: int) =
  bind affineType, random_elem

  var rng: RngState
  let timeseed = uint32(toUnix(getTime()) and (1'i64 shl 32 - 1)) # unixTime mod 2^32
  seed(rng, timeseed)
  echo "\n------------------------------------------------------\n"
  echo "test_pairing_",$GT.Name,"_gt xoshiro512** seed: ", timeseed

  proc test_gt_impl(gen: RandomGen, iters: int) =
    stdout.write "    "
    for _ in 0 ..< iters:
      let a = rng.random_elem(GT, gen)
      doAssert not bool a.isInCyclotomicSubgroup(), "The odds of generating randomly such an element are too low a: " & a.toHex()
      var a2 = a
      a2.finalExpEasy()
      doAssert bool a2.isInCyclotomicSubgroup()
      doAssert not bool a2.isInPairingSubgroup(), "The odds of generating randomly such an element are too low a2: " & a.toHex()
      var a3 = a2
      finalExpHard(a3)
      doAssert bool a3.isInCyclotomicSubgroup()
      doAssert bool a3.isInPairingSubgroup()
      stdout.write '.'

    stdout.write '\n'

  suite "Pairing - 𝔾ₜ subgroup " & $GT.Name & " [" & $WordBitWidth & "-bit words]":
    test "Final Exponentiation and 𝔾ₜ-subgroup membership":
      test_gt_impl(gen = Uniform, iters)
      test_gt_impl(gen = HighHammingWeight, iters)
      test_gt_impl(gen = Long01Sequence, iters)

func random_gt(rng: var RngState, F: typedesc, gen: RandomGen): F {.noInit.} =
  result = rng.random_elem(F, gen)
  result.finalExp()
  debug: doAssert bool result.isInPairingSubgroup()

proc runGTexponentiationTests*(GT: typedesc, iters: int) =
  var rng: RngState
  let timeseed = uint32(toUnix(getTime()) and (1'i64 shl 32 - 1)) # unixTime mod 2^32
  seed(rng, timeseed)
  echo "\n------------------------------------------------------\n"
  echo "test_pairing_",$GT.Name,"_gt_exponentiation xoshiro512** seed: ", timeseed

  proc test_gt_exponentiation_impl(gen: RandomGen, iters: int) =
    stdout.write "    "
    for _ in 0 ..< iters:
      let a = rng.random_gt(GT, gen)
      let kUnred = rng.random_long01seq(GT.Name.getBigInt(kScalarField))
      var k {.noInit.}: GT.Name.getBigInt(kScalarField)
      discard k.reduce_vartime(kUnred, GT.Name.scalarFieldModulus())

      # Reference impl using exponentiation with tables on any field/extension field
      var r_ref = a
      r_ref.pow_vartime(k, window = 3)

      # Square-and-multiply
      var r_sqrmul {.noInit.}: GT
      r_sqrmul.gtExp_sqrmul_vartime(a, k)
      doAssert bool(r_ref == r_sqrmul)

      # MSB->LSB min Hamming Weight signed recoding
      var r_l2r_recoding {.noInit.}: GT
      r_l2r_recoding.gtExp_jy00_vartime(a, k)
      doAssert bool(r_ref == r_l2r_recoding)

      # Windowed NAF
      var r_wNAF {.noInit.}: GT
      r_wNAF.gtExp_wNAF_vartime(a, k, window = 2)
      doAssert bool(r_ref == r_wNAF)
      r_wNAF.gtExp_wNAF_vartime(a, k, window = 3)
      doAssert bool(r_ref == r_wNAF)
      r_wNAF.gtExp_wNAF_vartime(a, k, window = 4)
      doAssert bool(r_ref == r_wNAF)

      # Windowed NAF + endomorphism acceleration
      var r_endoWNAF {.noInit.}: GT
      r_endoWNAF.gtExpEndo_wNAF_vartime(a, k, window = 2)
      doAssert bool(r_ref == r_endoWNAF)
      r_endoWNAF.gtExpEndo_wNAF_vartime(a, k, window = 3)
      doAssert bool(r_ref == r_endoWNAF)
      r_endoWNAF.gtExpEndo_wNAF_vartime(a, k, window = 4)
      doAssert bool(r_ref == r_endoWNAF)

      # Constant-time 𝔾ₜ exponentiation with endomorphism
      var r_ctEndo {.noInit.}: GT
      r_ctEndo.gtExpEndo(a, k)
      doAssert bool(r_ref == r_ctEndo)

      stdout.write '.'

    stdout.write '\n'


  suite "Pairing - Exponentiation for 𝔾ₜ " & $GT.Name & " [" & $WordBitWidth & "-bit words]":
    test "𝔾ₜ exponentiation consistency":
      test_gt_exponentiation_impl(gen = Uniform, iters)
      test_gt_exponentiation_impl(gen = HighHammingWeight, iters)
      test_gt_exponentiation_impl(gen = Long01Sequence, iters)

proc runGTmultiexpTests*[N: static int](GT: typedesc, num_points: array[N, int], iters: int) =
  var rng: RngState
  let timeseed = uint32(toUnix(getTime()) and (1'i64 shl 32 - 1)) # unixTime mod 2^32
  seed(rng, timeseed)
  echo "\n------------------------------------------------------\n"
  echo "test_pairing_",$GT.Name,"_gt_multiexp xoshiro512** seed: ", timeseed

  proc test_gt_multiexp_impl[N](GT: typedesc, rng: var RngState, num_points: array[N, int], gen: RandomGen, iters: int) =
    for N in num_points:
      stdout.write "    "
      for _ in 0 ..< iters:
        var elems = newSeq[GT](N)
        var exponents = newSeq[Fr[GT.Name]](N)

        for i in 0 ..< N:
          elems[i] = rng.random_gt(GT, gen)
          exponents[i] = rng.random_elem(Fr[GT.Name], gen)

        var naive: GT
        naive.setOne()
        for i in 0 ..< N:
          var t {.noInit.}: GT
          t.gtExp_vartime(elems[i], exponents[i])
          naive *= t

        var mexp_ref, mexp_ref_torus, mexp_opt, mexp_opt_torus: GT
        mexp_ref.multiExp_reference_vartime(elems, exponents, useTorus = false)
        mexp_ref_torus.multiExp_reference_vartime(elems, exponents, useTorus = true)
        mexp_opt.multiExp_vartime(elems, exponents, useTorus = false)
        mexp_opt_torus.multiExp_vartime(elems, exponents, useTorus = true)

        doAssert bool(naive == mexp_ref)
        doAssert bool(naive == mexp_ref_torus)
        doAssert bool(naive == mexp_opt)
        doAssert bool(naive == mexp_opt_torus)

        stdout.write '.'

      stdout.write '\n'

  suite "Pairing - MultiExponentiation for 𝔾ₜ " & $GT.Name & " [" & $WordBitWidth & "-bit words]":
    test "𝔾ₜ multi-exponentiation consistency":
      test_gt_multiexp_impl(GT, rng, num_points, gen = Long01Sequence, iters)
