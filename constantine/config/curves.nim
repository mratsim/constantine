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
  ../math/[precomputed, bigints_checked]


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
else:
  # Fake curve for testing field arithmetic
  declareCurves:
    curve Fake101:
      bitsize: 7
      modulus: "0x65" # 101 in hex

# ############################################################
#
#    Autogeneration of precomputed constants in ROM
#
# ############################################################

const MontyNegInvModWord* = block:
  ## Store the Montgomery Magic Constant "Negative Inverse mod 2^63" in ROM
  var buf: array[Curve, BaseType]
  for curve in Curve:
    buf[curve] = curve.Mod.mres.negInvModWord
  buf

{.experimental: "dynamicBindSym".}

macro genR2modP(T: typed): untyped =
  ## Store the Montgomery Magic Constant "R^2 mod N" in ROM
  ## For each curve under the private symbol "MyCurve_R2modP"
  T.getImpl.expectKind(nnkTypeDef)
  T.getImpl[2].expectKind(nnkEnumTy)

  result = newStmtList()

  let E = T.getImpl[2]
  for i in 1 ..< E.len:
    let curve = E[i]
    result.add newConstStmt(
      ident($curve & "_R2modP"), newCall(
        bindSym"r2mod",
        # The curve parser creates modulus
        # under symbol "MyCurve_Modulus"
        nnkDotExpr.newTree(
          bindSym($curve & "_Modulus"),
          ident"mres"
        )
      )
    )

  # echo result.toStrLit

genR2modP(Curve)

macro getR2modP*(C: static Curve): untyped =
  ## Get the Montgomery Magic Constant Associated to a curve
  result = bindSym($C & "_R2modP")
