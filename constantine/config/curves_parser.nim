# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  # Standard library
  macros,
  # Internal
  ../io/io_bigints, ../arithmetic/bigints

# Macro to parse declarative curves configuration.

macro declareCurves*(curves: untyped): untyped =
  ## Parse curve configuration and generates
  ##
  ## type Curve = enum
  ##   BN254
  ##   ...
  ##
  ## const CurveBitSize* = array[
  ##   BN254: 254,
  ##   ...
  ## ]
  ##
  ## TODO: Ensure that the modulus is not inlined at runtime
  ##       to avoid codesize explosion.
  ## const BN254_Modulus = fromHex(BigInt[254], "0x30644e72e131a029b85045b68181585d97816a916871ca8d3c208c16d87cfd47")
  ##
  ## func fieldModulus*(curve: static Curve): auto =
  ##   when curve == BN254_Modulus: BN254_Modulus
  ##   ...
  curves.expectKind(nnkStmtList)

  # curve BN254:
  #   bitsize: 254
  #   modulus: "0x30644e72e131a029b85045b68181585d97816a916871ca8d3c208c16d87cfd47"
  #
  # is parsed into
  #
  # StmtList
  #   Command
  #     Ident "curve"
  #     Ident "BN254"
  #     StmtList
  #       Call
  #         Ident "bitsize"
  #         StmtList
  #           IntLit 254
  #       Call
  #         Ident "modulus"
  #         StmtList
  #           StrLit "0x30644e72e131a029b85045b68181585d97816a916871ca8d3c208c16d87cfd47"

  var Curves: seq[NimNode]
  var MapCurveBitWidth = nnkBracket.newTree()
  var MapCurveFamily = nnkBracket.newTree()
  var curveModStmts = newStmtList()
  var curveExtraStmts = newStmtList()

  for curveDesc in curves:
    # Checks
    # -----------------------------------------------
    curveDesc.expectKind(nnkCommand)
    doAssert curveDesc[0].eqIdent"curve"
    curveDesc[1].expectKind(nnkIdent)    # Curve name
    curveDesc[2].expectKind(nnkStmtList)
    curveDesc[2][0].expectKind(nnkCall)
    curveDesc[2][1].expectKind(nnkCall)

    # Mandatory fields
    # -----------------------------------------------
    let curve = curveDesc[1]
    let curveParams = curveDesc[2]

    var offset = 0
    var testCurve = false
    if curveParams[0][0].eqident"testingCurve":
      offset = 1
      testCurve = curveParams[0][1].boolVal

    let sizeSection = curveParams[offset]
    doAssert sizeSection[0].eqIdent"bitsize"
    sizeSection[1].expectKind(nnkStmtList)
    let bitSize = sizeSection[1][0]

    let modSection = curveParams[offset+1]
    doAssert modSection[0].eqIdent"modulus"
    modSection[1].expectKind(nnkStmtList)
    let modulus = modSection[1][0]

    # Construct the constants
    # -----------------------------------------------
    if not testCurve or defined(testingCurves):
      Curves.add curve
      # "BN254: 254" for array construction
      MapCurveBitWidth.add nnkExprColonExpr.newTree(
        curve, bitSize
      )

      # const BN254_Snarks_Modulus = fromHex(BigInt[254], "0x30644e72e131a029b85045b68181585d97816a916871ca8d3c208c16d87cfd47")
      let modulusID = ident($curve & "_Modulus")
      curveModStmts.add newConstStmt(
        modulusID,
        newCall(
          bindSym"fromHex",
          nnkBracketExpr.newTree(bindSym"BigInt", bitSize),
          modulus
        )
      )

    # Family specific
    # -----------------------------------------------
    if offset + 2 < curveParams.len:
      let familySection = curveParams[offset+2]
      doAssert familySection[0].eqIdent"family"
      familySection[1].expectKind(nnkStmtList)
      let family = familySection[1][0]

      MapCurveFamily.add nnkExprColonExpr.newTree(
        curve, family
      )

      if offset + 5 == curveParams.len:
        if family.eqIdent"BarretoNaehrig" and
              curveParams[offset+3][0].eqIdent"bn_u_bitwidth" and
              curveParams[offset+4][0].eqIdent"bn_u":

          let bn_u_bitwidth = curveParams[offset+3][1][0]
          let bn_u = curveParams[offset+4][1][0]

          # const BN254_Snarks_BN_param_u = fromHex(BigInt[63], "0x44E992B44A6909F1")
          curveExtraStmts.add newConstStmt(
            ident($curve & "_BN_param_u"),
            newCall(
              bindSym"fromHex",
              nnkBracketExpr.newTree(bindSym"BigInt", bn_u_bitwidth),
              bn_u
            )
          )

    else:
      MapCurveFamily.add nnkExprColonExpr.newTree(
        curve, ident"NoFamily"
      )

  # end for ---------------------------------------------------

  result = newStmtList()

  # type Curve = enum
  let Curve = ident"Curve"
  result.add newEnum(
    name = Curve,
    fields = Curves,
    public = true,
    pure = false
  )

  # const CurveBitSize: array[Curve, int] = ...
  result.add newConstStmt(
    ident("CurveBitSize"), MapCurveBitWidth
  )
  # const CurveFamily: array[Curve, CurveFamily] = ...
  result.add newConstStmt(
    ident("CurveFamilies"), MapCurveFamily
  )

  result.add curveModStmts
  result.add curveExtraStmts

  echo result.toStrLit()
