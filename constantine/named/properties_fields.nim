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
  ../platforms/abstractions,
  ./config_fields_and_curves,
  ./deriv/derive_constants

export Algebra

# ############################################################
#
#                 Field types
#
# ############################################################

template matchingBigInt*(Name: static Algebra): untyped =
  ## BigInt type necessary to store the prime field Fp
  # Workaround: https://github.com/nim-lang/Nim/issues/16774
  # as we cannot do array accesses in type section.
  # Due to generic sandwiches, it must be exported.
  BigInt[CurveBitWidth[Name]]

template matchingOrderBigInt*(Name: static Algebra): untyped =
  ## BigInt type necessary to store the scalar field Fr
  # Workaround: https://github.com/nim-lang/Nim/issues/16774
  # as we cannot do array accesses in type section.
  # Due to generic sandwiches, it must be exported.
  BigInt[CurveOrderBitWidth[Name]]

type
  Fp*[Name: static Algebra] = object
    ## All operations on a Fp field are modulo P
    ## P being the prime modulus of the Curve C
    ## Internally, data is stored in Montgomery n-residue form
    ## with the magic constant chosen for convenient division (a power of 2 depending on P bitsize)
    # TODO, pseudo mersenne primes like 2²⁵⁵-19 have very fast modular reduction
    #       and don't need Montgomery representation
    mres*: matchingBigInt(Name)

  Fr*[Name: static Algebra] = object
    ## All operations on a field are modulo `r`
    ## `r` being the prime curve order or subgroup order
    ## Internally, data is stored in Montgomery n-residue form
    ## with the magic constant chosen for convenient division (a power of 2 depending on P bitsize)
    mres*: matchingOrderBigInt(Name)

  FF*[Name: static Algebra] = Fp[Name] or Fr[Name]

debug:
  # Those MUST not be enabled in production to avoiding the compiler auto-conversion and printing SecretWord by mistake, for example in crash logs.

  func `$`*[Name: static Algebra](a: Fp[Name]): string =
    result = "Fp[" & $Name
    result.add "]("
    result.add $a.mres
    result.add ')'

  func `$`*[Name: static Algebra](a: Fr[Name]): string =
    result = "Fr[" & $Name
    result.add "]("
    result.add $a.mres
    result.add ')'

# ############################################################
#
#                 Field properties
#
# ############################################################

{.experimental: "dynamicBindSym".}

macro baseFieldModulus*(Name: static Algebra): untyped =
  result = bindSym($Name & "_Modulus")

macro scalarFieldModulus*(Name: static Algebra): untyped =
  result = bindSym($Name & "_Order")

template getModulus*[Name: static Algebra](F: type FF[Name]): untyped =
  # We use a template to ensure the caller directly reads
  # the data from ROM, and reduce chances of Nim duplicating the constant.
  # Also `F is Fp` has issues in macros
  when F is Fp:
    baseFieldModulus(Name)
  else:
    scalarFieldModulus(Name)

template getBigInt*[Name: static Algebra](T: type FF[Name]): untyped =
  ## Get the underlying BigInt type.
  typeof(default(T).mres)

template isCrandallPrimeField*(F: type Fr): static bool = false

macro getCrandallPrimeSubterm*[Name: static Algebra](F: type Fp[Name]): static SecretWord =
  result = newcall(bindSym"SecretWord", bindSym($Name & "_fp_CrandallSubTerm"))

macro isCrandallPrimeField*[Name: static Algebra](F: type Fp[Name]): static bool =
  let rawCrandall = bindSym($Name & "_fp_isCrandall")
  let subTerm = bindSym($Name & "_fp_CrandallSubTerm")
  result = quote do:
    when `rawCrandall`:
      when log2_vartime(`subTerm`) < WordBitWidth:
        true
      else: false
    else: false

func bits*[Name: static Algebra](T: type FF[Name]): static int =
  T.getBigInt().bits

template getLimbs2x*(Name: static Algebra): typedesc =
  const N2 = wordsRequired(CurveBitWidth[Name]) * 2 # TODO upstream, not precomputing N2 breaks semcheck
  array[N2, SecretWord] # TODO upstream, using Limbs[N2] breaks semcheck

func has_P_3mod4_primeModulus*(Name: static Algebra): static bool =
  ## Returns true iff p ≡ 3 (mod 4)
  (BaseType(Name.baseFieldModulus().limbs[0]) and 3) == 3

func has_P_5mod8_primeModulus*(Name: static Algebra): static bool =
  ## Returns true iff p ≡ 5 (mod 8)
  (BaseType(Name.baseFieldModulus().limbs[0]) and 7) == 5

func has_P_9mod16_primeModulus*(Name: static Algebra): static bool =
  ## Returns true iff p ≡ 9 (mod 16)
  (BaseType(Name.baseFieldModulus().limbs[0]) and 15) == 9

func has_Psquare_9mod16_primePower*(Name: static Algebra): static bool =
  ## Returns true iff p² ≡ 9 (mod 16)
  ((BaseType(Name.baseFieldModulus().limbs[0]) * BaseType(Name.baseFieldModulus().limbs[0])) and 15) == 9

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
  # which prevents checking if a type FF[Name] = Fp[Name] or Fr[Name]
  # was instantiated with Fp or Fr.
  # getTypeInst only returns FF and sameType doesn't work.
  # so quote do + when checks.
  let T = getTypeInst(ff)
  T.expectKind(nnkBracketExpr)
  doAssert T[0].eqIdent("typedesc")

  let curve =
    if T[1].kind == nnkBracketExpr: # typedesc[Fp[BLS12_381]] as used internally
      # doAssert T[1][0].eqIdent"Fp" or T[1][0].eqIdent"Fr", "Found ident: '" & $T[1][0] & "' instead of 'Fp' or 'Fr'"
      T[1][1].expectKind(nnkIntLit) # static enum are ints in the VM
      $Algebra(T[1][1].intVal)
    else: # typedesc[bls12381_fp] alias as used for C exports
      let T1 = getTypeInst(T[1].getImpl()[2])
      if T1.kind != nnkBracketExpr or
         T1[1].kind != nnkIntLit:
        echo T.repr()
        echo T1.repr()
        echo getTypeInst(T1).treerepr()
        error "getTypeInst didn't return the full instantiation." &
          " Dealing with types in macros is hard, complain at https://github.com/nim-lang/RFCs/issues/44"
      $Algebra(T1[1].intVal)

  let curve_fp = bindSym(curve & "_Fp_" & property)
  let curve_fr = bindSym(curve & "_Fr_" & property)
  result = quote do:
    when `ff` is Fp:
      `curve_fp`
    elif `ff` is Fr:
      `curve_fr`
    else:
      {.error: "Unreachable, received type: " & $`ff`.}

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

macro getR3modP*(ff: type FF): untyped =
  ## Get the Montgomery "R^3 mod P" constant associated to a curve field modulus
  result = bindConstant(ff, "R3modP")

macro getNegInvModWord*(ff: type FF): untyped =
  ## Get the Montgomery "-1/P[0] mod 2^Wordbitwidth" constant associated to a curve field modulus
  result = bindConstant(ff, "NegInvModWord")

macro getMontyOne*(ff: type FF): untyped =
  ## Get one in Montgomery representation (i.e. R mod P)
  result = bindConstant(ff, "MontyOne")

macro getMontyPrimeMinus1*(ff: type FF): untyped =
  ## Get (P-1)
  result = bindConstant(ff, "MontyPrimeMinus1")

macro getPrimePlus1div2*(ff: type FF): untyped =
  ## Get (P+1) / 2 for an odd prime
  ## Warning ⚠️: Result in canonical domain (not Montgomery)
  result = bindConstant(ff, "PrimePlus1div2")

macro getPrimeMinus1*(ff: type FF): untyped =
  ## Get P-1
  ## Warning ⚠️: Result in canonical domain (not Montgomery)
  result = bindConstant(ff, "PrimeMinus1")

macro getPrimeMinus1div2*(ff: type FF): untyped =
  ## Get (P-1) / 2 for an odd prime
  ## Warning ⚠️: Result in canonical domain (not Montgomery)
  result = bindConstant(ff, "PrimeMinus1div2")

macro getPrimeMinus3div4_BE*(ff: type FF): untyped =
  ## Get (P-3) / 4 in big-endian serialized format
  result = bindConstant(ff, "PrimeMinus3div4_BE")

macro getPrimeMinus5div8_BE*(ff: type FF): untyped =
  ## Get (P-5) / 8 in big-endian serialized format
  result = bindConstant(ff, "PrimeMinus5div8_BE")

# ############################################################
#
#                Debug info printed at compile-time
#
# ############################################################

macro debugConsts(): untyped {.used.} =
  let curves = bindSym("Algebra")
  let E = curves.getImpl[2]

  result = newStmtList()
  for i in 1 ..< E.len:
    let curve = E[i]
    let curveName = $curve
    let modulus = bindSym(curveName & "_Modulus")
    let r2modp = bindSym(curveName & "_Fp_R2modP")
    let negInvModWord = bindSym(curveName & "_Fp_NegInvModWord")

    result.add quote do:
      echo "Algebra ", `curveName`,':'
      echo "  Field Modulus:                 ", `modulus`
      echo "  Montgomery R² (mod P):         ", `r2modp`
      echo "  Montgomery -1/P[0] (mod 2^", WordBitWidth, "): ", `negInvModWord`

  result.add quote do:
    echo "----------------------------------------------------------------------------"

# debug: # displayed with -d:CTT_DEBUG
#   debugConsts()
