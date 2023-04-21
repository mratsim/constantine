# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import std/macros

# OpenArray type
# ---------------------------------------------------------

template toOpenArray*[T](p: ptr UncheckedArray[T], len: int): openArray[T] =
  p.toOpenArray(0, len-1)

# View type
# ---------------------------------------------------------
#
# This view type is equivalent to (pointer + length)
# like openArray. Unlike openArray it can be stored in a type
# Or can be used for nested views like openArray[View[byte]]

type View*[T] = object
  # TODO, use `lent UncheckedArray[T]` for proper borrow-checking - https://github.com/nim-lang/Nim/issues/21674
  data: ptr UncheckedArray[T]
  len: int

template toOpenArray*[T](v: View[T]): openArray[T] =
  v.data.toOpenArray(0, v.len-1)

# Binary blob API
# ---------------------------------------------------------
#
# High-level API needs to provide functions of the form
# - func verify[T: byte|char](pubkey: PubKey, message: T, signature: Signature)
# - func update[T: byte|char](ctx: var Sha256Context, message: openarray[T])
#
# for all APIs that ingest bytes/strings including:
# - Ciphers
# - Signature protocols
# - Hashing algorithms
# - Message Authentication code
# - Key derivation functions
#
# This causes the following issues:
# - Code explosion due to monomorphization. The code for bytes and char will be duplicated needlessly.
# - Cannot be exported to C. Generic code cannot be exported to C and so will need manual split
# - Longer compile-times. The inner functions can be byte-only instead of using generics.
#
# Instead we create a `genCharAPI` macro that generates the same function as an openArray[byte]
# but with openArray[char] inputs

template toOpenArrayByte[T: byte|char](oa: openArray[T]): openArray[byte] =
  when T is byte:
    oa
  else:
    oa.toOpenArrayByte(oa.low, oa.high)

macro genCharAPI*(procAst: untyped): untyped =
  ## For each openArray[byte] parameter in the input proc
  ## generate an openArray[char] variation.
  procAst.expectKind({nnkProcDef, nnkFuncDef})

  result = newStmtList()
  result.add procAst

  var genericParams = procAst[2].copyNimTree()
  var wrapperParams = nnkFormalParams.newTree(procAst.params[0].copyNimTree())
  var wrapperBody = newCall(ident($procAst.name))

  proc matchBytes(node: NimNode): bool =
    node.kind == nnkBracketExpr and
      node[0].eqIdent"openArray" and
      node[1].eqIdent"byte"

  # We do 2 passes:
  # If a single params is openArray[byte], we instantiate a non-generic proc.
  # - This should make for faster compile-times.
  # - It is also necessary for `hash` and `mac`, as it seems like overloading
  #   a concept function with an argument that matches but the generic and a concrete param
  #   crashes. i.e. either you use full generic (with genCharAPI) or you instantiate 2 concrete procs

  let countBytesParams = block:
    var count = 0
    for i in 1 ..< procAst.params.len:
      if procAst.params[i][^2].matchBytes():
        count += 1
      elif procAst.params[i][^2].kind == nnkVarTy and procAst.params[i][^2][0].matchBytes():
        count += 1
    count

  if countBytesParams == 0:
    error "Using genCharAPI on an input without any openArray[byte] parameter."

  if countBytesParams == 1:
    for i in 1 ..< procAst.params.len:
      # Unfortunately, even in typed macro, .sameType(getType(openArray[byte])) doesn't match
      if procAst.params[i][^2].matchBytes():
        # Handle "a, b: openArray[byte]"
        for j in 0 ..< procAst.params[i].len - 2:
          wrapperParams.add newIdentDefs(
            procAst.params[i][j].copyNimTree(),
            nnkBracketExpr.newTree(ident"openArray", ident"char"))
          wrapperBody.add newCall(bindSym"toOpenArrayByte", procAst.params[i][j])
      elif procAst.params[i][^2].kind == nnkVarTy and procAst.params[i][^2][0].matchBytes():
        # Handle "a, b: openArray[byte]"
        for j in 0 ..< procAst.params[i].len - 2:
          wrapperParams.add newIdentDefs(
            procAst.params[i][j].copyNimTree(),
            nnkVarTy.newTree(nnkBracketExpr.newTree(ident"openArray", ident"char")))
          wrapperBody.add newCall(bindSym"toOpenArrayByte", procAst.params[i][j])
      else:
        wrapperParams.add procAst.params[i].copyNimTree()
        # Handle "a, b: int"
        for j in 0 ..< procAst.params[i].len - 2:
          wrapperBody.add ident($procAst.params[i][j])

  else:
    if genericParams.kind == nnkEmpty:
      genericParams = nnkGenericParams.newTree()

    for i in 1 ..< procAst.params.len:
      # Unfortunately, even in typed macro, .sameType(getType(openArray[byte])) doesn't match
      if procAst.params[i][^2].matchBytes():
        # Handle "a, b: openArray[byte]"
        for j in 0 ..< procAst.params[i].len - 2:
          let genericId = ident("API_" & $i & "_" & $j)
          wrapperParams.add newIdentDefs(
            procAst.params[i][j].copyNimTree(),
            nnkBracketExpr.newTree(ident"openArray", genericId))
          genericParams.add newIdentDefs(
            genericId,
            nnkInfix.newTree(ident("|"), ident("byte"), ident("char")))
          wrapperBody.add newCall(bindSym"toOpenArrayByte", procAst.params[i][j])
      elif procAst.params[i][^2].kind == nnkVarTy and procAst.params[i][^2][0].matchBytes():
        for j in 0 ..< procAst.params[i].len - 2:
          let genericId = ident("API_" & $i & "_" & $j)
          wrapperParams.add newIdentDefs(
            procAst.params[i][j].copyNimTree(),
            nnkVarTy.newTree(nnkBracketExpr.newTree(bindSym"openArray", genericId)))
          genericParams.add newIdentDefs(
            genericId,
            nnkInfix.newTree(ident("|"), ident("byte"), ident("char")))
          wrapperBody.add newCall(bindSym"toOpenArrayByte", procAst.params[i][j])
      else:
        wrapperParams.add procAst.params[i].copyNimTree()
        # Handle "a, b: int"
        for j in 0 ..< procAst.params[i].len - 2:
          wrapperBody.add ident($procAst.params[i][j])

  var pragmas = nnkPragma.newTree(ident"inline")
  let skipPragmas = ["inline", "noinline", "noInline", "exportc", "exportcpp", "extern", "noconv", "cdecl", "stdcall", "dynlib", "libPrefix"]
  for i in 0 ..< procAst.pragma.len:
    if procAst.pragma[i].kind == nnkIdent:
      if $procAst.pragma[i] notin skipPragmas:
        pragmas.add procAst.pragma[i].copyNimTree()
    else:
      procAst.pragma[i].expectKind(nnkExprColonExpr)
      if $procAst.pragma[i][0] notin skipPragmas:
        pragmas.add procAst.pragma[i].copyNimTree()

  let wrapper = newTree(
    procAst.kind,             # proc or func
    procAst[0].copyNimTree(), # name: Keep export marker if any
    newEmptyNode(),           # term-rewriting macros
    genericParams,
    wrapperParams,
    pragmas,
    newEmptyNode(),
    wrapperBody)
  result.add wrapper

when isMainModule:
  expandMacros:

    proc foo(x: int, a: openArray[byte]) {.genCharAPI.} =
      discard

    proc bar(x: int, a: openArray[byte], b: openArray[byte]) {.genCharAPI.} =
      discard