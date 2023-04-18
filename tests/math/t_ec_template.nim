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
  ../../constantine/platforms/abstractions,
  ../../constantine/math/config/curves,
  ../../constantine/math/[arithmetic, extension_fields],
  ../../constantine/math/elliptic/[
    ec_shortweierstrass_affine,
    ec_shortweierstrass_jacobian,
    ec_shortweierstrass_jacobian_extended,
    ec_shortweierstrass_projective,
    ec_shortweierstrass_batch_ops,
    ec_twistededwards_affine,
    ec_twistededwards_projective,
    ec_scalar_mul,
    ec_multi_scalar_mul],
  ../../constantine/math/io/[io_bigints, io_fields, io_ec],
  ../../constantine/math/constants/zoo_subgroups,
  # Test utilities
  ../../helpers/prng_unsafe,
  ../../constantine/math/elliptic/ec_scalar_mul_vartime

export unittest, abstractions, arithmetic # Generic sandwich

# Extended Jacobian generic bindings
# ----------------------------------
# All vartime procedures MUST be tagged vartime
# Hence we do not expose `sum` or `+=` for extended jacobian operation to prevent `vartime` mistakes
# we create a local `sum` or `+=` for this module only

func sum[F; G: static Subgroup](r: var ECP_ShortW_JacExt[F, G], P, Q: ECP_ShortW_JacExt[F, G]) =
  r.sum_vartime(P, Q)
func `+=`[F; G: static Subgroup](P: var ECP_ShortW_JacExt[F, G], Q: ECP_ShortW_JacExt[F, G]) =
  P.sum_vartime(P, Q)
func madd[F; G: static Subgroup](r: var ECP_ShortW_JacExt[F, G], P: ECP_ShortW_JacExt[F, G], Q: ECP_ShortW_Aff[F, G]) =
  r.madd_vartime(P, Q)
func `+=`[F; G: static Subgroup](P: var ECP_ShortW_JacExt[F, G], Q: ECP_ShortW_Aff[F, G]) =
  P.madd_vartime(P, Q)

type
  RandomGen* = enum
    Uniform
    HighHammingWeight
    Long01Sequence

func random_point*(rng: var RngState, EC: typedesc, randZ: bool, gen: RandomGen): EC {.noInit.} =
  when EC is ECP_ShortW_Aff:
    if gen == Uniform:
      result = rng.random_unsafe(EC)
    elif gen == HighHammingWeight:
      result = rng.random_highHammingWeight(EC)
    else:
      result = rng.random_long01Seq(EC)
  else:
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
       moduleName: string) =
  var rng: RngState
  let seed = uint32(getTime().toUnix() and (1'i64 shl 32 - 1)) # unixTime mod 2^32
  rng.seed(seed)
  echo "\n------------------------------------------------------\n"
  echo moduleName, " xoshiro512** seed: ", seed

  const testSuiteDesc = "Elliptic curve in " & $ec.F.C.getEquationForm() & " form with projective coordinates"

  suite testSuiteDesc & " - " & $ec & " - [" & $WordBitWidth & "-bit mode]":
    test "The infinity point is the neutral element w.r.t. to EC " & $ec.G & " addition":
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

          # Aliasing tests
          r = P
          r += inf
          check: bool(r == P)

          r.setInf()
          r += P
          check: bool(r == P)

      test(ec, randZ = false, gen = Uniform)
      test(ec, randZ = true, gen = Uniform)
      test(ec, randZ = false, gen = HighHammingWeight)
      test(ec, randZ = true, gen = HighHammingWeight)
      test(ec, randZ = false, gen = Long01Sequence)
      test(ec, randZ = true, gen = Long01Sequence)

    test "Infinity point from affine conversion gives proper result":
      proc test(EC: typedesc, randZ: bool, gen: RandomGen) =
        var affInf {.noInit.}: affine(EC)
        var inf {.noInit.}: EC
        affInf.setInf()
        inf.fromAffine(affInf)
        check: bool inf.isInf()

        for _ in 0 ..< Iters:
          var r{.noInit.}: EC
          let P = rng.random_point(EC, randZ, gen)

          r.sum(P, inf)
          check: bool(r == P)

          r.sum(inf, P)
          check: bool(r == P)

          # Aliasing tests
          r = P
          r += inf
          check: bool(r == P)

          r = inf
          r += P
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

    test "EC " & $ec.G & " add is commutative":
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

    test "EC " & $ec.G & " add is associative":
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

    test "EC " & $ec.G & " double and EC " & $ec.G & " add are consistent":
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
       moduleName: string) =
  # Random seed for reproducibility
  var rng: RngState
  let seed = uint32(getTime().toUnix() and (1'i64 shl 32 - 1)) # unixTime mod 2^32
  rng.seed(seed)
  echo "\n------------------------------------------------------\n"
  echo moduleName, " xoshiro512** seed: ", seed

  const testSuiteDesc = "Elliptic curve in " & $ec.F.C.getEquationForm() & " form"

  suite testSuiteDesc & " - " & $ec & " - [" & $WordBitWidth & "-bit mode]":
    test "EC " & $ec.G & " mul [0]P == Inf":
      proc test(EC: typedesc, bits: static int, randZ: bool, gen: RandomGen) =
        for _ in 0 ..< ItersMul:
          let a = rng.random_point(EC, randZ, gen)

          var
            impl = a
            reference = a
            refMinWeight = a

          impl.scalarMulGeneric(BigInt[bits]())
          reference.scalarMul_doubleAdd_vartime(BigInt[bits]())
          refMinWeight.scalarMul_minHammingWeight_vartime(BigInt[bits]())

          check:
            bool(impl.isInf())
            bool(reference.isInf())
            bool(refMinWeight.isInf())

          proc refWNaf(bits, w: static int) = # workaround staticFor symbol visibility
            var refWNAF = a
            refWNAF.scalarMul_minHammingWeight_windowed_vartime(BigInt[bits](), window = w)
            check: bool(refWNAF.isInf())

          refWNaf(bits, w = 2)
          refWNaf(bits, w = 3)
          refWNaf(bits, w = 5)
          refWNaf(bits, w = 8)
          refWNaf(bits, w = 13)

      test(ec, bits = ec.F.C.getCurveOrderBitwidth(), randZ = false, gen = Uniform)
      test(ec, bits = ec.F.C.getCurveOrderBitwidth(), randZ = true, gen = Uniform)
      test(ec, bits = ec.F.C.getCurveOrderBitwidth(), randZ = false, gen = HighHammingWeight)
      test(ec, bits = ec.F.C.getCurveOrderBitwidth(), randZ = true, gen = HighHammingWeight)
      test(ec, bits = ec.F.C.getCurveOrderBitwidth(), randZ = false, gen = Long01Sequence)
      test(ec, bits = ec.F.C.getCurveOrderBitwidth(), randZ = true, gen = Long01Sequence)

    test "EC " & $ec.G & " mul [1]P == P":
      proc test(EC: typedesc, bits: static int, randZ: bool, gen: RandomGen) =
        for _ in 0 ..< ItersMul:
          let a = rng.random_point(EC, randZ, gen)

          var exponent{.noInit.}: BigInt[bits]
          exponent.setOne()

          var
            impl = a
            reference = a

          impl.scalarMulGeneric(exponent)
          reference.scalarMul_doubleAdd_vartime(exponent)

          check:
            bool(impl == a)
            bool(reference == a)

      test(ec, bits = ec.F.C.getCurveOrderBitwidth(), randZ = false, gen = Uniform)
      test(ec, bits = ec.F.C.getCurveOrderBitwidth(), randZ = true, gen = Uniform)
      test(ec, bits = ec.F.C.getCurveOrderBitwidth(), randZ = false, gen = HighHammingWeight)
      test(ec, bits = ec.F.C.getCurveOrderBitwidth(), randZ = true, gen = HighHammingWeight)
      test(ec, bits = ec.F.C.getCurveOrderBitwidth(), randZ = false, gen = Long01Sequence)
      test(ec, bits = ec.F.C.getCurveOrderBitwidth(), randZ = true, gen = Long01Sequence)

    test "EC " & $ec.G & " mul [2]P == P.double()":
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
          reference.scalarMul_doubleAdd_vartime(exponent)

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
       moduleName: string) =
  # Random seed for reproducibility
  var rng: RngState
  let seed = uint32(getTime().toUnix() and (1'i64 shl 32 - 1)) # unixTime mod 2^32
  rng.seed(seed)
  echo "\n------------------------------------------------------\n"
  echo moduleName, " xoshiro512** seed: ", seed

  const testSuiteDesc = "Elliptic curve in " & $ec.F.C.getEquationForm() & " form"

  suite testSuiteDesc & " - " & $ec & " - [" & $WordBitWidth & "-bit mode]":

    test "EC " & $ec.G & " mul is distributive over EC add":
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
          fReference.scalarMul_doubleAdd_vartime(exponent)

          # [k]a + [k]b - Distributed
          var kaImpl = a
          var kaRef = a

          kaImpl.scalarMulGeneric(exponent)
          kaRef.scalarMul_doubleAdd_vartime(exponent)

          var kbImpl = b
          var kbRef = b

          kbImpl.scalarMulGeneric(exponent)
          kbRef.scalarMul_doubleAdd_vartime(exponent)

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
       moduleName: string) =
  # Random seed for reproducibility
  var rng: RngState
  let seed = uint32(getTime().toUnix() and (1'i64 shl 32 - 1)) # unixTime mod 2^32
  rng.seed(seed)
  echo "\n------------------------------------------------------\n"
  echo moduleName, " xoshiro512** seed: ", seed

  const testSuiteDesc = "Elliptic curve in " & $ec.F.C.getEquationForm() & " form"

  suite testSuiteDesc & " - " & $ec & " - [" & $WordBitWidth & "-bit mode]":
    test "EC " & $ec.G & " mul constant-time is equivalent to a simple double-and-add and recoded algorithms":
      proc test(EC: typedesc, bits: static int, randZ: bool, gen: RandomGen) =
        for _ in 0 ..< ItersMul:
          let a = rng.random_point(EC, randZ, gen)

          # We want to test how window methods handles unbalanced 0/1
          let exponent = rng.random_long01Seq(BigInt[bits])

          var
            impl = a
            reference = a
            refMinWeight = a

          impl.scalarMulGeneric(exponent)
          reference.scalarMul_doubleAdd_vartime(exponent)
          refMinWeight.scalarMul_minHammingWeight_vartime(exponent)

          check:
            bool(impl == reference)
            bool(impl == refMinWeight)

          proc refWNaf(w: static int) = # workaround staticFor symbol visibility
            var refWNAF = a
            refWNAF.scalarMul_minHammingWeight_windowed_vartime(exponent, window = w)
            check: bool(impl == refWNAF)

          refWNaf(2)
          refWNaf(3)
          refWNaf(5)
          refWNaf(8)
          refWNaf(13)

      test(ec, bits = ec.F.C.getCurveOrderBitwidth(), randZ = false, gen = Uniform)
      test(ec, bits = ec.F.C.getCurveOrderBitwidth(), randZ = true, gen = Uniform)
      test(ec, bits = ec.F.C.getCurveOrderBitwidth(), randZ = false, gen = HighHammingWeight)
      test(ec, bits = ec.F.C.getCurveOrderBitwidth(), randZ = true, gen = HighHammingWeight)
      test(ec, bits = ec.F.C.getCurveOrderBitwidth(), randZ = false, gen = Long01Sequence)
      test(ec, bits = ec.F.C.getCurveOrderBitwidth(), randZ = true, gen = Long01Sequence)

proc run_EC_mixed_add_impl*(
       ec: typedesc,
       Iters: static int,
       moduleName: string) =
  # Random seed for reproducibility
  var rng: RngState
  let seed = uint32(getTime().toUnix() and (1'i64 shl 32 - 1)) # unixTime mod 2^32
  rng.seed(seed)
  echo "\n------------------------------------------------------\n"
  echo moduleName, " xoshiro512** seed: ", seed

  const testSuiteDesc = "Elliptic curve mixed addition for Short Weierstrass form"

  suite testSuiteDesc & " - " & $ec & " - [" & $WordBitWidth & "-bit mode]":
    test "EC " & $ec.G & " mixed addition is consistent with general addition":
      proc test(EC: typedesc, randZ: bool, gen: RandomGen) =
        for _ in 0 ..< Iters:
          let a = rng.random_point(EC, randZ, gen)
          let b = rng.random_point(EC, randZ, gen)
          var bAff: ECP_ShortW_Aff[EC.F, EC.G]
          bAff.affine(b)

          var r_generic, r_mixed: EC

          r_generic.sum(a, b)
          r_mixed.madd(a, bAff)

          check: bool(r_generic == r_mixed)

      test(ec, randZ = false, gen = Uniform)
      test(ec, randZ = true, gen = Uniform)
      test(ec, randZ = false, gen = HighHammingWeight)
      test(ec, randZ = true, gen = HighHammingWeight)
      test(ec, randZ = false, gen = Long01Sequence)
      test(ec, randZ = true, gen = Long01Sequence)

    test "EC " & $ec.G & " mixed addition - doubling":
      proc test(EC: typedesc, randZ: bool, gen: RandomGen) =
        for _ in 0 ..< Iters:
          let a = rng.random_point(EC, randZ, gen)
          var aAff: ECP_ShortW_Aff[EC.F, EC.G]
          aAff.affine(a)

          var r_generic, r_mixed: EC

          r_generic.double(a)
          r_mixed.madd(a, aAff)
          check: bool(r_generic == r_mixed)

          # Aliasing test
          r_mixed = a
          r_mixed += aAff
          check: bool(r_generic == r_mixed)

      test(ec, randZ = false, gen = Uniform)
      test(ec, randZ = true, gen = Uniform)
      test(ec, randZ = false, gen = HighHammingWeight)
      test(ec, randZ = true, gen = HighHammingWeight)
      test(ec, randZ = false, gen = Long01Sequence)
      test(ec, randZ = true, gen = Long01Sequence)

    test "EC " & $ec.G & " mixed addition - adding infinity LHS":
      proc test(EC: typedesc, randZ: bool, gen: RandomGen) =
        for _ in 0 ..< Iters:
          var a{.noInit.}: EC
          a.setInf()
          let bAff = rng.random_point(ECP_ShortW_Aff[EC.F, EC.G], randZ = false, gen)

          var r_mixed{.noInit.}: EC
          r_mixed.madd(a, bAff)

          var r{.noInit.}: ECP_ShortW_Aff[EC.F, EC.G]
          r.affine(r_mixed)

          a += bAff

          check:
            bool(r == bAff)
            bool(a == r_mixed)

      test(ec, randZ = false, gen = Uniform)
      test(ec, randZ = false, gen = HighHammingWeight)
      test(ec, randZ = false, gen = Long01Sequence)

    test "EC " & $ec.G & " mixed addition - adding infinity RHS":
      proc test(EC: typedesc, randZ: bool, gen: RandomGen) =
        for _ in 0 ..< Iters:
          let a = rng.random_point(EC, randZ, gen)
          var naAff{.noInit.}: ECP_ShortW_Aff[EC.F, EC.G]
          naAff.affine(a)
          naAff.neg()

          var r{.noInit.}: EC
          r.madd(a, naAff)

          check: r.isInf().bool

          r = a
          r += naAff
          check: r.isInf().bool

      test(ec, randZ = false, gen = Uniform)
      test(ec, randZ = true, gen = Uniform)
      test(ec, randZ = false, gen = HighHammingWeight)
      test(ec, randZ = true, gen = HighHammingWeight)
      test(ec, randZ = false, gen = Long01Sequence)
      test(ec, randZ = true, gen = Long01Sequence)

    test "EC " & $ec.G & " mixed addition - adding opposites":
      proc test(EC: typedesc, randZ: bool, gen: RandomGen) =
        for _ in 0 ..< Iters:
          let a = rng.random_point(EC, randZ, gen)
          var bAff{.noInit.}: ECP_ShortW_Aff[EC.F, EC.G]
          bAff.setInf()

          var r{.noInit.}: EC
          r.madd(a, bAff)

          check: bool(r == a)

          r = a
          r += bAff
          check: bool(r == a)

      test(ec, randZ = false, gen = Uniform)
      test(ec, randZ = true, gen = Uniform)
      test(ec, randZ = false, gen = HighHammingWeight)
      test(ec, randZ = true, gen = HighHammingWeight)
      test(ec, randZ = false, gen = Long01Sequence)
      test(ec, randZ = true, gen = Long01Sequence)

proc run_EC_subgroups_cofactors_impl*(
       ec: typedesc,
       ItersMul: static int,
       moduleName: string) =
  # Random seed for reproducibility
  var rng: RngState
  let seed = uint32(getTime().toUnix() and (1'i64 shl 32 - 1)) # unixTime mod 2^32
  rng.seed(seed)
  echo "\n------------------------------------------------------\n"
  echo moduleName, " xoshiro512** seed: ", seed

  const testSuiteDesc = "Elliptic curve subgroup check and cofactor clearing"

  suite testSuiteDesc & " - " & $ec & " - [" & $WordBitWidth & "-bit mode]":
    test "Effective cofactor matches accelerated cofactor clearing" & " - " & $ec & " - [" & $WordBitWidth & "-bit mode]":
      proc test(EC: typedesc, randZ: bool, gen: RandomGen) =
        for _ in 0 ..< ItersMul:
          let P = rng.random_point(EC, randZ, gen)
          var cPeff = P
          var cPfast = P

          cPeff.clearCofactorReference()
          cPfast.clearCofactorFast()

          check: bool(cPeff == cPfast)

      test(ec, randZ = false, gen = Uniform)
      test(ec, randZ = true, gen = Uniform)
      test(ec, randZ = false, gen = HighHammingWeight)
      test(ec, randZ = true, gen = HighHammingWeight)
      test(ec, randZ = false, gen = Long01Sequence)
      test(ec, randZ = true, gen = Long01Sequence)

    test "Subgroup checks and cofactor clearing consistency":
      var inSubgroup = 0
      var offSubgroup = 0
      proc test(EC: typedesc, randZ: bool, gen: RandomGen) =
        stdout.write "    "
        for _ in 0 ..< ItersMul:
          let P = rng.random_point(EC, randZ, gen)
          var rP = P
          rP.scalarMulGeneric(EC.F.C.getCurveOrder())
          if bool rP.isInf():
            inSubgroup += 1
            doAssert bool P.isInSubgroup(), "Subgroup check issue on " & $EC & " with P: " & P.toHex()
          else:
            offSubgroup += 1
            doAssert not bool P.isInSubgroup(), "Subgroup check issue on " & $EC & " with P: " & P.toHex()

          var Q = P
          var rQ: typeof(rP)
          Q.clearCofactor()
          rQ = Q
          rQ.scalarMulGeneric(EC.F.C.getCurveOrder())
          doAssert bool rQ.isInf(), "Cofactor clearing issue on " & $EC & " with Q: " & Q.toHex()
          doAssert bool Q.isInSubgroup(), "Subgroup check issue on " & $EC & " with Q: " & Q.toHex()

          stdout.write '.'

        stdout.write '\n'

      test(ec, randZ = false, gen = Uniform)
      test(ec, randZ = true, gen = Uniform)
      test(ec, randZ = false, gen = HighHammingWeight)
      test(ec, randZ = true, gen = HighHammingWeight)
      test(ec, randZ = false, gen = Long01Sequence)
      test(ec, randZ = true, gen = Long01Sequence)

      echo "    [SUCCESS] Test finished with ", inSubgroup, " points in ", $ec.G, " subgroup and ",
              offSubgroup, " points on curve but not in subgroup (before cofactor clearing)"

proc run_EC_affine_conversion*(
       ec: typedesc,
       Iters: static int,
       moduleName: string) =
  # Random seed for reproducibility
  var rng: RngState
  let seed = uint32(getTime().toUnix() and (1'i64 shl 32 - 1)) # unixTime mod 2^32
  rng.seed(seed)
  echo "\n------------------------------------------------------\n"
  echo moduleName, " xoshiro512** seed: ", seed

  const testSuiteDesc = "Elliptic curve in " & $ec.F.C.getEquationForm() & " form"

  suite testSuiteDesc & " - " & $ec & " - [" & $WordBitWidth & "-bit mode]":
    test "EC " & $ec.G & " batchAffine is consistent with single affine conversion":
      proc test(EC: typedesc, gen: RandomGen) =
        const batchSize = 10
        for _ in 0 ..< Iters:
          var Ps: array[batchSize, EC]
          for i in 0 ..< batchSize:
            Ps[i] = rng.random_point(EC, randZ = true, gen)

          var Qs, Rs: array[batchSize, affine(EC)]
          for i in 0 ..< batchSize:
            Qs[i].affine(Ps[i])
          Rs.batchAffine(Ps)

          for i in countdown(batchSize-1, 0):
            doAssert bool(Qs[i] == Rs[i]), block:
              var s: string
              s &= "Mismatch on iteration " & $i
              s &= "\nFailing batch for " & $EC & " (" & $WordBitWidth & "-bit)"
              s &= "\n  ["
              for i in 0 ..< batchSize:
                s &= "\n" & Ps[i].toHex(indent = 4)
                if i != batchSize-1: s &= ","
              s &= "\n  ]"
              s &= "\nFailing inversions for " & $EC & " (" & $WordBitWidth & "-bit)"
              s &= "\n  ["
              for i in 0 ..< batchSize:
                s &= "\n" & Rs[i].toHex(indent = 4)
                if i != batchSize-1: s &= ","
              s &= "\n  ]"
              s &= "\nExpected inversions for " & $EC & " (" & $WordBitWidth & "-bit)"
              s &= "\n  ["
              for i in 0 ..< batchSize:
                s &= "\n" & Qs[i].toHex(indent = 4)
                if i != batchSize-1: s &= ","
              s &= "\n  ]"
              s

      test(ec, gen = Uniform)
      test(ec, gen = HighHammingWeight)
      test(ec, gen = Long01Sequence)

proc run_EC_conversion_failures*(
       moduleName: string
     ) =

  echo "\n------------------------------------------------------\n"
  echo moduleName

  suite moduleName & " - [" & $WordBitWidth & "-bit mode]":
    test "EC batchAffine fuzzing failures ":
      proc test_bn254_snarks_g1(ECP: type) =
        type ECP_Aff = ECP_ShortW_Aff[Fp[BN254_Snarks], G1]

        let Ps = [
          ECP.fromHex(
            x = "0x0e0a76c19a07e01fe56f246f7878652c0b39eb28f5c60b3dd43e438dc50e0d9d",
            y = "0x04e6da44bc7f802fab3df34ce45d86857327663bc24ff574da48ee2b01a4932e"
          ),
          ECP.fromHex(
            x = "0x2036a21a3d9cc09d8f5f7491fe7e4f44cffd2addf01c6ae587bee7d24f060571",
            y = "0x2b5f1cc6f1cdb4a6dbaf3c88b9c02ccf984aecbba4830d5aeb33f940cb632d8a"
          ),
          ECP.fromHex(
            x = "0x2fd314a75c6b1f82d70f2edc7b7bf6e7397bc04bc6aaa0584b9e5bbb7689082a",
            y = "0x111b3b4a697e7a990400eb39f09a9bb559748cea6699535bd114ffb3dcc0b4d1"
          ),
          ECP.fromHex(
            x = "0x0000000000000000000000000000000000000000000000000000000000000000",
            y = "0x0000000000000000000000000000000000000000000000000000000000000000"
          ),
          ECP.fromHex(
            x = "0x0e0a77c199ffdf2f686ea36f7879462c0a74eb28f5e70b3dd31d438dc58f0d9d",
            y = "0x0b3938a732020d98793510be6aa312651a5f5369ebbbe41d7fda8fd914b7f264"
          ),
          ECP.fromHex(
            x = "0x0000000007ffffffffffffff80000000000007ffe000000000ffffffffffffff",
            y = "0x1d9db0f30e3395ee33a70674a31e2854de0665292dd545c10fb3da579d7df916"
          ),
          ECP.fromHex(
            x = "0x000000000000000fffffffffe0000000000007ffffffffffffffffffffffffff",
            y = "0x2a5c6df4d24efa9ffcf4003e35801dc202d820b59d67ecc65d57cfdf53b4bbc6"
          ),
          ECP.fromHex(
            x = "0x00000000000000000003ffffffc00000000000000c000000000000003ffffffe",
            y = "0x09f811f84207472ccd6ca00bb1ec3e6132a1c9206adc9ed768871f0005f0d358"
          ),
          ECP.fromHex(
            x = "0x0e0979b99d07df30656ea36f7879462c097beb28f5c8083dd25d448dc58f0ca4",
            y = "0x1799b22d8780c917ab1c4e15da718c243babc1c51225b5f8298aa570b5029796"
          ),
          ECP.fromHex(
            x = "0x0e0a76c29a07e02f666ea36e806a462c0a78eb25f5c70b3dd35c4b8dc58f0d9c",
            y = "0x0529cb1ad2552c7979a900ff59551d5dc1f8680c3a4f20d3b9cdcf68b69ec61c"
          )
        ]

        let Qs = [
          ECP_Aff.fromHex(
            x = "0x0e0a76c19a07e01fe56f246f7878652c0b39eb28f5c60b3dd43e438dc50e0d9d",
            y = "0x04e6da44bc7f802fab3df34ce45d86857327663bc24ff574da48ee2b01a4932e"
          ),
          ECP_Aff.fromHex(
            x = "0x2036a21a3d9cc09d8f5f7491fe7e4f44cffd2addf01c6ae587bee7d24f060571",
            y = "0x2b5f1cc6f1cdb4a6dbaf3c88b9c02ccf984aecbba4830d5aeb33f940cb632d8a"
          ),
          ECP_Aff.fromHex(
            x = "0x2fd314a75c6b1f82d70f2edc7b7bf6e7397bc04bc6aaa0584b9e5bbb7689082a",
            y = "0x111b3b4a697e7a990400eb39f09a9bb559748cea6699535bd114ffb3dcc0b4d1"
          ),
          ECP_Aff.fromHex(
            x = "0x0000000000000000000000000000000000000000000000000000000000000000",
            y = "0x0000000000000000000000000000000000000000000000000000000000000000"
          ),
          ECP_Aff.fromHex(
            x = "0x0e0a77c199ffdf2f686ea36f7879462c0a74eb28f5e70b3dd31d438dc58f0d9d",
            y = "0x0b3938a732020d98793510be6aa312651a5f5369ebbbe41d7fda8fd914b7f264"
          ),
          ECP_Aff.fromHex(
            x = "0x0000000007ffffffffffffff80000000000007ffe000000000ffffffffffffff",
            y = "0x1d9db0f30e3395ee33a70674a31e2854de0665292dd545c10fb3da579d7df916"
          ),
          ECP_Aff.fromHex(
            x = "0x000000000000000fffffffffe0000000000007ffffffffffffffffffffffffff",
            y = "0x2a5c6df4d24efa9ffcf4003e35801dc202d820b59d67ecc65d57cfdf53b4bbc6"
          ),
          ECP_Aff.fromHex(
            x = "0x00000000000000000003ffffffc00000000000000c000000000000003ffffffe",
            y = "0x09f811f84207472ccd6ca00bb1ec3e6132a1c9206adc9ed768871f0005f0d358"
          ),
          ECP_Aff.fromHex(
            x = "0x0e0979b99d07df30656ea36f7879462c097beb28f5c8083dd25d448dc58f0ca4",
            y = "0x1799b22d8780c917ab1c4e15da718c243babc1c51225b5f8298aa570b5029796"
          ),
          ECP_Aff.fromHex(
            x = "0x0e0a76c29a07e02f666ea36e806a462c0a78eb25f5c70b3dd35c4b8dc58f0d9c",
            y = "0x0529cb1ad2552c7979a900ff59551d5dc1f8680c3a4f20d3b9cdcf68b69ec61c"
          )
        ]

        var Rs: array[10, ECP_Aff]
        Rs.batchAffine(Ps)
        for i in 0 ..< 10:
          doAssert bool(Qs[i] == Rs[i])

      test_bn254_snarks_g1(ECP_ShortW_Prj[Fp[BN254_Snarks], G1])
      test_bn254_snarks_g1(ECP_ShortW_Jac[Fp[BN254_Snarks], G1])

proc run_EC_batch_add_impl*[N: static int](
       ec: typedesc,
       numPoints: array[N, int],
       moduleName: string) =
  # Random seed for reproducibility
  var rng: RngState
  let seed = uint32(getTime().toUnix() and (1'i64 shl 32 - 1)) # unixTime mod 2^32
  rng.seed(seed)
  echo "\n------------------------------------------------------\n"
  echo moduleName, " xoshiro512** seed: ", seed

  const testSuiteDesc = "Elliptic curve sum reduction for Short Weierstrass form"

  suite testSuiteDesc & " - " & $ec & " - [" & $WordBitWidth & "-bit mode]":
    for n in numPoints:
      test $ec & " sum reduction (N=" & $n & ")":
        proc test(EC: typedesc, gen: RandomGen) =
          var points = newSeq[ECP_ShortW_Aff[EC.F, EC.G]](n)

          for i in 0 ..< n:
            points[i] = rng.random_point(ECP_ShortW_Aff[EC.F, EC.G], randZ = false, gen)

          var r_batch{.noinit.}, r_ref{.noInit.}: EC

          r_ref.setInf()
          for i in 0 ..< n:
            r_ref += points[i]

          r_batch.sum_reduce_vartime(points)

          check: bool(r_batch == r_ref)


        test(ec, gen = Uniform)
        test(ec, gen = HighHammingWeight)
        test(ec, gen = Long01Sequence)

      test "EC " & $ec.G & " sum reduction (N=" & $n & ") - special cases":
        proc test(EC: typedesc, gen: RandomGen) =
          var points = newSeq[ECP_ShortW_Aff[EC.F, EC.G]](n)

          let halfN = n div 2

          for i in 0 ..< halfN:
            points[i] = rng.random_point(ECP_ShortW_Aff[EC.F, EC.G], randZ = false, gen)

          for i in halfN ..< n:
            # The special cases test relies on internal knowledge that we sum(points[i], points[i+n/2]
            # It should be changed if scheduling change, for example if we sum(points[2*i], points[2*i+1])
            let c = rng.random_unsafe(3)
            if c == 0:
              points[i] = rng.random_point(ECP_ShortW_Aff[EC.F, EC.G], randZ = false, gen)
            elif c == 1:
              points[i] = points[i-halfN]
            else:
              points[i].neg(points[i-halfN])

          var r_batch{.noinit.}, r_ref{.noInit.}: EC

          r_ref.setInf()
          for i in 0 ..< n:
            r_ref += points[i]

          r_batch.sum_reduce_vartime(points)

          check: bool(r_batch == r_ref)

        test(ec, gen = Uniform)
        test(ec, gen = HighHammingWeight)
        test(ec, gen = Long01Sequence)

proc run_EC_multi_scalar_mul_impl*[N: static int](
       ec: typedesc,
       numPoints: array[N, int],
       moduleName: string) =
  # Random seed for reproducibility
  var rng: RngState
  let seed = uint32(getTime().toUnix() and (1'i64 shl 32 - 1)) # unixTime mod 2^32
  rng.seed(seed)
  echo "\n------------------------------------------------------\n"
  echo moduleName, " xoshiro512** seed: ", seed

  const testSuiteDesc = "Elliptic curve multi-scalar-multiplication for Short Weierstrass form"

  suite testSuiteDesc & " - " & $ec & " - [" & $WordBitWidth & "-bit mode]":
    for n in numPoints:
      let bucketBits = bestBucketBitSize(n, ec.F.C.getCurveOrderBitwidth(), useSignedBuckets = false, useManualTuning = false)
      test $ec & " Multi-scalar-mul (N=" & $n & ", bucket bits: " & $bucketBits & ")":
        proc test(EC: typedesc, gen: RandomGen) =
          var points = newSeq[ECP_ShortW_Aff[EC.F, EC.G]](n)
          var coefs = newSeq[BigInt[EC.F.C.getCurveOrderBitwidth()]](n)

          for i in 0 ..< n:
            var tmp = rng.random_unsafe(EC)
            tmp.clearCofactor()
            points[i].affine(tmp)
            coefs[i] = rng.random_unsafe(BigInt[EC.F.C.getCurveOrderBitwidth()])

          var naive, naive_tmp: EC
          naive.setInf()
          for i in 0 ..< n:
            naive_tmp.fromAffine(points[i])
            naive_tmp.scalarMul(coefs[i])
            naive += naive_tmp

          var msm_ref, msm: EC
          msm_ref.multiScalarMul_reference_vartime(coefs, points)
          msm.multiScalarMul_vartime(coefs, points)

          doAssert bool(naive == msm_ref)
          doAssert bool(naive == msm)

        test(ec, gen = Uniform)
        test(ec, gen = HighHammingWeight)
        test(ec, gen = Long01Sequence)