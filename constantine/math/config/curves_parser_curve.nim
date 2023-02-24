# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  # Standard library
  std/macros,
  # Internal
  ./type_bigint, ./type_ff,
  ../io/[io_bigints, io_fields],
  ./curves_declaration, ./curves_parser_field

export CurveFamily, Curve, SexticTwist

# ############################################################
#
#                   Curve properties generator
#
# ############################################################

template getCoef(c: CurveCoef, curveName: untyped): untyped {.dirty.}=
  case c.kind
  of NoCoef:
    error "Unreachable"
    nnkDiscardStmt.newTree(newLit "Dummy")
  of Small:
    newLit c.coef
  of Large:
    newCall(
      bindSym"fromHex",
      nnkBracketExpr.newTree(bindSym"Fp", curveName),
      newLit c.coefHex
    )

proc genCurveConstants(defs: seq[CurveParams]): NimNode =
  ## Generate curves main constants

  # MapCurveBitWidth & MapCurveOrderBitWidth
  # are workaround for https://github.com/nim-lang/Nim/issues/16774

  var MapCurveFamily = nnkBracket.newTree()
  var curveEllipticStmts = newStmtList()

  for curveDef in defs:
    curveDef.name.expectKind(nnkIdent)
    curveDef.bitWidth.expectKind(nnkIntLit)
    curveDef.modulus.expectKind(nnkStrLit)

    let curve = curveDef.name
    let family = curveDef.family

    MapCurveFamily.add nnkExprColonExpr.newTree(
        curve, newLit(family)
    )

    # Curve equation
    # -----------------------------------------------
    curveEllipticStmts.add newConstStmt(
      exported($curve & "_equation_form"),
      newLit curveDef.eq_form
    )

    if curveDef.eq_form == ShortWeierstrass and
         curveDef.coef_A.kind != NoCoef and curveDef.coef_B.kind != NoCoef:
      curveEllipticStmts.add newConstStmt(
        exported($curve & "_coef_A"),
        curveDef.coef_A.getCoef(curve)
      )
      curveEllipticStmts.add newConstStmt(
        exported($curve & "_coef_B"),
        curveDef.coef_B.getCoef(curve)
      )

      # Towering
      # -----------------------------------------------
      curveEllipticStmts.add newConstStmt(
        exported($curve & "_nonresidue_fp"),
        curveDef.nonresidue_fp
      )
      curveEllipticStmts.add newConstStmt(
        exported($curve & "_nonresidue_fp2"),
        curveDef.nonresidue_fp2
      )

      # Pairing
      # -----------------------------------------------
      curveEllipticStmts.add newConstStmt(
        exported($curve & "_embedding_degree"),
        newLit curveDef.embedding_degree
      )
      curveEllipticStmts.add newConstStmt(
        exported($curve & "_sexticTwist"),
        newLit curveDef.sexticTwist
      )

    if curveDef.eq_form == TwistedEdwards and
         curveDef.coef_A.kind != NoCoef and curveDef.coef_D.kind != NoCoef:
      curveEllipticStmts.add newConstStmt(
        exported($curve & "_coef_A"),
        curveDef.coef_A.getCoef(curve)
      )
      curveEllipticStmts.add newConstStmt(
        exported($curve & "_coef_D"),
        curveDef.coef_D.getCoef(curve)
      )

  # end for ---------------------------------------------------

  result = newStmtList()

  # const CurveFamily: array[Curve, CurveFamily] = ...
  result.add newConstStmt(
    exported("CurveFamilies"), MapCurveFamily
  )

  result.add curveEllipticStmts

macro setupCurves(): untyped =
  result = genCurveConstants(curvesDefinitions)

setupCurves()