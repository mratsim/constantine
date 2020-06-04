# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  # Standard library
  std/[macros, strutils],
  # Internal
  ../io/io_bigints, ../arithmetic/[bigints, precomputed]

# Parsing is done in 2 steps:
# 1. All declared parameters are collected in a {.compileTime.} seq[CurveParams]
# 2. Those parameters are assigned to a constant
#    If needed a macro is defined to retrieve those in a generic way.
#
# Using a const indirection rather than directly accessing the {.compileTime.} object ensures 2 things:
# - properly cross the compile-time -> runtime boundary
# - avoid inlining large const arrays at the call site
#   for example when using the `r2modP` constant in multiple overloads in the same module
#   TODO: check that those constants use extern const to avoid duplication across modules

type
  CurveFamily* = enum
    NoFamily
    BarretoNaehrig   # BN curve
    BarretoLynnScott # BLS curve

  CurveCoefKind* = enum
    ## Small coefficients fit in an int64
    ## Large ones require a bigint
    ## Note that some seemingly large coefficients might be small
    ## when represented as a negative modular integer
    ##
    ## NoCoef is used when the curve is not defined (i.e. we are only interest in field arithmetic)
    ## use `Small` to set a coef to ``0``
    NoCoef
    Small
    Large

  CurveCoef* = object
    case kind: CurveCoefKind
    of NoCoef: discard
    of Small: coef: int
    of Large: coefHex: string

  CurveEquationForm* = enum
    ShortWeierstrass

  SexticTwist* = enum
    ## The sextic twist type of the current elliptic curve
    ##
    ## Assuming a standard curve `E` over the prime field `𝔽p`
    ## denoted `E(𝔽p)` in Short Weierstrass form
    ##   y² = x³ + Ax + B
    ##
    ## If E(𝔽p^k), the elliptic curve defined over the extension field
    ## of degree k, the embedding degree, admits an isomorphism
    ## to a curve E'(Fp^(k/d)), we call E' a twisted curve.
    ##
    ## For pairing they have the following equation
    ##   y² = x³ + Ax/µ² + B/µ³ for a D-Twist (Divisor)
    ## or
    ##   y² = x³ + µ²Ax + µ³B for a M-Twist (Multiplicand)
    ## with the polynomial x^k - µ being irreducible.
    ##
    ## i.e. if d == 2, E' is a quadratic twist and µ is a quadratic non-residue
    ## if d == 4, E' is a quartic twist
    ## if d == 6, E' is a sextic twist
    ##
    ## References:
    ## - Efficient Pairings on Twisted Elliptic Curve
    ##   Yasuyuki Nogami, Masataka Akane, Yumi Sakemi and Yoshitaka Morikawa, 2010
    ##   https://www.researchgate.net/publication/221908359_Efficient_Pairings_on_Twisted_Elliptic_Curve
    ##
    ## - A note on twists for pairing friendly curves\
    ##   Michael Scott, 2009\
    ##   http://indigo.ie/~mscott/twists.pdf
    NotTwisted
    D_Twist
    M_Twist

  CurveParams = object
    ## All the curve parameters that may be defined
    # Note: we don't use case object here, the transition is annoying
    #       and would force use to scan all "kind" field (eq_form, family, ...)
    #       before instantiating the object.
    name: NimNode

    # Field parameters
    bitWidth: NimNode # nnkIntLit
    modulus: NimNode  # nnkStrLit (hex)

    # Towering
    nonresidue_quad_fp: NimNode # nnkIntLit
    nonresidue_cube_fp2: NimNode # nnkPar(nnkIntLit, nnkIntLit)

    # Curve parameters
    eq_form: CurveEquationForm
    coef_A: CurveCoef
    coef_B: CurveCoef
    order: NimNode # nnkStrLit (hex)
    orderBitwidth: NimNode # nnkIntLit

    sexticTwist: SexticTwist
    sexticNonResidue_fp2: NimNode # nnkPar(nnkIntLit, nnkIntLit)

    family: CurveFamily
    # BN family
    # ------------------------
    bn_u_bitwidth: NimNode # nnkIntLit
    bn_u: NimNode          # nnkStrLit (hex)

var curvesDefinitions {.compileTime.}: seq[CurveParams]

proc parseCurveDecls(defs: var seq[CurveParams], curves: NimNode) =
  ## Parse the curve declarations and store them in the curve definitions
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

  for curveDesc in curves:
    # Checks
    # -----------------------------------------------
    curveDesc.expectKind(nnkCommand)
    doAssert curveDesc[0].eqIdent"curve"

    let curve = curveDesc[1]
    let curveParams = curveDesc[2]
    curve.expectKind(nnkIdent)          # Curve name
    curveParams.expectKind(nnkStmtList) # Curve parameters

    # Skip test curves if not testing
    # -----------------------------------------------

    var offset = 0
    var testCurve = false
    if curveParams[0][0].eqident"testingCurve":
      offset = 1
      testCurve = curveParams[0][1].boolVal

    if testCurve and defined(testingCurves):
      continue

    # Parameters
    # -----------------------------------------------
    var params = CurveParams(name: curve)
    for i in offset ..< curveParams.len:
      let sectionId = curveParams[i][0]
      curveParams[i][1].expectKind(nnkStmtList)
      let sectionVal = curveParams[i][1][0]

      if sectionId.eqIdent"bitwidth":
        params.bitWidth = sectionVal
      elif sectionId.eqident"modulus":
        params.modulus = sectionVal
      elif sectionId.eqIdent"family":
        params.family = parseEnum[CurveFamily]($sectionVal)
      elif sectionId.eqIdent"bn_u_bitwidth":
        params.bn_u_bitwidth = sectionVal
      elif sectionId.eqIdent"bn_u":
        params.bn_u = sectionVal
      elif sectionId.eqIdent"eq_form":
        params.eq_form = parseEnum[CurveEquationForm]($sectionVal)
      elif sectionId.eqIdent"coef_a":
        if sectionVal.kind == nnkIntLit:
          params.coef_A = CurveCoef(kind: Small, coef: sectionVal.intVal.int)
        else:
          params.coef_A = CurveCoef(kind: Large, coefHex: sectionVal.strVal)
      elif sectionId.eqIdent"coef_b":
        if sectionVal.kind == nnkIntLit:
          params.coef_B = CurveCoef(kind: Small, coef: sectionVal.intVal.int)
        else:
          params.coef_B = CurveCoef(kind: Large, coefHex: sectionVal.strVal)
      elif sectionId.eqIdent"order":
        params.order = sectionVal
      elif sectionId.eqIdent"orderBitwidth":
        params.orderBitwidth = sectionVal
      elif sectionId.eqIdent"cofactor":
        discard "TODO"
      elif sectionId.eqIdent"nonresidue_quad_fp":
        params.nonresidue_quad_fp = sectionVal
      elif sectionId.eqIdent"nonresidue_cube_fp2":
        params.nonresidue_cube_fp2 = sectionVal
      elif sectionId.eqIdent"sexticTwist":
        params.sexticTwist = parseEnum[SexticTwist]($sectionVal)
      elif sectionId.eqIdent"sexticNonResidue_fp2":
        params.sexticNonResidue_fp2 = sectionVal
      else:
        error "Invalid section: \n", curveParams[i].toStrLit()

    defs.add params

proc exported(id: string): NimNode =
  nnkPostfix.newTree(
    ident"*",
    ident(id)
  )

template getCoef(c: CurveCoef, width: NimNode): untyped {.dirty.}=
  case c.kind
  of NoCoef:
    error "Unreachable"
    nnkDiscardStmt.newTree(newLit "Dummy")
  of Small:
    newLit c.coef
  of Large:
    newCall(
      bindSym"fromHex",
      nnkBracketExpr.newTree(bindSym"BigInt", width),
      newLit c.coefHex
    )

proc genMainConstants(defs: var seq[CurveParams]): NimNode =
  ## Generate curves and fields main constants

  var Curves: seq[NimNode]
  var MapCurveBitWidth = nnkBracket.newTree()
  var MapCurveFamily = nnkBracket.newTree()
  var curveModStmts = newStmtList()
  var curveEllipticStmts = newStmtList()
  var curveExtraStmts = newStmtList()

  for curveDef in defs:
    curveDef.name.expectKind(nnkIdent)
    curveDef.bitWidth.expectKind(nnkIntLit)
    curveDef.modulus.expectKind(nnkStrLit)

    let curve = curveDef.name
    let bitWidth = curveDef.bitWidth
    let modulus = curveDef.modulus
    let family = curveDef.family

    Curves.add curve
    # "BN254_Snarks: 254" array construction expression
    MapCurveBitWidth.add nnkExprColonExpr.newTree(
      curve, bitWidth
    )

    # const BN254_Snarks_Modulus = fromHex(BigInt[254], "0x30644e72e131a029b85045b68181585d97816a916871ca8d3c208c16d87cfd47")
    curveModStmts.add newConstStmt(
      exported($curve & "_Modulus"),
      newCall(
        bindSym"fromHex",
        nnkBracketExpr.newTree(bindSym"BigInt", bitWidth),
        modulus
      )
    )

    MapCurveFamily.add nnkExprColonExpr.newTree(
        curve, newLit(family)
    )
    # Curve equation
    # -----------------------------------------------
    curveEllipticStmts.add newConstStmt(
      exported($curve & "_equation_form"),
      newLit curveDef.eq_form
    )
    if not curveDef.order.isNil:
      curveDef.orderBitwidth.expectKind(nnkIntLit)
      curveEllipticStmts.add newConstStmt(
        exported($curve & "_Order"),
        newCall(
          bindSym"fromHex",
          nnkBracketExpr.newTree(bindSym"BigInt", curveDef.orderBitwidth),
          curveDef.order
        )
      )
    if curveDef.coef_A.kind != NoCoef and curveDef.coef_B.kind != NoCoef:
      curveEllipticStmts.add newConstStmt(
        exported($curve & "_coef_A"),
        curveDef.coef_A.getCoef(bitWidth)
      )
      curveEllipticStmts.add newConstStmt(
        exported($curve & "_coef_B"),
        curveDef.coef_B.getCoef(bitWidth)
      )
      curveEllipticStmts.add newConstStmt(
        exported($curve & "_nonresidue_quad_fp"),
        curveDef.nonresidue_quad_fp
      )
      curveEllipticStmts.add newConstStmt(
        exported($curve & "_nonresidue_cube_fp2"),
        curveDef.nonresidue_cube_fp2
      )
      curveEllipticStmts.add newConstStmt(
        exported($curve & "_sexticTwist"),
        newLit curveDef.sexticTwist
      )
      curveEllipticStmts.add newConstStmt(
        exported($curve & "_sexticNonResidue_fp2"),
        curveDef.sexticNonResidue_fp2
      )

    # BN curves
    # -----------------------------------------------
    if family == BarretoNaehrig:
      if not curveDef.bn_u_bitwidth.isNil and
         not curveDef.bn_u.isNil and
         ($curveDef.bn_u)[0] != '-': # The parameter must be positive
        curveExtraStmts.add newConstStmt(
          exported($curve & "_BN_can_use_addchain_inversion"),
          newLit true
        )
      else:
        curveExtraStmts.add newConstStmt(
          exported($curve & "_BN_can_use_addchain_inversion"),
          newLit false
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
    exported("CurveBitWidth"), MapCurveBitWidth
  )
  # const CurveFamily: array[Curve, CurveFamily] = ...
  result.add newConstStmt(
    exported("CurveFamilies"), MapCurveFamily
  )

  result.add curveModStmts
  result.add curveEllipticStmts
  result.add curveExtraStmts

  # echo result.toStrLit()

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
  ## TODO: Ensure that
  ##       1. the modulus is not inlined at runtime to avoid codesize explosion.
  ##       2. is not duplicated across compilation modules.

  curves.expectKind(nnkStmtList)
  curvesDefinitions.parseCurveDecls(curves)
  result = curvesDefinitions.genMainConstants()
