# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import std/macros
import ../../ast_rebuilder

# ############################################################
#
#                     Binding utilities
#
# ############################################################

# Flag parameters
# ------------------------------------------------------------

type Flag*[E: enum] = distinct cint

func flag*[E: enum](e: varargs[E]): Flag[E] {.inline.} =
  ## Enum should only have power of 2 fields
  # static:
  #   for val in E:
  #     assert (ord(val) and (ord(val) - 1)) == 0, "Enum values should all be power of 2, found " &
  #                                                 $val & " with value " & $ord(val) & "."
  var flags = 0
  for val in e:
    flags = flags or ord(val)
  result = Flag[E](flags)

# Macros
# ------------------------------------------------------------

macro replacePragmasByInline(procAst: typed): untyped =
  ## Replace pragmas by the inline pragma
  ## We need a separate "typed" macro
  ## so that it is executed after the {.push mypragma.} calls
  var params: seq[NimNode]
  for i in 0 ..< procAst.params.len:
    params.add procAst.params[i]

  result = newStmtList()

  # The push noconv is applied multiple times :/, so fight push with push
  result.add nnkPragma.newTree(ident"push", ident"nimcall", ident"inline")

  result.add newProc(
    name = procAst.name,
    params = params,
    body = procAst.body.rebuildUntypedAst(),
    procType = nnkProcDef,
    pragmas = nnkPragma.newTree(ident"inline", ident"nimcall")
  )

  result.add nnkPragma.newTree(ident"pop")

macro wrapOpenArrayLenType*(ty: typedesc, procAst: untyped): untyped =
  ## Wraps pointer+len library calls in properly typed and converted openArray calls
  ##
  ## ```
  ## {.push noconv.}
  ## proc foo*(r: int, a: openArray[CustomType], b: int) {.wrapOpenArrayLenType: uint32, importc: "foo", dynlib: "libfoo.so".}
  ## {.pop.}
  ## ```
  ##
  ## is transformed into
  ##
  ## ```
  ## proc foo(r: int, a: ptr CustomType, aLen: uint32, b: int) {.noconv, importc: "foo", dynlib: "libfoo.so".}
  ##
  ## proc foo*(r: int, a: openArray[CustomType], b: int) {.inline.} =
  ##   foo(r, a[0].unsafeAddr, a.len.uint32, b)
  ## ```
  procAst.expectKind(nnkProcDef)

  var
    wrappeeParams = @[procAst.params[0]]
    wrapperParams = @[procAst.params[0]]
    wrapperBody = newCall(ident($procAst.name))

  for i in 1 ..< procAst.params.len:
    if procAst.params[i][^2].kind == nnkBracketExpr and procAst.params[i][^2][0].eqident"openarray":
      procAst.params[i].expectLen(3) # prevent `proc foo(a, b: openArray[int])`
      wrappeeParams.add newIdentDefs(
        ident($procAst.params[i][0] & "Ptr"),
        nnkPtrTy.newTree(procAst.params[i][^2][1]),
        newEmptyNode()
      )
      wrappeeParams.add newIdentDefs(
        ident($procAst.params[i][0] & "Len"),
        ty,
        newEmptyNode()
      )
      wrapperParams.add procAst.params[i]
      wrapperBody.add nnkIfExpr.newTree(
        nnkElifExpr.newTree(
          nnkInfix.newTree(
            ident"==",
            nnkDotExpr.newTree(ident($procAst.params[i][0]), bindSym"len"),
            newLit 0
          ),
          newNilLit()
        ),
        nnkElseExpr.newTree(
          newCall(
          ident"unsafeAddr",
          nnkBracketExpr.newTree(
            ident($procAst.params[i][0]),
            newLit 0
          ))
        )
      )
      wrapperBody.add newCall(ty, nnkDotExpr.newTree(ident($procAst.params[i][0]), bindSym"len"))
    else:
      wrappeeParams.add procAst.params[i]
      wrapperParams.add procAst.params[i]
      # Handle "a, b: int"
      for j in 0 ..< procAst.params[i].len - 2:
        wrapperBody.add ident($procAst.params[i][j])

  let wrappee = newProc(
    name = ident($procAst.name),                                 # Remove export marker if any
    params = wrappeeParams,
    body = procAst.body.copyNimTree(),
    procType = nnkProcDef,
    pragmas = procAst.pragma
  )
  let wrapper = newProc(
    name = procAst[0],                                           # keep export marker if any
    params = wrapperParams,
    body = newStmtList(procAst.body.copyNimTree(), wrapperBody), # original procAst body can contain comments that we copy
    procType = nnkProcDef,
    pragmas = nnkPragma.newTree(bindSym"replacePragmasByInline") # pragmas are for the wrappee
  )

  result = newStmtList(wrappee, wrapper)

when isMainModule:
  expandMacros:
    {.push noconv.}

    proc foo(x: int, a: openArray[uint32], name: cstring) {.wrapOpenArrayLenType: cuint.} =
      discard

    {.pop.}
