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
      body.replaceNodes(idx, newLit i)
    )

{.experimental: "dynamicBindSym".}

macro staticFor*(ident: untyped{nkIdent}, choices: typed, body: untyped): untyped =
  ## matches
  ##   staticFor(curve, TestCurves):
  ##     body
  ## and unroll the body for each curve in TestCurves

  let choices = if choices.kind == nnkSym:
                  # Unpack symbol
                  choices.getImpl()
                else:
                  choices.expectKind(nnkBracket)
                  choices

  result = newStmtList()
  for choice in choices:
    result.add nnkBlockStmt.newTree(
      ident($ident & "_" & $choice.intVal),
      body.replaceNodes(ident, choice)
    )
