# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  std/macros,
  ./primitives

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
  len*: int

template toOpenArray*[T](v: View[T]): openArray[T] =
  v.data.toOpenArray(0, v.len-1)

func toView*[T](oa: openArray[T]): View[T] {.inline.} =
  View[T](data: cast[ptr UncheckedArray[T]](oa[0].unsafeAddr), len: oa.len)

func toView*[T](data: ptr UncheckedArray[T], len: int): View[T] {.inline.} =
  View[T](data: data, len: len)

func `[]`*[T](v: View[T], idx: int): lent T {.inline.} =
  v.data[idx]

func chunk*[T](v: View[T], start, len: int): View[T] {.inline.} =
  ## Create a sub-chunk from a view
  debug:
    doAssert start >= 0
    doAssert start + len <= v.len
  result.data = v.data +% start
  result.len = len

type MutableView*[T] {.borrow: `.`.} = distinct View[T]

template toOpenArray*[T](v: MutableView[T]): openArray[T] =
  v.data.toOpenArray(0, v.len-1)

func toMutableView*[T](data: ptr UncheckedArray[T], len: int) {.inline.} =
  View[T](data: data, len: len)
func `[]`*[T](v: MutableView[T], idx: int): var T {.inline.} =
  v.data[idx]
func `[]=`*[T](v: MutableView[T], idx: int, val: T) {.inline.} =
  v.data[idx] = val

# StridedView type
# ---------------------------------------------------------
# using the borrow checker with `lent` requires a recent Nim
# https://github.com/nim-lang/Nim/issues/21674

type
  StridedView*[T] = object
    ## A strided view over an (unowned) data buffer
    len*: int
    stride: int
    offset: int
    data: ptr UncheckedArray[T]

func `[]`*[T](v: StridedView[T], idx: int): lent T {.inline.} =
  v.data[v.offset + idx*v.stride]

func `[]`*[T](v: var StridedView[T], idx: int): var T {.inline.} =
  v.data[v.offset + idx*v.stride]

func `[]=`*[T](v: var StridedView[T], idx: int, val: T) {.inline.} =
  v.data[v.offset + idx*v.stride] = val

func toStridedView*[T](oa: openArray[T]): StridedView[T] {.inline.} =
  result.len = oa.len
  result.stride = 1
  result.offset = 0
  result.data = cast[ptr UncheckedArray[T]](oa[0].unsafeAddr)

func toStridedView*[T](p: ptr UncheckedArray[T], len: int): StridedView[T] {.inline.} =
  result.len = len
  result.stride = 1
  result.offset = 0
  result.data = p

iterator items*[T](v: StridedView[T]): lent T =
  var cur = v.offset
  for _ in 0 ..< v.len:
    yield v.data[cur]
    cur += v.stride

func `$`*(v: StridedView): string =
  result = "StridedView["
  var first = true
  for elem in v:
    if not first:
      result &= ", "
    else:
      first = false
    result &= $elem
  result &= ']'

func toHex*(v: StridedView): string =
  mixin toHex

  result = "StridedView["
  var first = true
  for elem in v:
    if not first:
      result &= ", "
    else:
      first = false
    result &= elem.toHex()
  result &= ']'

# FFT-specific splitting
# -------------------------------------------------------------------------------

func splitAlternate*(t: StridedView): tuple[even, odd: StridedView] {.inline.} =
  ## Split the tensor into 2
  ## partitioning the input every other index
  ## even: indices [0, 2, 4, ...]
  ## odd: indices [ 1, 3, 5, ...]
  assert (t.len and 1) == 0, "The tensor must contain an even number of elements"

  let half = t.len shr 1
  let skipHalf = t.stride shl 1

  result.even.len = half
  result.even.stride = skipHalf
  result.even.offset = t.offset
  result.even.data = t.data

  result.odd.len = half
  result.odd.stride = skipHalf
  result.odd.offset = t.offset + t.stride
  result.odd.data = t.data

func splitMiddle*(t: StridedView): tuple[left, right: StridedView] {.inline.} =
  ## Split the tensor into 2
  ## partitioning into left and right halves.
  ## left:  indices [0, 1, 2, 3]
  ## right: indices  [4, 5, 6, 7]
  assert (t.len and 1) == 0, "The tensor must contain an even number of elements"

  let half = t.len shr 1

  result.left.len = half
  result.left.stride = t.stride
  result.left.offset = t.offset
  result.left.data = t.data

  result.right.len = half
  result.right.stride = t.stride
  result.right.offset = t.offset + half
  result.right.data = t.data

func skipHalf*(t: StridedView): StridedView {.inline.} =
  ## Pick one every other indices
  ## output: [0, 2, 4, ...]
  assert (t.len and 1) == 0, "The tensor must contain an even number of elements"

  result.len = t.len shr 1
  result.stride = t.stride shl 1
  result.offset = t.offset
  result.data = t.data

func slice*(v: StridedView, start, stop, step: int): StridedView {.inline.} =
  ## Slice a view
  ## stop is inclusive
  # General tensor slicing algorithm is
  # https://github.com/mratsim/Arraymancer/blob/71cf616/src/arraymancer/tensor/private/p_accessors_macros_read.nim#L26-L56
  #
  # for i, slice in slices:
  #   # Check if we start from the end
  #   let a = if slice.a_from_end: result.shape[i] - slice.a
  #           else: slice.a
  #
  #   let b = if slice.b_from_end: result.shape[i] - slice.b
  #           else: slice.b
  #
  #   # Compute offset:
  #   result.offset += a * result.strides[i]
  #   # Now change shape and strides
  #   result.strides[i] *= slice.step
  #   result.shape[i] = abs((b-a) div slice.step) + 1
  #
  # with slices being of size 1, as we have a monodimensional Tensor
  # and the slice being a..<b with the reverse case: len-1 -> 0
  #
  # result is preinitialized with a copy of v (shape, stride, offset, data)
  result.offset = v.offset + start * v.stride
  result.stride = v.stride * step
  result.len = abs((stop-start) div step) + 1
  result.data = v.data

func reversed*(v: StridedView): StridedView {.inline.} =
  # Hopefully the compiler optimizes div by -1
  v.slice(v.len-1, 0, -1)

# Debugging helpers
# ---------------------------------------------------------

when defined(debugConstantine):
  import std/[strformat, strutils]

  func display*[F](name: string, indent: int, oa: openArray[F]) =
    debugEcho strutils.indent(name & ", openarray of " & $F & " of length " & $oa.len, indent)
    for i in 0 ..< oa.len:
      debugEcho strutils.indent(&"    {i:>2}: {oa[i].toHex()}", indent)
    debugEcho strutils.indent(name & "  " & $F & " -- FIN\n", indent)

  func display*[F](name: string, indent: int, v: StridedView[F]) =
    debugEcho strutils.indent(name & ", view of " & $F & " of length " & $v.len, indent)
    for i in 0 ..< v.len:
      debugEcho strutils.indent(&"    {i:>2}: {v[i].toHex()}", indent)
    debugEcho strutils.indent(name & "  " & $F & " -- FIN\n", indent)

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