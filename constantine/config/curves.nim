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
  ./curves_parser, ./common,
  ../arithmetic/[precomputed, bigints]


# ############################################################
#
#           Configuration of finite fields
#
# ############################################################

# Curves & their corresponding finite fields are preconfigured in this file

# Note, in the past the convention was to name a curve by its conjectured security level.
# as this might change with advances in research, the new convention is
# to name curves according to the length of the prime bit length.
# i.e. the BN254 was previously named BN128.

# Curves security level were significantly impacted by
# advances in the Tower Number Field Sieve.
# in particular BN254 curve security dropped
# from estimated 128-bit to estimated 100-bit
# Barbulescu, R. and S. Duquesne, "Updating Key Size Estimations for Pairings",
# Journal of Cryptology, DOI 10.1007/s00145-018-9280-5, January 2018.

# Generates public:
# - type Curve* = enum
# - proc Mod*(curve: static Curve): auto
#   which returns the field modulus of the curve
when not defined(testingCurves):
  declareCurves:
    # Barreto-Naehrig curve, pairing-friendly, Prime 254 bit, ~100-bit security
    # https://eprint.iacr.org/2013/879.pdf
    # Usage: Zero-Knowledge Proofs / zkSNARKs in ZCash and Ethereum 1
    #        https://eips.ethereum.org/EIPS/eip-196
    curve BN254:
      bitsize: 254
      modulus: "0x30644e72e131a029b85045b68181585d97816a916871ca8d3c208c16d87cfd47"
      # Equation: Y^2 = X^3 + 3
    curve BLS12_381:
      bitsize: 381
      modulus: "0x1a0111ea397fe69a4b1ba7b6434bacd764774b84f38512bf6730d2a0f6b0f6241eabfffeb153ffffb9feffffffffaaab"
      # Equation: y^2 = x^3 + 4
    curve P256: # secp256r1 / NIST P-256
      bitsize: 256
      modulus: "0xffffffff00000001000000000000000000000000ffffffffffffffffffffffff"
    curve Secp256k1: # Bitcoin curve
      bitsize: 256
      modulus: "0xFFFFFFFF FFFFFFFF FFFFFFFF FFFFFFFF FFFFFFFF FFFFFFFF FFFFFFFE FFFFFC2F"
else:
  # Fake curve for testing field arithmetic
  declareCurves:
    curve Fake101:
      bitsize: 7
      modulus: "0x65" # 101 in hex
    curve Mersenne61:
      bitsize: 61
      modulus: "0x1fffffffffffffff" # 2^61 - 1
    curve Mersenne127:
      bitsize: 127
      modulus: "0x7fffffffffffffffffffffffffffffff" # 2^127 - 1
    curve P256: # secp256r1 / NIST P-256
      bitsize: 256
      modulus: "0xffffffff00000001000000000000000000000000ffffffffffffffffffffffff"
    curve BLS12_381:
      bitsize: 381
      modulus: "0x1a0111ea397fe69a4b1ba7b6434bacd764774b84f38512bf6730d2a0f6b0f6241eabfffeb153ffffb9feffffffffaaab"

# ############################################################
#
#              Curve Modulus Accessor
#
# ############################################################

{.experimental: "dynamicBindSym".}

macro Mod*(C: static Curve): untyped =
  ## Get the Modulus associated to a curve
  result = bindSym($C & "_Modulus")

# ############################################################
#
#  Autogeneration of precomputed Montgomery constants in ROM
#
# ############################################################

macro genMontyMagics(T: typed): untyped =
  ## Store
  ## - the Montgomery magic constant "R^2 mod N" in ROM
  ##   For each curve under the private symbol "MyCurve_R2modP"
  ## - the Montgomery magic constant -1/P mod 2^WordBitSize
  ##   For each curve under the private symbol "MyCurve_NegInvModWord
  T.getImpl.expectKind(nnkTypeDef)
  T.getImpl[2].expectKind(nnkEnumTy)

  result = newStmtList()

  let E = T.getImpl[2]
  for i in 1 ..< E.len:
    let curve = E[i]
    # const MyCurve_R2modP = r2mod(MyCurve_Modulus)
    result.add newConstStmt(
      ident($curve & "_R2modP"), newCall(
        bindSym"r2mod",
        nnkDotExpr.newTree(
          bindSym($curve & "_Modulus"),
          ident"mres"
        )
      )
    )
    # const MyCurve_NegInvModWord = negInvModWord(MyCurve_Modulus)
    result.add newConstStmt(
      ident($curve & "_NegInvModWord"), newCall(
        bindSym"negInvModWord",
        nnkDotExpr.newTree(
          bindSym($curve & "_Modulus"),
          ident"mres"
        )
      )
    )
    # const MyCurve_montyOne = montyOne(MyCurve_Modulus)
    result.add newConstStmt(
      ident($curve & "_MontyOne"), newCall(
        bindSym"montyOne",
        nnkDotExpr.newTree(
          bindSym($curve & "_Modulus"),
          ident"mres"
        )
      )
    )
    # const MyCurve_InvModExponent = primeMinus2_BE(MyCurve_Modulus)
    result.add newConstStmt(
      ident($curve & "_InvModExponent"), newCall(
        bindSym"primeMinus2_BE",
        nnkDotExpr.newTree(
          bindSym($curve & "_Modulus"),
          ident"mres"
        )
      )
    )

  # echo result.toStrLit

genMontyMagics(Curve)

macro getR2modP*(C: static Curve): untyped =
  ## Get the Montgomery "R^2 mod P" constant associated to a curve field modulus
  result = bindSym($C & "_R2modP")

macro getNegInvModWord*(C: static Curve): untyped =
  ## Get the Montgomery "-1/P[0] mod 2^WordBitSize" constant associated to a curve field modulus
  result = bindSym($C & "_NegInvModWord")

macro getMontyOne*(C: static Curve): untyped =
  ## Get one in Montgomery representation (i.e. R mod P)
  result = bindSym($C & "_MontyOne")

macro getInvModExponent*(C: static Curve): untyped =
  ## Get modular inversion exponent (Modulus-2 in canonical representation)
  result = bindSym($C & "_InvModExponent")

# ############################################################
#
#                Debug info printed at compile-time
#
# ############################################################

macro debugConsts(): untyped =
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

debug:
  debugConsts()
