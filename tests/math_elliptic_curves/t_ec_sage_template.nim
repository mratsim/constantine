# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  # Standard library
  std/[unittest, times, os, strutils, macros],
  # 3rd party
  pkg/jsony,
  # Internals
  constantine/platforms/abstractions,
  constantine/math/[arithmetic, extension_fields],
  constantine/math/io/[io_bigints, io_ec],
  constantine/math/ec_shortweierstrass,
  constantine/named/zoo_endomorphisms

export unittest, abstractions, arithmetic # Generic sandwich

# Serialization
# --------------------------------------------------------------------------

type
  TestVector*[EC: EC_ShortW_Aff, bits: static int] = object
    id: int
    P: EC
    scalarBits: int
    scalar: BigInt[bits]
    Q: EC

  EC_G1_hex = object
    x: string
    y: string

  Fp2_hex = object
    c0: string
    c1: string

  EC_G2_hex = object
    x: Fp2_hex
    y: Fp2_hex

  ScalarMulTestG1[EC: EC_ShortW_Aff, bits: static int] = object
    curve: string
    group: string
    modulus: string
    order: string
    cofactor: string
    form: string
    a: string
    b: string
    # vectors ------------------
    vectors: seq[TestVector[EC, bits]]

  ScalarMulTestG2[EC: EC_ShortW_Aff, bits: static int] = object
    curve: string
    group: string
    modulus: string
    order: string
    cofactor: string
    form: string
    a: string
    b: string
    # G2 -----------------------
    twist_degree: int
    twist: string
    non_residue_fp: int
    G2_field: string
    when EC.F is Fp:
      non_residue_twist: int
    else:
      non_residue_twist: array[2, int]
    # vectors ------------------
    vectors: seq[TestVector[EC, bits]]

const
  TestVectorsDir* =
    currentSourcePath.rsplit(DirSep, 1)[0] / "vectors"

proc parseHook*(src: string, pos: var int, value: var BigInt) =
  var str: string
  parseHook(src, pos, str)
  value.fromHex(str)

proc parseHook*(src: string, pos: var int, value: var EC_ShortW_Aff) =
  # Note when nim-serialization was used:
  #   When EC_ShortW_Aff[Fp[Foo], G1]
  #   and EC_ShortW_Aff[Fp[Foo], G2]
  #   are generated in the same file (i.e. twists and base curve are both on Fp)
  #   this creates bad codegen, in the C code, the `value`parameter gets the wrong type
  #   TODO: upstream
  when EC_ShortW_Aff.F is Fp:
    var P: EC_G1_hex
    parseHook(src, pos, P)
    let ok = value.fromHex(P.x, P.y)
    doAssert ok, "\nDeserialization error on G1 for\n" &
      "  P.x: " & P.x & "\n" &
      "  P.y: " & P.x & "\n"
  elif EC_ShortW_Aff.F is Fp2:
    var P: EC_G2_hex
    parseHook(src, pos, P)
    let ok = value.fromHex(P.x.c0, P.x.c1, P.y.c0, P.y.c1)
    doAssert ok, "\nDeserialization error on G2 for\n" &
      "  P.x0: " & P.x.c0 & "\n" &
      "  P.x1: " & P.x.c1 & "\n" &
      "  P.y0: " & P.y.c0 & "\n" &
      "  P.y1: " & P.y.c1 & "\n"
  else:
    {.error: "Not Implemented".}

proc loadVectors(TestType: typedesc): TestType =
  const group = when TestType.EC.G == G1: "G1"
                else: "G2"
  const filename = "tv_" & $TestType.EC.F.Name & "_scalar_mul_" & group & "_" & $TestType.bits & "bit.json"
  echo "Loading: ", filename
  let content = readFile(TestVectorsDir/filename)
  result = content.fromJson(TestType)

# Testing
# ------------------------------------------------------------------------

proc run_scalar_mul_test_vs_sage*(
       EC: typedesc, bits: static int,
       moduleName: string
     ) =
  echo "\n------------------------------------------------------\n"
  echo moduleName & '\n'

  when EC.G == G1:
    const G1_or_G2 = "G1"
    let vec = loadVectors(ScalarMulTestG1[EC_ShortW_Aff[EC.F, EC.G], bits])
  else:
    const G1_or_G2 = "G2"
    let vec = loadVectors(ScalarMulTestG2[EC_ShortW_Aff[EC.F, EC.G], bits])

  const coord = when EC is EC_ShortW_Prj: " Projective coordinates "
                elif EC is EC_ShortW_Jac: " Jacobian coordinates "

  const testSuiteDesc = "Scalar Multiplication " & $EC.getName() & " " & G1_or_G2 & " " & coord & " vs SageMath - " & $bits & "-bit scalar"

  suite testSuiteDesc & " [" & $WordBitWidth & "-bit words]":
    for i in 0 ..< vec.vectors.len:
      test "test " & $vec.vectors[i].id & " - " & $EC & " - " & $bits & "-bit scalar":
        var
          P{.noInit.}: EC
          Q {.noInit.}: EC
          impl {.noInit.}: EC
          reference {.noInit.}: EC
          refMinWeight {.noInit.}: EC

        P.fromAffine(vec.vectors[i].P)
        Q.fromAffine(vec.vectors[i].Q)
        impl = P
        reference = P
        refMinWeight = P

        impl.scalarMulGeneric(vec.vectors[i].scalar)
        reference.scalarMul_doubleAdd_vartime(vec.vectors[i].scalar)
        refMinWeight.scalarMul_jy00_vartime(vec.vectors[i].scalar)

        doAssert: bool(Q == reference)
        doAssert: bool(Q == impl)
        doAssert: bool(Q == refMinWeight)

        staticFor w, 2, 5:
          var refWNAF = P
          refWNAF.scalarMul_wNAF_vartime(vec.vectors[i].scalar, window = w)
          check: bool(impl == refWNAF)

        when bits >= EndomorphismThreshold: # All endomorphisms constants are below this threshold
          var endo = P
          endo.scalarMulEndo(vec.vectors[i].scalar)
          doAssert: bool(Q == endo)

          when EC.F is Fp: # Test windowed endomorphism acceleration
            var endoW = P
            endoW.scalarMulGLV_m2w2(vec.vectors[i].scalar)
            doAssert: bool(Q == endoW)

          staticFor w, 2, 5:
            var endoWNAF = P
            endoWNAF.scalarMulEndo_wNAF_vartime(vec.vectors[i].scalar, window = w)
            check: bool(impl == endoWNAF)
