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
  jsony,
  # Internals
  ../constantine/config/[common, curves, type_bigint, type_ff],
  ../constantine/towers,
  ../constantine/io/[io_bigints, io_ec],
  ../constantine/elliptic/[
    ec_shortweierstrass_affine,
    ec_shortweierstrass_projective,
    ec_shortweierstrass_jacobian,
    ec_scalar_mul,
    ec_endomorphism_accel],
  # Test utilities
  ./support/ec_reference_scalar_mult

# Serialization
# --------------------------------------------------------------------------

macro matchingScalar*(EC: type ECP_ShortW_Aff): untyped =
  ## Workaround the annoying type system
  ## 1. Higher-kinded type
  ## 2. Computation in type section needs template or macro indirection
  ## 3. Converting NimNode to typedesc
  ##      https://github.com/nim-lang/Nim/issues/6785
  # BigInt[EC.F.C.getCurveOrderBitwidth()]

  let ec = EC.getTypeImpl()
  # echo ec.treerepr
  # BracketExpr
  # Sym "typeDesc"
  # BracketExpr
  #   Sym "ECP_ShortW_Aff"
  #   BracketExpr
  #     Sym "Fp"
  #     IntLit 12
  #   IntLit 0

  doAssert ec[0].eqIdent"typedesc"
  doAssert ec[1][0].eqIdent"ECP_ShortW_Aff"
  ec[1][1].expectkind(nnkBracketExpr)
  doAssert ($ec[1][1][0]).startsWith"Fp"

  let curve = Curve(ec[1][1][1].intVal)
  let bitwidth = getAST(getCurveOrderBitwidth(curve))
  result = nnkBracketExpr.newTree(
    bindSym"BigInt",
    bitwidth
  )

macro matchingNonResidueType*(EC: type ECP_ShortW_Aff): untyped =
  ## Workaround the annoying type system
  ## 1. Higher-kinded type
  ## 2. Computation in type section needs template or macro indirection
  ## 3. Converting NimNode to typedesc
  ##      https://github.com/nim-lang/Nim/issues/6785
  let ec = EC.getTypeImpl()
  doAssert ec[0].eqIdent"typedesc"
  doAssert ec[1][0].eqIdent"ECP_ShortW_Aff"
  ec[1][1].expectkind(nnkBracketExpr)
  doAssert ($ec[1][1][0]).startsWith"Fp"

  # int or array[2, int]
  if ec[1][1][0].eqIdent"Fp":
    result = bindSym"int"
  elif ec[1][1][0].eqIdent"Fp2":
    result = nnkBracketExpr.newTree(
      bindSym"array",
      newLit 2,
      bindSym"int"
    )

type
  TestVector*[EC: ECP_ShortW_Aff] = object
    id: int
    P: EC
    scalar: matchingScalar(EC)
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

  ScalarMulTestG1[EC: ECP_ShortW_Aff] = object
    curve: string
    group: string
    modulus: string
    order: string
    cofactor: string
    form: string
    a: string
    b: string
    # vectors ------------------
    vectors: seq[TestVector[EC]]

  ScalarMulTestG2[EC: ECP_ShortW_Aff] = object
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
    non_residue_twist: matchingNonResidueType(EC) # int or array[2, int]
    # vectors ------------------
    vectors: seq[TestVector[EC]]

const
  TestVectorsDir* =
    currentSourcePath.rsplit(DirSep, 1)[0] / "vectors"

proc parseHook*(src: string, pos: var int, value: var BigInt) =
  var str: string
  parseHook(src, pos, str)
  value.fromHex(str)

proc parseHook*(src: string, pos: var int, value: var ECP_ShortW_Aff) =
  # Note when nim-serialization was used:
  #   When ECP_ShortW_Aff[Fp[Foo], G1]
  #   and ECP_ShortW_Aff[Fp[Foo], G2]
  #   are generated in the same file (i.e. twists and base curve are both on Fp)
  #   this creates bad codegen, in the C code, the `value`parameter gets the wrong type
  #   TODO: upstream
  when ECP_ShortW_Aff.F is Fp:
    var P: EC_G1_hex
    parseHook(src, pos, P)
    let ok = value.fromHex(P.x, P.y)
    doAssert ok, "\nDeserialization error on G1 for\n" &
      "  P.x: " & P.x & "\n" &
      "  P.y: " & P.x & "\n"
  elif ECP_ShortW_Aff.F is Fp2:
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
  const filename = "tv_" & $TestType.EC.F.C & "_scalar_mul_" & group & ".json"
  let content = readFile(TestVectorsDir/filename)
  result = content.fromJson(TestType)

# Testing
# ------------------------------------------------------------------------

proc run_scalar_mul_test_vs_sage*(
       EC: typedesc,
       moduleName: string
     ) =
  echo "\n------------------------------------------------------\n"
  echo moduleName & '\n'

  when EC.G == G1:
    const G1_or_G2 = "G1"
    let vec = loadVectors(ScalarMulTestG1[ECP_ShortW_Aff[EC.F, EC.G]])
  else:
    const G1_or_G2 = "G2"
    let vec = loadVectors(ScalarMulTestG2[ECP_ShortW_Aff[EC.F, EC.G]])

  const coord = when EC is ECP_ShortW_Prj: " Projective coordinates "
                elif EC is ECP_ShortW_Jac: " Jacobian coordinates "

  const testSuiteDesc = "Scalar Multiplication " & $EC.F.C & " " & G1_or_G2 & " vs SageMath"

  suite testSuiteDesc & " [" & $WordBitwidth & "-bit mode]":
    for i in 0 ..< vec.vectors.len:
      test "test " & $vec.vectors[i].id & " - " & $EC:
        var
          P{.noInit.}: EC
          Q {.noInit.}: EC
          impl {.noInit.}: EC
          reference {.noInit.}: EC
          endo {.noInit.}: EC

        when EC is ECP_ShortW_Prj:
          P.fromAffine(vec.vectors[i].P)
          Q.fromAffine(vec.vectors[i].Q)
        else:
          P.fromAffine(vec.vectors[i].P)
          Q.fromAffine(vec.vectors[i].Q)
        impl = P
        reference = P
        endo = P

        impl.scalarMulGeneric(vec.vectors[i].scalar)
        reference.unsafe_ECmul_double_add(vec.vectors[i].scalar)
        endo.scalarMulEndo(vec.vectors[i].scalar)

        doAssert: bool(Q == reference)
        doAssert: bool(Q == impl)
        doAssert: bool(Q == endo)

        when EC.F is Fp: # Test windowed endomorphism acceleration
          var endoW = P
          endoW.scalarMulGLV_m2w2(vec.vectors[i].scalar)
          doAssert: bool(Q == endoW)
