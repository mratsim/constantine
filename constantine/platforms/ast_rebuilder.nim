# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import std/macros

proc rebuildUntypedAst*(ast: NimNode, dropRootStmtList = false): NimNode =
  ## In some cases (generics or static proc) Nim gives us
  ## typed NimNode which are hard to process.
  ## This rebuilds an untyped AST.
  ##
  ## Additionally this allows dropping the root StmtList that
  ## may wrap the typed AST from early symbol resolution
  proc rebuild(node: NimNode): NimNode =
    proc defaultMultipleChildren(node: NimNode): NimNode =
      var rTree = node.kind.newTree()
      for child in node:
        rTree.add rebuild(child)
      return rTree

    case node.kind:
    of {nnkIdent, nnkSym}:
      return ident($node)
    of nnkEmpty:
      return node
    of nnkLiterals:
      return node
    of nnkHiddenStdConv:
      if node[1].kind == nnkIntLit:
        return node[1]
      else:
        expectKind(node[1], nnkSym)
        return ident($node[1])
    of nnkConv: # type conversion needs to be replaced by a function call in untyped AST
      var rTree = nnkCall.newTree()
      for child in node:
        rTree.add rebuild(child)
      return rTree
    of {nnkCall, nnkInfix, nnkPrefix}:
      if node[0].kind == nnkOpenSymChoice:
        if node[0][0].eqIdent"contains":
          var rTree = nnkInfix.newTree()
          rTree.add ident"in"
          rTree.add rebuild(node[2])
          rTree.add rebuild(node[1])
          return rTree
        else:
          var rTree = node.kind.newTree()
          rTree.add rebuild(node[0][0])
          for i in 1 ..< node.len:
            rTree.add rebuild(node[i])
          return rTree
      elif node[0].kind == nnkClosedSymChoice:
        if node[0][0].eqIdent"addr":
          node.expectLen(1)
          return nnkAddr.newTree(rebuild(node[1]))
        else:
          var rTree = node.kind.newTree()
          rTree.add rebuild(node[0][0])
          for i in 1 ..< node.len:
            rTree.add rebuild(node[i])
          return rTree
      else:
        return defaultMultipleChildren(node)
    of {nnkOpenSymChoice, nnkClosedSymChoice}:
      return rebuild(node[0])
    else:
      return defaultMultipleChildren(node)

  if dropRootStmtList and ast.kind == nnkStmtList:
    return rebuild(ast[0])
  else:
    result = rebuild(ast)