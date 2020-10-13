# Constantine
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
  ./type_bigint, ./common,
  ./curves_declaration, ./curves_derived, ./curves_parser

export CurveFamily, Curve, SexticTwist

# ############################################################
#
#                 Field properties
#
# ############################################################

{.experimental: "dynamicBindSym".}

macro Mod*(C: static Curve): untyped =
  ## Get the Modulus associated to a curve
  result = bindSym($C & "_Modulus")

template getCurveBitwidth*(C: Curve): int =
  ## Returns the number of bits taken by the curve modulus
  CurveBitWidth[C]

template matchingBigInt*(C: static Curve): untyped =
  BigInt[CurveBitWidth[C]]

template family*(C: Curve): CurveFamily =
  CurveFamilies[C]

template matchingLimbs2x*(C: Curve): untyped =
  const N2 = wordsRequired(getCurveBitwidth(C)) * 2 # TODO upstream, not precomputing N2 breaks semcheck
  array[N2, SecretWord] # TODO upstream, using Limbs[N2] breaks semcheck

# ############################################################
#
#                   Curve properties
#
# ############################################################

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

macro get_QNR_Fp*(C: static Curve): untyped =
  ## Returns the tower extension quadratic non-residue in 𝔽p
  ## i.e. a number that is not a square in 𝔽p
  result = bindSym($C & "_nonresidue_quad_fp")

macro get_CNR_Fp2*(C: static Curve): untyped =
  ## Returns the tower extension cubic non-residue 𝔽p²
  ## i.e. a number that is not a cube in 𝔽p²
  ##
  ## The return value is a tuple (a, b)
  ## that corresponds to the number a + b𝑗
  ## with 𝑗 choosen for 𝑗² - QNR_Fp == 0
  ## i.e. if -1 is chosen as a quadratic non-residue 𝑗 = √-1
  ##      if -2 is chosen as a quadratic non-residue 𝑗 = √-2
  result = bindSym($C & "_nonresidue_cube_fp2")

macro getEmbeddingDegree*(C: static Curve): untyped =
  ## Returns the prime embedding degree,
  ## i.e. the smallest k such that r|𝑝^𝑘−1
  ## equivalently 𝑝^𝑘 ≡ 1 (mod r)
  ## with r the curve order and p its field modulus
  result = bindSym($C & "_embedding_degree")

macro getSexticTwist*(C: static Curve): untyped =
  ## Returns if D-Twist or M-Twist
  result = bindSym($C & "_sexticTwist")

macro get_SNR_Fp2*(C: static Curve): untyped =
  ## Returns the sextic non-residue in 𝔽p²
  ## choosen to build the twisted curve E'(𝔽p²)
  ## i.e. a number µ so that x⁶ - µ is irreducible
  result = bindSym($C & "_sexticNonResidue_fp2")

# ############################################################
#
#        Access precomputed derived constants in ROM
#
# ############################################################

genDerivedConstants()

macro canUseNoCarryMontyMul*(C: static Curve): untyped =
  ## Returns true if the Modulus is compatible with a fast
  ## Montgomery multiplication that avoids many carries
  result = bindSym($C & "_CanUseNoCarryMontyMul")

macro canUseNoCarryMontySquare*(C: static Curve): untyped =
  ## Returns true if the Modulus is compatible with a fast
  ## Montgomery squaring that avoids many carries
  result = bindSym($C & "_CanUseNoCarryMontySquare")

macro getR2modP*(C: static Curve): untyped =
  ## Get the Montgomery "R^2 mod P" constant associated to a curve field modulus
  result = bindSym($C & "_R2modP")

macro getNegInvModWord*(C: static Curve): untyped =
  ## Get the Montgomery "-1/P[0] mod 2^Wordbitwidth" constant associated to a curve field modulus
  result = bindSym($C & "_NegInvModWord")

macro getMontyOne*(C: static Curve): untyped =
  ## Get one in Montgomery representation (i.e. R mod P)
  result = bindSym($C & "_MontyOne")

macro getMontyPrimeMinus1*(C: static Curve): untyped =
  ## Get (P+1) / 2 for an odd prime
  result = bindSym($C & "_MontyPrimeMinus1")

macro getInvModExponent*(C: static Curve): untyped =
  ## Get modular inversion exponent (Modulus-2 in canonical representation)
  result = bindSym($C & "_InvModExponent")

macro getPrimePlus1div2*(C: static Curve): untyped =
  ## Get (P+1) / 2 for an odd prime
  ## Warning ⚠️: Result in canonical domain (not Montgomery)
  result = bindSym($C & "_PrimePlus1div2")

macro getPrimeMinus1div2_BE*(C: static Curve): untyped =
  ## Get (P-1) / 2 in big-endian serialized format
  result = bindSym($C & "_PrimeMinus1div2_BE")

macro getPrimeMinus3div4_BE*(C: static Curve): untyped =
  ## Get (P-3) / 2 in big-endian serialized format
  result = bindSym($C & "_PrimeMinus3div4_BE")

macro getPrimePlus1div4_BE*(C: static Curve): untyped =
  ## Get (P+1) / 4 for an odd prime in big-endian serialized format
  result = bindSym($C & "_PrimePlus1div4_BE")

# ############################################################
#
#                Debug info printed at compile-time
#
# ############################################################

macro debugConsts(): untyped {.used.} =
  let curves = bindSym("Curve")
  let E = curves.getImpl[2]

  result = newStmtList()
  for i in 1 ..< E.len:
    let curve = E[i]
    let curveName = $curve
    let modulus = bindSym(curveName & "_Modulus")
    let r2modp = bindSym(curveName & "_R2modP")
    let negInvModWord = bindSym(curveName & "_NegInvModWord")

    result.add quote do:
      echo "Curve ", `curveName`,':'
      echo "  Field Modulus:                 ", `modulus`
      echo "  Montgomery R² (mod P):         ", `r2modp`
      echo "  Montgomery -1/P[0] (mod 2^", WordBitWidth, "): ", `negInvModWord`

  result.add quote do:
    echo "----------------------------------------------------------------------------"

# debug: # displayed with -d:debugConstantine
#   debugConsts()
