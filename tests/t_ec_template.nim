# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

# ############################################################
#
#         Template tests for elliptic curve operations
#
# ############################################################

import
  # Standard library
  std/[unittest, times],
  # Internals
  ../constantine/config/[common, curves],
  ../constantine/arithmetic,
  ../constantine/towers,
  ../constantine/elliptic/[
    ec_shortweierstrass_affine,
    ec_shortweierstrass_jacobian,
    ec_shortweierstrass_projective,
    ec_scalar_mul],
    ../constantine/io/[io_bigints, io_fields],
  # Test utilities
  ../helpers/prng_unsafe,
  ./support/ec_reference_scalar_mult

type
  RandomGen* = enum
    Uniform
    HighHammingWeight
    Long01Sequence

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

proc run_EC_addition_tests*(
       ec: typedesc,
       Iters: static int,
       moduleName: string
     ) =

  # Random seed for reproducibility
  var rng: RngState
  let seed = uint32(getTime().toUnix() and (1'i64 shl 32 - 1)) # unixTime mod 2^32
  rng.seed(seed)
  echo "\n------------------------------------------------------\n"
  echo moduleName, " xoshiro512** seed: ", seed

  when ec.F is Fp:
    const G1_or_G2 = "G1"
  else:
    const G1_or_G2 = "G2"

  const testSuiteDesc = "Elliptic curve in Short Weierstrass form with projective coordinates"

  suite testSuiteDesc & " - " & $ec & " - [" & $WordBitwidth & "-bit mode]":
    test "The infinity point is the neutral element w.r.t. to EC " & G1_or_G2 & " addition":
      proc test(EC: typedesc, randZ: bool, gen: RandomGen) =
        var inf {.noInit.}: EC
        inf.setInf()
        check: bool inf.isInf()

        for _ in 0 ..< Iters:
          var r{.noInit.}: EC
          let P = rng.random_point(EC, randZ, gen)

          r.sum(P, inf)
          check: bool(r == P)

          r.sum(inf, P)
          check: bool(r == P)

      test(ec, randZ = false, gen = Uniform)
      test(ec, randZ = true, gen = Uniform)
      test(ec, randZ = false, gen = HighHammingWeight)
      test(ec, randZ = true, gen = HighHammingWeight)
      test(ec, randZ = false, gen = Long01Sequence)
      test(ec, randZ = true, gen = Long01Sequence)

    test "Adding opposites gives an infinity point":
      proc test(EC: typedesc, randZ: bool, gen: RandomGen) =
        for _ in 0 ..< Iters:
          var r{.noInit.}: EC
          let P = rng.random_point(EC, randZ, gen)
          var Q = P
          Q.neg()

          r.sum(P, Q)
          check: bool r.isInf()

          r.sum(Q, P)
          check: bool r.isInf()

      test(ec, randZ = false, gen = Uniform)
      test(ec, randZ = true, gen = Uniform)
      test(ec, randZ = false, gen = HighHammingWeight)
      test(ec, randZ = true, gen = HighHammingWeight)
      test(ec, randZ = false, gen = Long01Sequence)
      test(ec, randZ = true, gen = Long01Sequence)

    test "EC " & G1_or_G2 & " add is commutative":
      proc test(EC: typedesc, randZ: bool, gen: RandomGen) =
        for _ in 0 ..< Iters:
          var r0{.noInit.}, r1{.noInit.}: EC
          let P = rng.random_point(EC, randZ, gen)
          let Q = rng.random_point(EC, randZ, gen)

          r0.sum(P, Q)
          r1.sum(Q, P)
          check: bool(r0 == r1)

      test(ec, randZ = false, gen = Uniform)
      test(ec, randZ = true, gen = Uniform)
      test(ec, randZ = false, gen = HighHammingWeight)
      test(ec, randZ = true, gen = HighHammingWeight)
      test(ec, randZ = false, gen = Long01Sequence)
      test(ec, randZ = true, gen = Long01Sequence)

    test "EC " & G1_or_G2 & " add is associative":
      proc test(EC: typedesc, randZ: bool, gen: RandomGen) =
        for _ in 0 ..< Iters:
          let a = rng.random_point(EC, randZ, gen)
          let b = rng.random_point(EC, randZ, gen)
          let c = rng.random_point(EC, randZ, gen)

          var tmp1{.noInit.}, tmp2{.noInit.}: EC

          # r0 = (a + b) + c
          tmp1.sum(a, b)
          tmp2.sum(tmp1, c)
          let r0 = tmp2

          # r1 = a + (b + c)
          tmp1.sum(b, c)
          tmp2.sum(a, tmp1)
          let r1 = tmp2

          # r2 = (a + c) + b
          tmp1.sum(a, c)
          tmp2.sum(tmp1, b)
          let r2 = tmp2

          # r3 = a + (c + b)
          tmp1.sum(c, b)
          tmp2.sum(a, tmp1)
          let r3 = tmp2

          # r4 = (c + a) + b
          tmp1.sum(c, a)
          tmp2.sum(tmp1, b)
          let r4 = tmp2

          # ...

          check:
            bool(r0 == r1)
            bool(r0 == r2)
            bool(r0 == r3)
            bool(r0 == r4)

      test(ec, randZ = false, gen = Uniform)
      test(ec, randZ = true, gen = Uniform)
      test(ec, randZ = false, gen = HighHammingWeight)
      test(ec, randZ = true, gen = HighHammingWeight)
      test(ec, randZ = false, gen = Long01Sequence)
      test(ec, randZ = true, gen = Long01Sequence)

    test "EC " & G1_or_G2 & " double and EC " & G1_or_G2 & " add are consistent":
      proc test(EC: typedesc, randZ: bool, gen: RandomGen) =
        for _ in 0 ..< Iters:
          let a = rng.random_point(EC, randZ, gen)

          var r0{.noInit.}, r1{.noInit.}: EC

          r0.double(a)
          r1.sum(a, a)

          check: bool(r0 == r1)

      test(ec, randZ = false, gen = Uniform)
      test(ec, randZ = true, gen = Uniform)
      test(ec, randZ = false, gen = HighHammingWeight)
      test(ec, randZ = true, gen = HighHammingWeight)
      test(ec, randZ = false, gen = Long01Sequence)
      test(ec, randZ = true, gen = Long01Sequence)

proc run_EC_mul_sanity_tests*(
       ec: typedesc,
       ItersMul: static int,
       moduleName: string
     ) =

  # Random seed for reproducibility
  var rng: RngState
  let seed = uint32(getTime().toUnix() and (1'i64 shl 32 - 1)) # unixTime mod 2^32
  rng.seed(seed)
  echo "\n------------------------------------------------------\n"
  echo moduleName, " xoshiro512** seed: ", seed

  when ec.F is Fp:
    const G1_or_G2 = "G1"
  else:
    const G1_or_G2 = "G2"

  const testSuiteDesc = "Elliptic curve in Short Weierstrass form"

  suite testSuiteDesc & " - " & $ec & " - [" & $WordBitwidth & "-bit mode]":
    test "EC " & G1_or_G2 & " mul [0]P == Inf":
      proc test(EC: typedesc, bits: static int, randZ: bool, gen: RandomGen) =
        for _ in 0 ..< ItersMul:
          let a = rng.random_point(EC, randZ, gen)

          var
            impl = a
            reference = a

          impl.scalarMulGeneric(BigInt[bits]())
          reference.unsafe_ECmul_double_add(BigInt[bits]())

          check:
            bool(impl.isInf())
            bool(reference.isInf())

      test(ec, bits = ec.F.C.getCurveOrderBitwidth(), randZ = false, gen = Uniform)
      test(ec, bits = ec.F.C.getCurveOrderBitwidth(), randZ = true, gen = Uniform)
      test(ec, bits = ec.F.C.getCurveOrderBitwidth(), randZ = false, gen = HighHammingWeight)
      test(ec, bits = ec.F.C.getCurveOrderBitwidth(), randZ = true, gen = HighHammingWeight)
      test(ec, bits = ec.F.C.getCurveOrderBitwidth(), randZ = false, gen = Long01Sequence)
      test(ec, bits = ec.F.C.getCurveOrderBitwidth(), randZ = true, gen = Long01Sequence)

    test "EC " & G1_or_G2 & " mul [1]P == P":
      proc test(EC: typedesc, bits: static int, randZ: bool, gen: RandomGen) =
        for _ in 0 ..< ItersMul:
          let a = rng.random_point(EC, randZ, gen)

          var exponent{.noInit.}: BigInt[bits]
          exponent.setOne()

          var
            impl = a
            reference = a

          impl.scalarMulGeneric(exponent)
          reference.unsafe_ECmul_double_add(exponent)

          check:
            bool(impl == a)
            bool(reference == a)

      test(ec, bits = ec.F.C.getCurveOrderBitwidth(), randZ = false, gen = Uniform)
      test(ec, bits = ec.F.C.getCurveOrderBitwidth(), randZ = true, gen = Uniform)
      test(ec, bits = ec.F.C.getCurveOrderBitwidth(), randZ = false, gen = HighHammingWeight)
      test(ec, bits = ec.F.C.getCurveOrderBitwidth(), randZ = true, gen = HighHammingWeight)
      test(ec, bits = ec.F.C.getCurveOrderBitwidth(), randZ = false, gen = Long01Sequence)
      test(ec, bits = ec.F.C.getCurveOrderBitwidth(), randZ = true, gen = Long01Sequence)

    test "EC " & G1_or_G2 & " mul [2]P == P.double()":
      proc test(EC: typedesc, bits: static int, randZ: bool, gen: RandomGen) =
        for _ in 0 ..< ItersMul:
          let a = rng.random_point(EC, randZ, gen)

          var doubleA{.noInit.}: EC
          doubleA.double(a)

          let exponent = BigInt[bits].fromUint(2)

          var
            impl = a
            reference = a

          impl.scalarMulGeneric(exponent)
          reference.unsafe_ECmul_double_add(exponent)

          check:
            bool(impl == doubleA)
            bool(reference == doubleA)

      test(ec, bits = ec.F.C.getCurveOrderBitwidth(), randZ = false, gen = Uniform)
      test(ec, bits = ec.F.C.getCurveOrderBitwidth(), randZ = true, gen = Uniform)
      test(ec, bits = ec.F.C.getCurveOrderBitwidth(), randZ = false, gen = HighHammingWeight)
      test(ec, bits = ec.F.C.getCurveOrderBitwidth(), randZ = true, gen = HighHammingWeight)
      test(ec, bits = ec.F.C.getCurveOrderBitwidth(), randZ = false, gen = Long01Sequence)
      test(ec, bits = ec.F.C.getCurveOrderBitwidth(), randZ = true, gen = Long01Sequence)

proc run_EC_mul_distributive_tests*(
       ec: typedesc,
       ItersMul: static int,
       moduleName: string
     ) =

  # Random seed for reproducibility
  var rng: RngState
  let seed = uint32(getTime().toUnix() and (1'i64 shl 32 - 1)) # unixTime mod 2^32
  rng.seed(seed)
  echo "\n------------------------------------------------------\n"
  echo moduleName, " xoshiro512** seed: ", seed

  when ec.F is Fp:
    const G1_or_G2 = "G1"
  else:
    const G1_or_G2 = "G2"

  const testSuiteDesc = "Elliptic curve in Short Weierstrass form"

  suite testSuiteDesc & " - " & $ec & " - [" & $WordBitwidth & "-bit mode]":

    test "EC " & G1_or_G2 & " mul is distributive over EC add":
      proc test(EC: typedesc, bits: static int, randZ: bool, gen: RandomGen) =
        for _ in 0 ..< ItersMul:
          let a = rng.random_point(EC, randZ, gen)
          let b = rng.random_point(EC, randZ, gen)

          let exponent = rng.random_unsafe(BigInt[bits])

          # [k](a + b) - Factorized
          var
            fImpl{.noInit.}: EC
            fReference{.noInit.}: EC

          fImpl.sum(a, b)
          fReference.sum(a, b)

          fImpl.scalarMulGeneric(exponent)
          fReference.unsafe_ECmul_double_add(exponent)

          # [k]a + [k]b - Distributed
          var kaImpl = a
          var kaRef = a

          kaImpl.scalarMulGeneric(exponent)
          kaRef.unsafe_ECmul_double_add(exponent)

          var kbImpl = b
          var kbRef = b

          kbImpl.scalarMulGeneric(exponent)
          kbRef.unsafe_ECmul_double_add(exponent)

          var kakbImpl{.noInit.}, kakbRef{.noInit.}: EC
          kakbImpl.sum(kaImpl, kbImpl)
          kakbRef.sum(kaRef, kbRef)

          check:
            bool(fImpl == kakbImpl)
            bool(fReference == kakbRef)
            bool(fImpl == fReference)

      test(ec, bits = ec.F.C.getCurveOrderBitwidth(), randZ = false, gen = Uniform)
      test(ec, bits = ec.F.C.getCurveOrderBitwidth(), randZ = true, gen = Uniform)
      test(ec, bits = ec.F.C.getCurveOrderBitwidth(), randZ = false, gen = HighHammingWeight)
      test(ec, bits = ec.F.C.getCurveOrderBitwidth(), randZ = true, gen = HighHammingWeight)
      test(ec, bits = ec.F.C.getCurveOrderBitwidth(), randZ = false, gen = Long01Sequence)
      test(ec, bits = ec.F.C.getCurveOrderBitwidth(), randZ = true, gen = Long01Sequence)

proc run_EC_mul_vs_ref_impl*(
       ec: typedesc,
       ItersMul: static int,
       moduleName: string
     ) =

  # Random seed for reproducibility
  var rng: RngState
  let seed = uint32(getTime().toUnix() and (1'i64 shl 32 - 1)) # unixTime mod 2^32
  rng.seed(seed)
  echo "\n------------------------------------------------------\n"
  echo moduleName, " xoshiro512** seed: ", seed

  when ec.F is Fp:
    const G1_or_G2 = "G1"
  else:
    const G1_or_G2 = "G2"

  const testSuiteDesc = "Elliptic curve in Short Weierstrass form"

  suite testSuiteDesc & " - " & $ec & " - [" & $WordBitwidth & "-bit mode]":
    test "EC " & G1_or_G2 & " mul constant-time is equivalent to a simple double-and-add algorithm":
      proc test(EC: typedesc, bits: static int, randZ: bool, gen: RandomGen) =
        for _ in 0 ..< ItersMul:
          let a = rng.random_point(EC, randZ, gen)

          let exponent = rng.random_unsafe(BigInt[bits])

          var
            impl = a
            reference = a

          impl.scalarMulGeneric(exponent)
          reference.unsafe_ECmul_double_add(exponent)

          check: bool(impl == reference)

      test(ec, bits = ec.F.C.getCurveOrderBitwidth(), randZ = false, gen = Uniform)
      test(ec, bits = ec.F.C.getCurveOrderBitwidth(), randZ = true, gen = Uniform)
      test(ec, bits = ec.F.C.getCurveOrderBitwidth(), randZ = false, gen = HighHammingWeight)
      test(ec, bits = ec.F.C.getCurveOrderBitwidth(), randZ = true, gen = HighHammingWeight)
      test(ec, bits = ec.F.C.getCurveOrderBitwidth(), randZ = false, gen = Long01Sequence)
      test(ec, bits = ec.F.C.getCurveOrderBitwidth(), randZ = true, gen = Long01Sequence)

proc run_EC_mixed_add_impl*(
       ec: typedesc,
       Iters: static int,
       moduleName: string
     ) =

  # Random seed for reproducibility
  var rng: RngState
  let seed = uint32(getTime().toUnix() and (1'i64 shl 32 - 1)) # unixTime mod 2^32
  rng.seed(seed)
  echo "\n------------------------------------------------------\n"
  echo moduleName, " xoshiro512** seed: ", seed

  when ec.F is Fp:
    const G1_or_G2 = "G1"
  else:
    const G1_or_G2 = "G2"

  const testSuiteDesc = "Elliptic curve mixed addition for Short Weierstrass form"

  suite testSuiteDesc & " - " & $ec & " - [" & $WordBitwidth & "-bit mode]":
    test "EC " & G1_or_G2 & " mixed addition is consistent with general addition":
      proc test(EC: typedesc, bits: static int, randZ: bool, gen: RandomGen) =
        for _ in 0 ..< Iters:
          let a = rng.random_point(EC, randZ, gen)
          let b = rng.random_point(EC, randZ, gen)
          var bAff: ECP_ShortW_Aff[EC.F, EC.Tw]
          bAff.affineFromProjective(b)

          var r_generic, r_mixed: EC

          r_generic.sum(a, b)
          r_mixed.madd(a, bAff)

          check: bool(r_generic == r_mixed)

      test(ec, bits = ec.F.C.getCurveOrderBitwidth(), randZ = false, gen = Uniform)
      test(ec, bits = ec.F.C.getCurveOrderBitwidth(), randZ = true, gen = Uniform)
      test(ec, bits = ec.F.C.getCurveOrderBitwidth(), randZ = false, gen = HighHammingWeight)
      test(ec, bits = ec.F.C.getCurveOrderBitwidth(), randZ = true, gen = HighHammingWeight)
      test(ec, bits = ec.F.C.getCurveOrderBitwidth(), randZ = false, gen = Long01Sequence)
      test(ec, bits = ec.F.C.getCurveOrderBitwidth(), randZ = true, gen = Long01Sequence)
