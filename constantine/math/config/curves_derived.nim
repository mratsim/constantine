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
  ./precompute,
  ./curves_declaration

{.experimental: "dynamicBindSym".}

type
  DerivedConstantMode* = enum
    kModulus
    kOrder

macro genDerivedConstants*(mode: static DerivedConstantMode): untyped =
  ## Generate constants derived from the main constants
  ##
  ## For example
  ## - the Montgomery magic constant "R^2 mod N" in ROM
  ##   For each curve under the private symbol "MyCurve_R2modP"
  ## - the Montgomery magic constant -1/P mod 2^Wordbitwidth
  ##   For each curve under the private symbol "MyCurve_NegInvModWord
  ## - ...

  # Now typedesc are NimNode and there is no way to translate
  # NimNode -> typedesc easily so we can't
  # "for curve in low(Curve) .. high(Curve):"
  # As an ugly workaround, we count
  # The item at position 0 is a pragma
  result = newStmtList()

  template used(name: string): NimNode =
    nnkPragmaExpr.newTree(
      ident(name),
      nnkPragma.newTree(ident"used")
    )

  let ff = if mode == kModulus: "_Fp" else: "_Fr"


  for curveSym in low(Curve) .. high(Curve):
    let curve = $curveSym
    let M = if mode == kModulus: bindSym(curve & "_Modulus")
            else: bindSym(curve & "_Order")

    # const MyCurve_SpareBits = countSpareBits(MyCurve_Modulus)
    result.add newConstStmt(
      used(curve & ff & "_SpareBits"), newCall(
        bindSym"countSpareBits",
        M
      )
    )

    # const MyCurve_R2modP = r2mod(MyCurve_Modulus)
    result.add newConstStmt(
      used(curve & ff & "_R2modP"), newCall(
        bindSym"r2mod",
        M
      )
    )
    # const MyCurve_R4modP = r4mod(MyCurve_Modulus)
    result.add newConstStmt(
      used(curve & ff & "_R3modP"), newCall(
        bindSym"r3mod",
        M
      )
    )

    # const MyCurve_NegInvModWord = negInvModWord(MyCurve_Modulus)
    result.add newConstStmt(
      used(curve & ff & "_NegInvModWord"), newCall(
        bindSym"negInvModWord",
        M
      )
    )
    # const MyCurve_montyOne = montyOne(MyCurve_Modulus)
    result.add newConstStmt(
      used(curve & ff & "_MontyOne"), newCall(
        bindSym"montyOne",
        M
      )
    )
    # const MyCurve_MontyPrimeMinus1 = montyPrimeMinus1(MyCurve_Modulus)
    result.add newConstStmt(
      used(curve & ff & "_MontyPrimeMinus1"), newCall(
        bindSym"montyPrimeMinus1",
        M
      )
    )
    # const MyCurve_PrimePlus1div2 = primePlus1div2(MyCurve_Modulus)
    result.add newConstStmt(
      used(curve & ff & "_PrimePlus1div2"), newCall(
        bindSym"primePlus1div2",
        M
      )
    )
    # const MyCurve_PrimeMinus1div2 = primeMinus1div2(MyCurve_Modulus)
    result.add newConstStmt(
      used(curve & ff & "_PrimeMinus1div2"), newCall(
        bindSym"primeMinus1div2",
        M
      )
    )
    # const MyCurve_PrimeMinus3div4_BE = primeMinus3div4_BE(MyCurve_Modulus)
    result.add newConstStmt(
      used(curve & ff & "_PrimeMinus3div4_BE"), newCall(
        bindSym"primeMinus3div4_BE",
        M
      )
    )
    # const MyCurve_PrimeMinus5div8_BE = primeMinus5div8_BE(MyCurve_Modulus)
    result.add newConstStmt(
      used(curve & ff & "_PrimeMinus5div8_BE"), newCall(
        bindSym"primeMinus5div8_BE",
        M
      )
    )
