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
  ../io/io_bigints, ../arithmetic/bigints_checked

# Macro to parse declarative curves configuration.

macro declareCurves*(curves: untyped): untyped =
  ## Parse curve configuration and generates
  ##
  ## type Curve = enum
  ##   BN254
  ##   ...
  ##
  ## const CurveBitSize* = array[
  ##   BN254: 254,
  ##   ...
  ## ]
  ##
  ## TODO: Ensure that the modulus is not inlined at runtime
  ##       to avoid codesize explosion.
  ## const BN254_Modulus = fromHex(BigInt[254], "0x30644e72e131a029b85045b68181585d97816a916871ca8d3c208c16d87cfd47")
  ##
  ## func fieldModulus*(curve: static Curve): auto =
  ##   when curve == BN254_Modulus: BN254_Modulus
  ##   ...
  curves.expectKind(nnkStmtList)

  # curve BN254:
  #   bitsize: 254
  #   modulus: "0x30644e72e131a029b85045b68181585d97816a916871ca8d3c208c16d87cfd47"
  #
  # is parsed into
  #
  # StmtList
  #   Command
  #     Ident "curve"
  #     Ident "BN254"
  #     StmtList
  #       Call
  #         Ident "bitsize"
  #         StmtList
  #           IntLit 254
  #       Call
  #         Ident "modulus"
  #         StmtList
  #           StrLit "0x30644e72e131a029b85045b68181585d97816a916871ca8d3c208c16d87cfd47"

  var Curves: seq[NimNode]
  var CurveBitSize = nnKBracket.newTree()
  var curveModStmts = newStmtList()

  let Fq = ident"Fq"

  for curveDesc in curves:
    curveDesc.expectKind(nnkCommand)
    doAssert curveDesc[0].eqIdent"curve"
    curveDesc[1].expectKind(nnkIdent)    # Curve name
    curveDesc[2].expectKind(nnkStmtList)
    curveDesc[2][0].expectKind(nnkCall)
    curveDesc[2][1].expectKind(nnkCall)

    let curve = curveDesc[1]

    let sizeSection = curveDesc[2][0]
    doAssert sizeSection[0].eqIdent"bitsize"
    sizeSection[1].expectKind(nnkStmtList)
    let bitSize = sizeSection[1][0]

    let modSection = curveDesc[2][1]
    doAssert modSection[0].eqIdent"modulus"
    modSection[1].expectKind(nnkStmtList)
    let modulus = modSection[1][0]

    Curves.add curve
    # "BN254: 254" for array construction
    CurveBitSize.add nnkExprColonExpr.newTree(
      curve, bitSize
    )

    # const BN254_Modulus = Fq[BN254](value: fromHex(BigInt[254], "0x30644e72e131a029b85045b68181585d97816a916871ca8d3c208c16d87cfd47"))
    let modulusID = ident($curve & "_Modulus")
    curveModStmts.add newConstStmt(
      modulusID,
      nnkObjConstr.newTree(
        nnkBracketExpr.newTree(Fq, curve),
        nnkExprColonExpr.newTree(
          ident"mres",
          newCall(
            bindSym"fromHex",
            nnkBracketExpr.newTree(bindSym"BigInt", bitSize),
            modulus
          )
        )
      )
    )

  # end for ---------------------------------------------------

  result = newStmtList()

  # type Curve = enum
  let Curve = ident"Curve"
  result.add newEnum(
    name = Curve,
    fields = Curves,
    public = true,
    pure = false
  )

  # const CurveBitSize: array[Curve, int] = ...
  let cbs = ident("CurveBitSize")
  result.add newConstStmt(
    cbs, CurveBitSize
  )

  # Need template indirection in the type section to avoid Nim sigmatch bug
  # template matchingBigInt(C: static Curve): untyped =
  #   BigInt[CurveBitSize[C]]
  let C = ident"C"
  let matchingBigInt = genSym(nskTemplate, "matchingBigInt")
  result.add newProc(
    name = matchingBigInt,
    params = [ident"untyped", newIdentDefs(C, nnkStaticTy.newTree(Curve))],
    body = nnkBracketExpr.newTree(bindSym"BigInt", nnkBracketExpr.newTree(cbs, C)),
    procType = nnkTemplateDef
  )

  # type
  #   `Fq`*[C: static Curve] = object
  #     ## All operations on a field are modulo P
  #     ## P being the prime modulus of the Curve C
  #     ## Internally, data is stored in Montgomery n-residue form
  #     ## with the magic constant chosen for convenient division (a power of 2 depending on P bitsize)
  #     mres*: matchingBigInt(C)
  result.add nnkTypeSection.newTree(
    nnkTypeDef.newTree(
      nnkPostfix.newTree(ident"*", Fq),
      nnkGenericParams.newTree(newIdentDefs(
        C, nnkStaticTy.newTree(Curve), newEmptyNode()
      )),
      # TODO: where should I put the nnkCommentStmt?
      nnkObjectTy.newTree(
        newEmptyNode(),
        newEmptyNode(),
        nnkRecList.newTree(
          newIdentDefs(
            nnkPostfix.newTree(ident"*", ident"mres"),
            newCall(matchingBigInt, C)
          )
        )
      )
    )
  )

  result.add curveModStmts

  # echo result.toStrLit()
