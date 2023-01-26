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
  ./curves_declaration, ./curves_parser_curve

export CurveFamily, Curve, SexticTwist

# ############################################################
#
#                   Curve properties
#
# ############################################################

{.experimental: "dynamicBindSym".}

template getCurveBitwidth*(C: Curve): int =
  ## Returns the number of bits taken by the curve modulus
  CurveBitWidth[C]

macro getCurveOrder*(C: static Curve): untyped =
  ## Get the curve order `r`
  ## i.e. the number of points on the elliptic curve
  result = bindSym($C & "_Order")

macro getCurveOrderBitwidth*(C: static Curve): untyped =
  ## Get the curve order `r`
  ## i.e. the number of points on the elliptic curve
  result = nnkDotExpr.newTree(
    getAST(getCurveOrder(C)),
    ident"bits"
  )

template family*(C: Curve): CurveFamily =
  CurveFamilies[C]

macro getEquationForm*(C: static Curve): untyped =
  ## Returns the equation form
  ## (ShortWeierstrass, Montgomery, Twisted Edwards, Weierstrass, ...)
  result = bindSym($C & "_equation_form")

macro getCoefA*(C: static Curve): untyped =
  ## Returns the A coefficient of the curve
  ## The return type is polymorphic, it can be an int
  ## or a bigInt depending on the curve
  result = bindSym($C & "_coef_A")

macro getCoefB*(C: static Curve): untyped =
  ## Returns the B coefficient of the curve
  ## The return type is polymorphic, it can be an int
  ## or a bigInt depending on the curve
  result = bindSym($C & "_coef_B")

macro getCoefD*(C: static Curve): untyped =
  ## Returns the D coefficient of the curve
  ## The return type is polymorphic, it can be an int
  ## or a bigInt depending on the curve
  result = bindSym($C & "_coef_D")

macro getNonResidueFp*(C: static Curve): untyped =
  ## Returns the tower extension (and twist) non-residue for 𝔽p
  ## Depending on the curve it might be:
  ## - not a square (quadratic non-residue to construct Fp2)
  ## - not a cube (cubic non-residue to construct Fp3)
  ## - neither a square or cube (sextic non-residue to construct Fp2, Fp3 or Fp6)
  result = bindSym($C & "_nonresidue_fp")

macro getNonResidueFp2*(C: static Curve): untyped =
  ## Returns the tower extension (and twist) non-residue for 𝔽p²
  ## Depending on the curve it might be:
  ## - not a square (quadratic non-residue to construct Fp4)
  ## - not a cube (cubic non-residue to construct Fp6)
  ## - neither a square or cube (sextic non-residue to construct Fp4, Fp6 or Fp12)
  ##
  ## The return value is a tuple (a, b)
  ## that corresponds to the number a + b𝑗
  ## with 𝑗 choosen for 𝑗² - QNR_Fp == 0
  ## i.e. if -1 is chosen as a quadratic non-residue 𝑗 = √-1
  ##      if -2 is chosen as a quadratic non-residue 𝑗 = √-2
  result = bindSym($C & "_nonresidue_fp2")

macro getEmbeddingDegree*(C: static Curve): untyped =
  ## Returns the prime embedding degree,
  ## i.e. the smallest k such that r|𝑝^𝑘−1
  ## equivalently 𝑝^𝑘 ≡ 1 (mod r)
  ## with r the curve order and p its field modulus
  result = bindSym($C & "_embedding_degree")

macro getSexticTwist*(C: static Curve): untyped =
  ## Returns if D-Twist or M-Twist
  result = bindSym($C & "_sexticTwist")

macro getGT*(C: static Curve): untyped =
  ## Returns the GT extension field

  template gt(embdegree: static int): untyped =
    `Fp embdegree`

  result = quote do:
    `gt`(getEmbeddingDegree(Curve(`C`)))[Curve(`C`)]
