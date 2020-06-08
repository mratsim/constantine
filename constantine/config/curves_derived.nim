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
  ./curves_declaration,
  ./type_fp,
  ../io/io_bigints

{.experimental: "dynamicBindSym".}

macro genDerivedConstants*(): untyped =
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

  for curveSym in low(Curve) .. high(Curve):
    let curve = $curveSym

    # const MyCurve_CanUseNoCarryMontyMul = useNoCarryMontyMul(MyCurve_Modulus)
    result.add newConstStmt(
      used(curve & "_CanUseNoCarryMontyMul"), newCall(
        bindSym"useNoCarryMontyMul",
        bindSym(curve & "_Modulus")
      )
    )

    # const MyCurve_CanUseNoCarryMontySquare = useNoCarryMontySquare(MyCurve_Modulus)
    result.add newConstStmt(
      used(curve & "_CanUseNoCarryMontySquare"), newCall(
        bindSym"useNoCarryMontySquare",
        bindSym(curve & "_Modulus")
      )
    )

    # const MyCurve_R2modP = r2mod(MyCurve_Modulus)
    result.add newConstStmt(
      used(curve & "_R2modP"), newCall(
        bindSym"r2mod",
        bindSym(curve & "_Modulus")
      )
    )

    # const MyCurve_NegInvModWord = negInvModWord(MyCurve_Modulus)
    result.add newConstStmt(
      used(curve & "_NegInvModWord"), newCall(
        bindSym"negInvModWord",
        bindSym(curve & "_Modulus")
      )
    )
    # const MyCurve_montyOne = montyOne(MyCurve_Modulus)
    result.add newConstStmt(
      used(curve & "_MontyOne"), newCall(
        bindSym"montyOne",
        bindSym(curve & "_Modulus")
      )
    )
    # const MyCurve_MontyPrimeMinus1 = montyPrimeMinus1(MyCurve_Modulus)
    result.add newConstStmt(
      used(curve & "_MontyPrimeMinus1"), newCall(
        bindSym"montyPrimeMinus1",
        bindSym(curve & "_Modulus")
      )
    )
    # const MyCurve_InvModExponent = primeMinus2_BE(MyCurve_Modulus)
    result.add newConstStmt(
      used(curve & "_InvModExponent"), newCall(
        bindSym"primeMinus2_BE",
        bindSym(curve & "_Modulus")
      )
    )
    # const MyCurve_PrimePlus1div2 = primePlus1div2(MyCurve_Modulus)
    result.add newConstStmt(
      used(curve & "_PrimePlus1div2"), newCall(
        bindSym"primePlus1div2",
        bindSym(curve & "_Modulus")
      )
    )
    # const MyCurve_PrimeMinus1div2_BE = primeMinus1div2_BE(MyCurve_Modulus)
    result.add newConstStmt(
      used(curve & "_PrimeMinus1div2_BE"), newCall(
        bindSym"primeMinus1div2_BE",
        bindSym(curve & "_Modulus")
      )
    )
    # const MyCurve_PrimeMinus3div4_BE = primeMinus3div4_BE(MyCurve_Modulus)
    result.add newConstStmt(
      used(curve & "_PrimeMinus3div4_BE"), newCall(
        bindSym"primeMinus3div4_BE",
        bindSym(curve & "_Modulus")
      )
    )
    # const MyCurve_PrimePlus1div4_BE = primePlus1div4_BE(MyCurve_Modulus)
    result.add newConstStmt(
      used(curve & "_PrimePlus1div4_BE"), newCall(
        bindSym"primePlus1div4_BE",
        bindSym(curve & "_Modulus")
      )
    )

    # const MyCurve_cubicRootOfUnity
    block:
      let cubicHex = ident(curve & "_cubicRootOfUnityHex")
      let cubic = used(curve & "_cubicRootOfUnity")
      let M = bindSym(curve & "_Modulus")
      let r2modM = ident(curve & "_R2modP")
      let m0ninv = ident(curve & "_NegInvModWord")
      result.add quote do:
        when declared(`cubichex`):
          const `cubic` = block:
            var cubic: Fp[Curve(`curveSym`)]
            montyResidue_precompute(
              cubic.mres,
              fromHex(cubic.mres.typeof, `cubicHex`),
              `M`, `r2modM`, `m0ninv`
            )
            cubic

    if CurveFamilies[curveSym] == BarretoNaehrig:
      # when declared(MyCurve_BN_param_u):
      #   const MyCurve_BN_u_BE = toCanonicalIntRepr(MyCurve_BN_param_u)
      #   const MyCurve_BN_6u_minus_1_BE = bn_6u_minus_1_BE(MyCurve_BN_param_u)
      var bnStmts = newStmtList()
      bnStmts.add newConstStmt(
        used(curve & "_BN_u_BE"), newCall(
          bindSym"toCanonicalIntRepr",
          ident(curve & "_BN_param_u")
        )
      )
      bnStmts.add newConstStmt(
        used(curve & "_BN_6u_minus_1_BE"), newCall(
          bindSym"bn_6u_minus_1_BE",
          ident(curve & "_BN_param_u")
        )
      )

      result.add nnkWhenStmt.newTree(
        nnkElifBranch.newTree(
          newCall(ident"declared", ident(curve & "_BN_param_u")),
          bnStmts
        )
      )

  # echo result.toStrLit()
