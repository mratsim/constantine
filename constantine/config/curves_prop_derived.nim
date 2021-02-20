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

proc bindConstant(ff: NimNode, property: string): NimNode =
  # Need to workaround https://github.com/nim-lang/Nim/issues/14021
  # which prevents checking if a type FF[C] = Fp[C] or Fr[C]
  # was instantiated with Fp or Fr.
  # getTypeInst only returns FF and sameType doesn't work.
  # so quote do + when checks.
  let T = getTypeInst(ff)
  T.expectKind(nnkBracketExpr)
  doAssert T[0].eqIdent("typedesc")

  if T[1].kind == nnkBracketExpr: # typedesc[Fp[BLS12_381]]
    # doAssert T[1][0].eqIdent"Fp" or T[1][0].eqIdent"Fr", "Found ident: '" & $T[1][0] & "' instead of 'Fp' or 'Fr'"

    T[1][1].expectKind(nnkIntLit) # static enum are ints in the VM

    let curve = $Curve(T[1][1].intVal)
    let curve_fp = bindSym(curve & "_Fp_" & property)
    let curve_fr = bindSym(curve & "_Fr_" & property)
    result = quote do:
      when `ff` is Fp:
        `curve_fp`
      elif `ff` is Fr:
        `curve_fr`
      else:
        {.error: "Unreachable, received type: " & $`ff`.}

  else:
    echo T.repr()
    echo getTypeInst(T[1]).treerepr
    error "getTypeInst didn't return the full instantiation." &
      " Dealing with types in macros is hard, complain at https://github.com/nim-lang/RFCs/issues/44"

template fieldMod*(Field: type FF): auto =
  when Field is Fp:
    Field.C.Mod
  else:
    Field.C.getCurveOrder()

macro getSpareBits*(ff: type FF): untyped =
  ## Returns the number of extra bits
  ## in the modulus M representation.
  ##
  ## This is used for no-carry operations
  ## or lazily reduced operations by allowing
  ## output in range:
  ## - [0, 2p) if 1 bit is available
  ## - [0, 4p) if 2 bits are available
  ## - [0, 8p) if 3 bits are available
  ## - ...
  result = bindConstant(ff, "SpareBits")

macro getR2modP*(ff: type FF): untyped =
  ## Get the Montgomery "R^2 mod P" constant associated to a curve field modulus
  result = bindConstant(ff, "R2modP")

macro getNegInvModWord*(ff: type FF): untyped =
  ## Get the Montgomery "-1/P[0] mod 2^Wordbitwidth" constant associated to a curve field modulus
  result = bindConstant(ff, "NegInvModWord")

macro getMontyOne*(ff: type FF): untyped =
  ## Get one in Montgomery representation (i.e. R mod P)
  result = bindConstant(ff, "MontyOne")

macro getMontyPrimeMinus1*(ff: type FF): untyped =
  ## Get (P+1) / 2 for an odd prime
  result = bindConstant(ff, "MontyPrimeMinus1")

macro getInvModExponent*(ff: type FF): untyped =
  ## Get modular inversion exponent (Modulus-2 in canonical representation)
  result = bindConstant(ff, "InvModExponent")

macro getPrimePlus1div2*(ff: type FF): untyped =
  ## Get (P+1) / 2 for an odd prime
  ## Warning ⚠️: Result in canonical domain (not Montgomery)
  result = bindConstant(ff, "PrimePlus1div2")

macro getPrimeMinus1div2_BE*(ff: type FF): untyped =
  ## Get (P-1) / 2 in big-endian serialized format
  result = bindConstant(ff, "PrimeMinus1div2_BE")

macro getPrimeMinus3div4_BE*(ff: type FF): untyped =
  ## Get (P-3) / 2 in big-endian serialized format
  result = bindConstant(ff, "PrimeMinus3div4_BE")

macro getPrimePlus1div4_BE*(ff: type FF): untyped =
  ## Get (P+1) / 4 for an odd prime in big-endian serialized format
  result = bindConstant(ff, "PrimePlus1div4_BE")

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
