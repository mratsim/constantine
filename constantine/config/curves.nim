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
  ./curves_declaration, ./curves_derived,
  ../arithmetic/bigints

export CurveFamily, Curve

# ############################################################
#
#                  Curve characteristics
#
# ############################################################

{.experimental: "dynamicBindSym".}

macro Mod*(C: static Curve): untyped =
  ## Get the Modulus associated to a curve
  result = bindSym($C & "_Modulus")

func getCurveBitSize*(C: static Curve): static int =
  ## Returns the number of bits taken by the curve modulus
  result = static(CurveBitWidth[C])

template matchingBigInt*(C: static Curve): untyped =
  BigInt[CurveBitWidth[C]]

func family*(C: static Curve): CurveFamily =
  result = static(CurveFamilies[C])

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

# Family specific
# -------------------------------------------------------
macro canUseFast_BN_Inversion*(C: static Curve): untyped =
  ## A BN curve can use the fast BN inversion if the parameter "u" is positive
  if CurveFamilies[C] != BarretoNaehrig:
    return newLit false
  return bindSym($C & "_BN_can_use_fast_inversion")

macro getBN_param_u_BE*(C: static Curve): untyped =
  ## Get the ``u`` parameter of a BN curve in canonical big-endian representation
  result = bindSym($C & "_BN_u_BE")

macro getBN_param_6u_minus_1_BE*(C: static Curve): untyped =
  ## Get the ``6u-1`` from the ``u`` parameter
  ## of a BN curve in canonical big-endian representation
  result = bindSym($C & "_BN_6u_minus_1_BE")

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
