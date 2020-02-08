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
  ../io, ../bigints

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
  var CurveBitSize = nnKBracket.newTree()
  var curveModStmts = newStmtList()
  var curveModWhenStmt = nnkWhenStmt.newTree()

  for curveDesc in curves:
    curveDesc.expectKind(nnkCommand)
    doAssert curveDesc[0].eqIdent"curve"
    curveDesc[1].expectKind(nnkIdent)    # Curve name
    curveDesc[2].expectKind(nnkStmtList)
    curveDesc[2][0].expectKind(nnkCall)
    curveDesc[2][1].expectKind(nnkCall)

    let curve = curveDesc[1]

    let sizeSection = curveDesc[2][0]
    doAssert sizeSection[0].eqIdent"bitsize"
    sizeSection[1].expectKind(nnkStmtList)
    let bitSize = sizeSection[1][0]

    let modSection = curveDesc[2][1]
    doAssert modSection[0].eqIdent"modulus"
    modSection[1].expectKind(nnkStmtList)
    let modulus = modSection[1][0]

    Curves.add curve
    # "BN254: 254" for array construction
    CurveBitSize.add nnkExprColonExpr.newTree(
      curve, bitSize
    )

    # const BN254_Modulus = fromHex(BigInt[254], "0x30644e72e131a029b85045b68181585d97816a916871ca8d3c208c16d87cfd47")
    let modulusID = ident($curve & "_Modulus")
    curveModStmts.add newConstStmt(
      modulusID,
      newCall(
        bindSym"fromHex",
        nnkBracketExpr.newTree(
          bindSym"BigInt",
          bitSize
        ),
        modulus
      )
    )

    # when curve == BN254: BN254_Modulus
    curveModWhenStmt.add nnkElifBranch.newTree(
      nnkInfix.newTree(
        ident"==",
        ident"curve",
        curve
      ),
      modulusID
    )

  result = newStmtList()

  result.add newEnum(
    name = ident"Curve",
    fields = Curves,
    public = true,
    pure = false
  )

  let cbs = ident("CurveBitSize")
  result.add quote do:
    const `cbs`*: array[Curve, int] = `CurveBitSize`

  result.add curveModStmts

  # Add 'else: {.error: "Unreachable".}' to the when statements
  curveModWhenStmt.add nnkElse.newTree(
    nnkPragma.newTree(
      nnkExprColonExpr.newTree(
        ident"error",
        newLit"Unreachable: the curve does not exist."
      )
    )
  )
  result.add newProc(
    name = nnkPostfix.newTree(ident"*", ident"Mod"),
    params = [
      ident"auto",
      newIdentDefs(
        name = ident"curve",
        kind = nnkStaticTy.newTree(ident"Curve")
      )
    ],
    body = curveModWhenStmt,
    procType = nnkFuncDef,
    pragmas = nnkPragma.newTree(ident"compileTime")
  )

  # echo result.toStrLit
