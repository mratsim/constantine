# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import std/macros

proc replaceNodes(ast: NimNode, what: NimNode, by: NimNode): NimNode =
  # Replace "what" ident node by "by"
  proc inspect(node: NimNode): NimNode =
    case node.kind:
    of {nnkIdent, nnkSym}:
      if node.eqIdent(what):
        return by
      return node
    of nnkEmpty:
      return node
    of nnkLiterals:
      return node
    else:
      var rTree = node.kind.newTree()
      for child in node:
        rTree.add inspect(child)
      return rTree
  result = inspect(ast)

macro staticFor*(idx: untyped{nkIdent}, start, stopEx: static int, body: untyped): untyped =
  result = newStmtList()
  for i in start ..< stopEx:
    result.add nnkBlockStmt.newTree(
      ident("unrolledIter_" & $idx & $i),
      body.replaceNodes(idx, newLit i))

macro staticForStepped*(idx: untyped{nkIdent}, start, stopEx, increment: static int, body: untyped): untyped =
  ## Version of `staticFor` which takes an increment != 1.
  result = newStmtList()
  for i in countup(start, stopEx - increment, increment):
    result.add nnkBlockStmt.newTree(
      ident("unrolledIter_" & $idx & $i),
      body.replaceNodes(idx, newLit i))

macro staticForCountdown*(idx: untyped{nkIdent}, start, stopIncl: static int, body: untyped): untyped =
  result = newStmtList()
  for i in countdown(start, stopIncl):
    result.add nnkBlockStmt.newTree(
      ident("unrolledIter_" & $idx & $i),
      body.replaceNodes(idx, newLit i))

{.experimental: "dynamicBindSym".}

const nim_v2 = (NimMajor, NimMinor) > (1, 6)

macro staticFor*(ident: untyped{nkIdent}, choices: typed, body: untyped): untyped =
  ## matches
  ##   staticFor(curve, TestCurves):
  ##     body
  ## and unroll the body for each curve in TestCurves

  let choices = if choices.kind == nnkSym:
                  # Unpack symbol
                  let impl = choices.getImpl()
                  when nim_v2:
                    impl[2] # nnkConstDef
                  else:
                    impl
                else:
                  choices.expectKind(nnkBracket)
                  choices

  result = newStmtList()
  for i in 0 ..< choices.len:
    result.add nnkBlockStmt.newTree(
      nnkAccQuoted.newTree(ident, ident("_"), ident($i)),
      body.replaceNodes(ident, choices[i]))
