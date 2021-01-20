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
  ./type_bigint, ./type_ff, ./common,
  ./curves_declaration, ./curves_derived

# ############################################################
#
#        Access precomputed derived constants in ROM
#
# ############################################################
{.experimental: "dynamicBindSym".}

genDerivedConstants(kModulus)
genDerivedConstants(kOrder)

proc prefix(ff: NimNode): string =
  # Accepts types in the form Fp[BLS12_381] or Fr[BLS12_381]
  let T = getTypeInst(ff)
  T.expectKind(nnkBracketExpr)
  doAssert T[0].eqIdent("typedesc")


  if T[1].kind == nnkBracketExpr: # typedesc[Fp[BLS12_381]]
    doAssert T[1][0].eqIdent"Fp" or T[1][0].eqIdent"Fr"
    T[1][1].expectKind(nnkIntLit) # static enum are ints in the VM

    result = $Curve(T[1][1].intVal)
    result &= "_" & $T[1][0] & '_'
  else:
    echo T.repr()
    echo getTypeInst(T[1]).treerepr
    error "getTypeInst didn't return the full instantiation." &
      " Dealing with types in macros is hard, complain at https://github.com/nim-lang/RFCs/issues/44"

macro canUseNoCarryMontyMul*(ff: type FF): untyped =
  ## Returns true if the Modulus is compatible with a fast
  ## Montgomery multiplication that avoids many carries
  result = bindSym(prefix(ff) & "CanUseNoCarryMontyMul")

macro canUseNoCarryMontySquare*(ff: type FF): untyped =
  ## Returns true if the Modulus is compatible with a fast
  ## Montgomery squaring that avoids many carries
  result = bindSym(prefix(ff) & "CanUseNoCarryMontySquare")

macro getR2modP*(ff: type FF): untyped =
  ## Get the Montgomery "R^2 mod P" constant associated to a curve field modulus
  result = bindSym(prefix(ff) & "R2modP")

macro getNegInvModWord*(ff: type FF): untyped =
  ## Get the Montgomery "-1/P[0] mod 2^Wordbitwidth" constant associated to a curve field modulus
  result = bindSym(prefix(ff) & "NegInvModWord")

macro getMontyOne*(ff: type FF): untyped =
  ## Get one in Montgomery representation (i.e. R mod P)
  result = bindSym(prefix(ff) & "MontyOne")

macro getMontyPrimeMinus1*(ff: type FF): untyped =
  ## Get (P+1) / 2 for an odd prime
  result = bindSym(prefix(ff) & "MontyPrimeMinus1")

macro getInvModExponent*(ff: type FF): untyped =
  ## Get modular inversion exponent (Modulus-2 in canonical representation)
  result = bindSym(prefix(ff) & "InvModExponent")

macro getPrimePlus1div2*(ff: type FF): untyped =
  ## Get (P+1) / 2 for an odd prime
  ## Warning ⚠️: Result in canonical domain (not Montgomery)
  result = bindSym(prefix(ff) & "PrimePlus1div2")

macro getPrimeMinus1div2_BE*(ff: type FF): untyped =
  ## Get (P-1) / 2 in big-endian serialized format
  result = bindSym(prefix(ff) & "PrimeMinus1div2_BE")

macro getPrimeMinus3div4_BE*(ff: type FF): untyped =
  ## Get (P-3) / 2 in big-endian serialized format
  result = bindSym(prefix(ff) & "PrimeMinus3div4_BE")

macro getPrimePlus1div4_BE*(ff: type FF): untyped =
  ## Get (P+1) / 4 for an odd prime in big-endian serialized format
  result = bindSym(prefix(ff) & "PrimePlus1div4_BE")

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
    let modulus = bindSym(curveName & "_Fp_Modulus")
    let r2modp = bindSym(curveName & "_Fp_R2modP")
    let negInvModWord = bindSym(curveName & "_Fp_NegInvModWord")

    result.add quote do:
      echo "Curve ", `curveName`,':'
      echo "  Field Modulus:                 ", `modulus`
      echo "  Montgomery R² (mod P):         ", `r2modp`
      echo "  Montgomery -1/P[0] (mod 2^", WordBitWidth, "): ", `negInvModWord`

  result.add quote do:
    echo "----------------------------------------------------------------------------"

# debug: # displayed with -d:debugConstantine
#   debugConsts()
