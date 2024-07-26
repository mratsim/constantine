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
  ./config_fields_and_curves,
  ./deriv/parser_curves,
  ./properties_fields

export Algebra, CurveFamily, SexticTwist

# ############################################################
#
#                   Curve properties
#
# ############################################################

{.experimental: "dynamicBindSym".}

type FieldKind* = enum
  kBaseField
  kScalarField

template getBigInt*(Name: static Algebra, kind: static FieldKind): untyped =
  # Workaround:
  # in `ptr UncheckedArray[BigInt[EC.getScalarField().bits()]]
  # EC.getScalarField is not accepted by the compiler
  #
  # and `ptr UncheckedArray[BigInt[Fr[EC.F.Name].bits]]` gets undeclared field: 'Name'
  when kind == kBaseField:
    Name.baseFieldModulus().typeof()
  else:
    Name.scalarFieldModulus().typeof()

template getField*(Name: static Algebra, kind: static FieldKind): untyped =
  when kind == kBaseField:
    Fp[Name]
  else:
    Fr[Name]

template family*(Name: Algebra): CurveFamily =
  CurveFamilies[Name]

template isPairingFriendly*(Name: Algebra): bool =
  family(Name) in {BarretoNaehrig, BarretoLynnScott, BrezingWeng}

macro getEquationForm*(Name: static Algebra): untyped =
  ## Returns the equation form
  ## (ShortWeierstrass, Montgomery, Twisted Edwards, Weierstrass, ...)
  result = bindSym($Name & "_equation_form")

macro getCoefA*(Name: static Algebra): untyped =
  ## Returns the A coefficient of the curve
  ## The return type is polymorphic, it can be an int
  ## or a bigInt depending on the curve
  result = bindSym($Name & "_coef_A")

macro getCoefB*(Name: static Algebra): untyped =
  ## Returns the B coefficient of the curve
  ## The return type is polymorphic, it can be an int
  ## or a bigInt depending on the curve
  result = bindSym($Name & "_coef_B")

macro getCoefD*(Name: static Algebra): untyped =
  ## Returns the D coefficient of the curve
  ## The return type is polymorphic, it can be an int
  ## or a bigInt depending on the curve
  result = bindSym($Name & "_coef_D")

macro getNonResidueFp*(Name: static Algebra): untyped =
  ## Returns the tower extension (and twist) non-residue for 𝔽p
  ## Depending on the curve it might be:
  ## - not a square (quadratic non-residue to construct Fp2)
  ## - not a cube (cubic non-residue to construct Fp3)
  ## - neither a square or cube (sextic non-residue to construct Fp2, Fp3 or Fp6)
  result = bindSym($Name & "_nonresidue_fp")

macro getNonResidueFp2*(Name: static Algebra): untyped =
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
  result = bindSym($Name & "_nonresidue_fp2")

macro getEmbeddingDegree*(Name: static Algebra): untyped =
  ## Returns the prime embedding degree,
  ## i.e. the smallest k such that r|𝑝^𝑘−1
  ## equivalently 𝑝^𝑘 ≡ 1 (mod r)
  ## with r the curve order and p its field modulus
  result = bindSym($Name & "_embedding_degree")

macro getSexticTwist*(Name: static Algebra): untyped =
  ## Returns if D-Twist or M-Twist
  result = bindSym($Name & "_sexticTwist")

macro getGT*(Name: static Algebra): untyped =
  ## Returns the GT extension field

  template gt(embdegree: static int): untyped =
    `Fp embdegree`

  result = quote do:
    `gt`(getEmbeddingDegree(Algebra(`Name`)))[Algebra(`Name`)]
