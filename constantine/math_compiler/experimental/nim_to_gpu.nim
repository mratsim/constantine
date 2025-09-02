# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import std / [macros, strutils, sequtils, options, sugar, tables, strformat, hashes, sets]

import ./gpu_types
import ./backends/backends

proc nimToGpuType(n: NimNode, allowToFail: bool = false, allowArrayIdent: bool = false): GpuType

proc initGpuType(kind: GpuTypeKind): GpuType =
  ## If `kind` is `gtPtr` `to` must be the type we point to
  if kind in [gtObject, gtPtr, gtArray]: raiseAssert "Objects/Pointers/Arrays must be constructed using `initGpuPtr/Object/ArrayType` "
  result = GpuType(kind: kind)

proc initGpuPtrType(to: GpuType, implicitPtr: bool): GpuType =
  ## If `kind` is `gtPtr` `to` must be the type we point to
  if to.kind == gtInvalid: # this is not a valid type
    result = GpuType(kind: gtInvalid)
  else:
    result = GpuType(kind: gtPtr, to: to, implicit: implicitPtr)

proc initGpuUAType(to: GpuType): GpuType =
  ## Initializes a GPU type for an unchecked array (ptr wraps this)
  if to.kind == gtInvalid: # this is not a valid type
    result = GpuType(kind: gtInvalid)
  else:
    result = GpuType(kind: gtUA, uaTo: to)

proc initGpuVoidPtr(): GpuType =
  result = GpuType(kind: gtVoidPtr)

proc initGpuObjectType(name: string, flds: seq[GpuTypeField]): GpuType =
  ## If `kind` is `gtPtr` `to` must be the type we point to
  result = GpuType(kind: gtObject, name: name, oFields: flds)

proc initGpuArrayType(aTyp: NimNode, len: int): GpuType =
  ## Construct an statically sized array type
  result = GpuType(kind: gtArray, aTyp: nimToGpuType(aTyp), aLen: len)

proc toTypeDef(typ: GpuType): GpuAst =
  ## Converts a given object or generic instantiation type into an AST of a
  ## corresponding type def.
  # store the type instantiation
  result = GpuAst(kind: gpuTypeDef, tTyp: typ)
  case typ.kind
  of gtObject:      result.tFields = typ.oFields
  of gtGenericInst: result.tFields = typ.gFields
  else:
    raiseAssert "Type: " & $pretty(typ) & " is neither object type nor generic instantiation."

proc toGpuTypeKind(t: NimTypeKind): GpuTypeKind =
  case t
  #of ntyBool, ntyChar:
    # , ntyEmpty, ntyAlias, ntyNil, ntyExpr, ntyStmt, ntyTypeDesc, ntyGenericInvocation, ntyGenericBody, ntyGenericInst, ntyGenericParam, ntyDistinct, ntyEnum, ntyOrdinal, ntyArray, ntyObject, ntyTuple, ntySet, ntyRange, ntyPtr, ntyRef, ntyVar, ntySequence, ntyProc,
  #of ntyPointer, ntyUncheckedArray, ntyOpenArray, ntyString, ntyCString
  # , ntyForward, ntyInt, ntyInt8,
  of ntyBool: gtBool
  of ntyInt16: gtInt16
  of ntyInt32: gtInt32
  of ntyInt64: gtInt64
  of ntyInt:   gtInt32 # `int` is always mapped to `int32` as that is the more "native" type on GPUs
  of ntyFloat: gtFloat64
  of ntyFloat32: gtFloat32
  of ntyFloat64: gtFloat64
  #of ntyFloat128: gtFloat128
  of ntyUInt: gtUint64
  of ntyUInt8: gtUint8
  of ntyUInt16: gtUint16
  of ntyUInt32: gtUint32
  of ntyUInt64: gtUint64
  of ntyString: gtString
  else:
    raiseAssert "Not supported yet: " & $t

proc parseTypeFields(node: NimNode): seq[GpuTypeField]
proc initGpuGenericInst(t: NimNode): GpuType =
  doAssert t.typeKind == ntyGenericInst, "Input is not a generic instantiation: " & $t.treerepr & " of typeKind: " & $t.typeKind
  case t.kind
  of nnkBracketExpr: # regular generic instantiation
    result = GpuType(kind: gtGenericInst, gName: t[0].repr)
    for i in 1 ..< t.len: # grab all generic arguments
      let typ = nimToGpuType(t[i])
      result.gArgs.add typ
    # now parse the object fields
    let impl = t.getTypeImpl() # impl for the `gFields`
    result.gFields = parseTypeFields(impl)
  of nnkObjConstr:
    doAssert t.len == 1, "Unexpected length of ObjConstr node: " & $t.len & " of node: " & $t.treerepr
    result = initGpuGenericInst(t[0])
  of nnkSym:
    let impl = getTypeImpl(t)
    case impl.kind
    of nnkDistinctTy:
      ## XXX: assumes distinct of inbuilt type, not object!
      result = nimToGpuType(impl[0])
    of nnkObjectTy:
      doAssert impl.kind == nnkObjectTy, "Unexpected node kind for generic inst: " & $impl.treerepr
      ## XXX: use signature hash for type name? Otherwise will produce duplicates
      result = GpuType(kind: gtGenericInst, gName: t.repr)
      result.gFields = parseTypeFields(impl)
    else:
      raiseAssert "Unexpected node kind in for genericInst: " & $t.treerepr
  else:
    raiseAssert "Unexpected node kind in for genericInst: " & $t.treerepr

proc unpackGenericInst(t: NimNode): NimNode =
  let tKind = t.typeKind
  if tKind == ntyGenericInst:
    let impl = t.getTypeImpl()
    case impl.kind
    of nnkDistinctTy: # just skip the distinct
      result = impl[0]
    else:
      raiseAssert "Unsupport type so far: " & $t.treerepr & " of impl: " & $impl.treerepr
  else:
    result = t

proc toGpuTypeKind(t: NimNode): GpuTypeKind =
  result = t.unpackGenericInst().typeKind.toGpuTypeKind()

proc getInnerPointerType(n: NimNode, allowToFail: bool = false, allowArrayIdent: bool = false): GpuType =
  doAssert n.typeKind in {ntyPtr, ntyPointer, ntyUncheckedArray, ntyVar} or n.kind == nnkPtrTy, "But was: " & $n.treerepr & " of typeKind " & $n.typeKind
  if n.typeKind in {ntyPointer, ntyUncheckedArray}:
    let typ = n.getTypeInst()
    doAssert typ.kind == nnkBracketExpr, "No, was: " & $typ.treerepr
    doAssert typ[0].kind in {nnkIdent, nnkSym}
    doAssert typ[0].strVal in ["ptr", "UncheckedArray"]
    result = nimToGpuType(typ[1], allowToFail, allowArrayIdent)
  elif n.kind == nnkPtrTy:
    result = nimToGpuType(n[0], allowToFail, allowArrayIdent)
  elif n.kind == nnkAddr:
    let typ = n.getTypeInst()
    result = getInnerPointerType(typ, allowToFail, allowArrayIdent)
  elif n.kind == nnkVarTy:
    # VarTy
    #   Sym "BigInt"
    result = nimToGpuType(n[0], allowToFail, allowArrayIdent)
  elif n.kind == nnkSym: # symbol of e.g. `ntyVar`
    result = nimToGpuType(n.getTypeInst(), allowToFail, allowArrayIdent)
  else:
    raiseAssert "Found what: " & $n.treerepr

proc determineArrayLength(n: NimNode, allowArrayIdent: bool): int =
  ## If `allowArrayIdent` is true, we do not emit the error message when
  ## encountering an ident. This is the case for procs taking arrays
  ## with a static array where the constant comes from outside the
  ## macro. In that case we return `-1` indicating
  ##  `proc mdsRowShfNaive(r: int, v: array[SPONGE_WIDTH, BigInt]): BigInt {.device.} =`
  case n[1].kind
  of nnkSym:
    # likely a constant, try to get its value
    result = n[1].getImpl.intVal
  of nnkIdent:
    if not allowArrayIdent:
      let msg = """Found array with length given by identifier: $#!
You might want to create a typed template taking a typed parameter for this
constant to force the Nim compiler to bind the symbol. In theory though this
error should not appear anymore though, as we don't try to parse generic
functions.
""" % n[1].strVal
      raiseAssert msg
    else:
      result = -1 # return -1 to indicate caller should look at symbol
  else:
    case n[1].kind
    of nnkIntLit: result = n[1].intVal
    else:
      # E.g.
      # BracketExpr
      #   Sym "array"
      #   Infix
      #     Ident ".."
      #     IntLit 0
      #     IntLit 11
      #   Sym "BigInt"
      #doAssert n[1].kind == nnkIntLit, "No is: " & $n.treerepr
      doAssert n[1].kind == nnkInfix, "No is: " & $n.treerepr
      doAssert n[1][1].kind == nnkIntLit, "No is: " & $n.treerepr
      doAssert n[1][1].intVal == 0, "No is: " & $n.treerepr
      result = n[1][2].intVal + 1

proc getTypeName(n: NimNode, recursedSym: bool = false): string
proc constructTupleTypeName(n: NimNode): string =
  ## XXX: overthink if this should really be here and not somewhere else
  ##
  ## Given a tuple, generate a name from the field names and types, e.g.
  ## `Tuple_lo_BaseType_hi_BaseType`
  ##
  ## XXX: `getTypeImpl.repr` is a hacky way to get a string name of the underlying
  ## type, e.g. for `BaseType`. Aliases would lead to duplicate tuple types.
  ## UPDATE: I changed the implementation to recurse into `getTypeName`
  ## TODO: verify that this did not break the tuple test & specifically check for aliases
  result = "Tuple_"
  doAssert n.kind in [nnkTupleTy, nnkTupleConstr]
  for i, ch in n:
    case ch.kind
    of nnkIdentDefs:
      let typName = ch[ch.len - 2].getTypeName() # second to last is type name of field(s)
      for j in 0 ..< ch.len - 2:
        # Example:
        # IdentDefs
        #   Ident "hi"
        #   Ident "lo"      `..< ch.len - 2 `
        #   Sym "BaseType"  `..< ch.len - 1`
        #   Empty           `..< ch.len`
        result.add ch[j].strVal & "_" & typName
        if j < ch.len - 3:
          result.add "_"
      if i < n.len - 1:
        result.add "_"
    of nnkExprColonExpr:
      # ExprColonExpr
      #   Sym "hi"
      #   Infix
      #     Sym "shr"
      #     Sym "n"
      #     IntLit 16
      # -> these are tuple types that are constructed in place using `(foo: bar, ar: br)`
      #    give them a slightly different name
      let typName = ch[0].getTypeName() ## XXX
      doAssert ch[0].kind == nnkSym, "Not a symbol, but: " & $ch.treerepr
      result.add ch[0].strVal & "_" & typName
      if i < n.len - 1:
        result.add "_"
    of nnkSym:
      # TupleConstr
      #   Sym "BaseType" <-- e.g. here
      #   Sym "BaseType"
      let typName = ch.getTypeName()
      result.add "Field" & $i & "_" & typName
      if i < n.len - 1:
        result.add "_"
    else:
      # TupleConstr      e.g. a tuple constr like this
      #   Infix
      #     Sym "shr"
      #     Sym "n"
      #     IntLit 16
      #   Infix
      #     Sym "and"
      #     Sym "n"
      #     UInt32Lit 65535
      # -> Try again with type impl
      return constructTupleTypeName(getTypeImpl(n))

proc getTypeName(n: NimNode, recursedSym: bool = false): string =
  ## Returns the name of the type
  case n.kind
  of nnkIdent: result = n.strVal
  of nnkSym:
    if recursedSym:
      result = n.strVal
    else:
      result = n.getTypeInst.getTypeName(true)
  of nnkObjConstr:
    if n[0].kind == nnkEmpty:
      result = n.getTypeInst.strVal
    else:
      result = n[0].strVal # type is the first node
  of nnkTupleTy, nnkTupleConstr:
    result = constructTupleTypeName(n)
  of nnkBracketExpr:
    # construct a type name `Foo_Bar_Baz`
    for i, ch in n:
      result.add ch.getTypeName()
      if i < n.len - 1:
        result.add "_"
  else: raiseAssert "Unexpected node in `getTypeName`: " & $n.treerepr

proc nimToGpuType(n: NimNode, allowToFail: bool = false, allowArrayIdent: bool = false): GpuType =
  ## Maps a Nim type to a type on the GPU
  ##
  ## If `allowToFail` is `true`, we return `GpuType(kind: gtVoid)` in cases
  ## where we would otherwise raise. This is so that in some cases where
  ## we only _attempt_ to determine a type, we can do so safely.
  case n.kind
  of nnkIdentDefs: # extract type for let / var based on explicit or implicit type
    if n[n.len - 2].kind != nnkEmpty: # explicit type
      result = nimToGpuType(n[n.len - 2], allowToFail, allowArrayIdent)
    else: # take from last element
      result = nimToGpuType(n[n.len - 1].getTypeInst(), allowToFail, allowArrayIdent)
  of nnkConstDef:
    if n[1].kind != nnkEmpty: # has an explicit type
      result = nimToGpuType(n[1], allowToFail, allowArrayIdent)
    else:
      result = nimToGpuType(n[2], allowToFail, allowArrayIdent) # derive from the RHS literal
  else:
    if n.kind == nnkEmpty: return initGpuType(gtVoid)
    case n.typeKind
    of ntyBool, ntyInt .. ntyUint64: # includes all float types
      result = initGpuType(toGpuTypeKind n.typeKind)
    of ntyString: # only supported on some backends!
      result = initGpuType(toGpuTypeKind n.typeKind)
    of ntyPtr:
      result = initGpuPtrType(getInnerPointerType(n, allowToFail, allowArrayIdent), implicitPtr = false)
    of ntyVar:
      result = initGpuPtrType(getInnerPointerType(n, allowToFail, allowArrayIdent), implicitPtr = true)
    of ntyPointer:
      result = initGpuVoidPtr()
    of ntyUncheckedArray:
      ## Note: this is just the internal type of the array. It is only a pointer due to
      ## `ptr UncheckedArray[T]`. We simply remove the `UncheckedArray` part.
      result = initGpuUAType(getInnerPointerType(n, allowToFail, allowArrayIdent))
    of ntyObject, ntyAlias, ntyTuple:
      # for aliases, treat them identical to regular object types, but
      # `getTypeName` returns the alias!
      let impl = if n.kind == nnkTupleConstr: n # might actually _lose_ information if used getTypeImpl
                 else: n.getTypeImpl
      let flds = impl.parseTypeFields()
      let typName = getTypeName(n) # might be an object construction
      result = initGpuObjectType(typName, flds)
    of ntyArray:
      # For a generic, static array type, e.g.:
      if n.kind == nnkSym:
        return nimToGpuType(getTypeImpl(n), allowToFail, allowArrayIdent)
      if n.len == 3:
        # BracketExpr
        #   Sym "array"
        #   Ident "N"
        #   Sym "uint32"
        doAssert n.len == 3, "Length was not 3, but: " & $n.len & " for node: " & n.treerepr
        doAssert n[0].strVal == "array"
        let len = determineArrayLength(n, allowArrayIdent)
        if len < 0:
          # indicates we found an array with an ident, e.g.
          # BracketExpr
          #   Sym "array"
          #   Ident "SPONGE_WIDTH"
          #   Sym "BigInt"
          return GpuType(kind: gtInvalid)
        else:
          result = initGpuArrayType(n[2], len)
      else:
        # just an array literal
        # Bracket
        #   UIntLit 2013265921
        let len = n.len
        result = initGpuArrayType(n[0], len)
    #of ntyCompositeTypeClass:
    #  echo n.getTypeImpl.treerepr
    #  error("o")
    of ntyGenericInvocation:
      result = initGpuType(gtInvalid)
      error("Generics are not supported in the CUDA DSL so far.") # Note: this should not appear nowadays
    of ntyGenericInst:
      result = initGpuGenericInst(n)
    of ntyTypeDesc:
      # `getType` returns a `BracketExpr` of eg:
      # BracketExpr
      #   Sym "typeDesc"
      #   Sym "float32"
      result = n.getType[1].nimToGpuType(allowToFail, allowArrayIdent) # for a type desc we need to recurse using the type of it
    of ntyUnused2:
      # BracketExpr
      #   Sym "lent"
      #   Sym "BigInt"
      doAssert n.kind == nnkBracketExpr and n[0].strVal == "lent", "ntyUnused2: " & $n.treerepr
      result = initGpuPtrType(nimToGpuType(n[1]), implicitPtr = false)
    else:
      if allowToFail:
        result = GpuType(kind: gtVoid)
      else:
        raiseAssert "Type : " & $n.typeKind & " not supported yet: " & $n.treerepr

proc assignOp(op: string, isBoolean: bool): string =
  ## Returns the correct CUDA operation given the Nim operator.
  ## This is to replace things like `shl`, `div` or `mod`
  case op
  of "div": result = "/"
  of "mod": result = "%"
  of "shl": result = "<<"
  of "shr": result = ">>"
  of "and": result = if isBoolean: "&&" else: "&" # bitwise OR
  of "or":  result = if isBoolean: "||" else: "|" # bitwise OR
  of "xor": result = "^"
  else: result = op

proc assignPrefixOp(op: string): string =
  ## Returns the correct CUDA operation given the Nim operator.
  case op
  of "not": result = "!"
  else: result = op

proc parseTypeFields(node: NimNode): seq[GpuTypeField] =
  case node.kind
  of nnkObjectTy:
    doAssert node[2].kind == nnkRecList
    for ch in node[2]:
      doAssert ch.kind == nnkIdentDefs and ch.len == 3
      result.add GpuTypeField(name: ch[0].strVal,
                              typ: nimToGpuType(ch[1]))
  of nnkTupleTy:
    for ch in node:
      doAssert ch.kind == nnkIdentDefs and ch.len == 3
      result.add GpuTypeField(name: ch[0].strVal,
                              typ: nimToGpuType(ch[1]))
  of nnkTupleConstr:
    # TupleConstr
    #   Sym "BaseType"
    #   Sym "BaseType"
    for i, ch in node:
      case ch.kind
      of nnkSym:
        result.add GpuTypeField(name: "Field" & $i,
                                typ: nimToGpuType(ch))
      of nnkExprColonExpr:
        result.add GpuTypeField(name: ch[0].strVal,
                                typ: nimToGpuType(ch[1]))
      else:
        return parseTypeFields(node.getTypeImpl) # will likely fall back to constr with `nnkSym`
  else:
    raiseAssert "Unsupported type to parse fields from: " & $node.kind

template findIdx(col, el): untyped =
  var res = -1
  for i, it in col:
    if it.name == el:
      res = i
      break
  res

proc ensureBlock(ast: GpuAst): GpuAst =
  ## Ensures the body is a block, e.g. if single statement in a for loop, we want the
  ## body to be a block regardless.
  if ast.kind == gpuBlock: ast
  else: GpuAst(kind: gpuBlock, statements: @[ast])

proc requiresMemcpy(n: NimNode): bool =
  ## At the moment we only emit a `memcpy` statement for array types
  result = n.typeKind == ntyArray and n.kind != nnkBracket # need to emit a memcpy

proc isBuiltIn(n: NimNode): bool =
  ## Checks if the given proc is a `{.builtin.}` (or if it is a Nim "built in"
  ## proc that uses `importc`, as we cannot emit those; they _need_ to have a
  ## WGSL / CUDA equivalent built in)
  doAssert n.kind in [nnkProcDef, nnkFuncDef], "Argument is not a proc: " & $n.treerepr
  for pragma in n.pragma:
    doAssert pragma.kind in [nnkIdent, nnkSym, nnkCall, nnkExprColonExpr], "Unexpected node kind: " & $pragma.treerepr
    let pragma = if pragma.kind in [nnkCall, nnkExprColonExpr]: pragma[0] else: pragma
    if pragma.strVal in ["builtin", "importc"]:
      return true

proc collectProcAttributes(n: NimNode): set[GpuAttribute] =
  doAssert n.kind in [nnkPragma, nnkEmpty]
  if n.kind == nnkEmpty: return # no pragmas
  for pragma in n:
    doAssert pragma.kind in [nnkIdent, nnkSym, nnkCall, nnkExprColonExpr], "Unexpected node kind: " & $pragma.treerepr
    let pragma = if pragma.kind in [nnkCall, nnkExprColonExpr]: pragma[0] else: pragma
    case pragma.strVal
    of "device": result.incl attDevice
    of "global": result.incl attGlobal
    of "inline", "forceinline": result.incl attForceInline
    of "nimonly", "builtin":
      # used to fully ignore functions!
      return
    of "importc": # encountered if we analyze a proc from outside `cuda` scope
      return # this _should_ be a builtin function that has a counterpart in Nim, e.g. `math.ceil`
    of "varargs": # attached to some builtins, e.g. `printf` on CUDA backend
      continue
    of "magic":
      return
    of "raises": discard # result.incl attDevice #discard # XXX
    else:
      raiseAssert "Unexpected pragma for procs: " & $pragma.treerepr

proc collectAttributes(n: NimNode): seq[GpuVarAttribute] =
  ## Collects all pragmas associated with the given variable.
  ## Takes the `nnkPragma` node of the `nnkIdentDefs` associated with it.
  # Example AST with multiple pragmas
  # IdentDefs
  #   PragmaExpr
  #     Sym "sharedMem"
  #     Pragma
  #       Sym "cuExtern"
  #       Sym "shared"
  #   BracketExpr
  #     Sym "array"
  #     IntLit 0
  #     Sym "BigInt"
  #   Empty
  doAssert n.kind == nnkPragma
  for pragma in n:
    doAssert pragma.kind in [nnkIdent, nnkSym], "Unexpected node kind: " & $pragma.treerepr
    # NOTE: We don't use `parseEnum`, because on the Nim side some of the attributes
    # do not match the CUDA string we need to emit, which is what the string value of
    # the `GpuVarAttribute` enum stores
    case pragma.strVal.normalize
    of "cuextern", "extern": result.add atvExtern
    of "shared": result.add atvShared
    of "private": result.add atvPrivate
    of "volatile": result.add atvVolatile
    of "constant": result.add atvConstant
    of "noinit": discard # XXX: ignore for now
    else:
      raiseAssert "Unexpected pragma: " & $pragma.treerepr

proc toGpuAst*(ctx: var GpuContext, node: NimNode): GpuAst

proc maybePatchFnName(n: var GpuAst) =
  ## Patches the function name for names that are not allowed on most backends, but appear
  ## commonly in Nim (custom operators).
  ##
  ## NOTE: I think that the binary operators don't actually appear as a `gpuCall`, but still
  ## as an infix node, even after sem checking by the Nim compiler.
  doAssert n.kind == gpuIdent
  template patch(arg, by: untyped): untyped =
    arg.iSym = arg.iSym.replace(arg.iName, by)
    arg.iName = by
  let name = n.iName
  case name
  of "[]":  patch(n, "get")
  of "[]=": patch(n, "set")
  of "+":   patch(n, "add")
  of "-":   patch(n, "sub")
  of "*":   patch(n, "mul")
  of "/":   patch(n, "div")
  else:
    # leave as is
    discard

proc getFnName(ctx: var GpuContext, n: NimNode): GpuAst =
  ## Returns the name for the function. Either the symbol name _or_
  ## the `{.cudaName.}` pragma argument.
  template toAst(fn): untyped = GpuAst(kind: gpuIdent, iName: fn, symbolKind: gsProc)
  # check if the implementation has a pragma

  if n.kind == nnkSym:
    # Check if `cudaName` pragma used:
    # ProcDef
    #   Sym "syncthreads"
    #   Empty
    #   Empty
    #   FormalParams
    #     Empty
    #   Pragma
    #     ExprColonExpr
    #       Sym "cudaName"           <- if this exists
    #       StrLit "__syncthreads"   <- use this name
    #   Empty
    #   DiscardStmt
    #     Empty
    let sig = n.repr & "_" & n.signatureHash()
    if sig in ctx.sigTab:
      result = ctx.sigTab[sig]
    else:
      let impl = n.getImpl
      if impl.kind in [nnkProcDef, nnkFuncDef]:
        let pragma = impl.pragma
        if pragma.kind != nnkEmpty and pragma[0].kind == nnkExprColonExpr:
          if pragma[0][0].kind in [nnkIdent, nnkSym] and pragma[0][0].strVal == "cudaName":
            # want to replace fn name
            result = toAst pragma[0][1].strVal
            ctx.sigTab[sig] = result
          else:
            result = ctx.toGpuAst(n) # if no `cudaName` pragma
        else:
          result = ctx.toGpuAst(n) # if _no_ pragma
      else:
        result = ctx.toGpuAst(n) # if not proc or func

      # possibly patch function names, e.g. custom `[]`, `[]=`, `+` etc operators
      # (inbuilt won't show up as a function name, but rather as a specific node kind, eg `nnkIndex`
      result.maybePatchFnName()

      # handle overloads with different signatures
      if n.strVal in ctx.symChoices:
        # this is an overload of another function with different signature (not a generic, but
        # overloads are not allowed in CUDA/WGSL/...). Update `sigTab` entry by using `iSym`
        # for `iName` field for unique name
        let id = ctx.sigTab[sig]
        id.iName = id.iSym
      else:
        ctx.symChoices.incl result.iName # store this name in `symChoices`
  else:
    # else we use the str representation (repr for open / closed sym choice nodes)
    result = toAst n.repr
    #raiseAssert "This fn identifier is not a symbol?! " & $n.repr
    # If it's not a symbol, there is no signature associated
    # ctx.sigTab[sig] = result
  result.symbolKind = gsProc # make sure it's a proc

proc gpuTypeMaybeFromSymbol(t: NimNode, n: NimNode): GpuType =
  ## Returns the type from a given Nim node `t` representing a type.
  ## If that fails due to an identifier in the type, we instead try
  ## to look up the type from the associated symbol, `n`.
  result = nimToGpuType(t, allowArrayIdent = true)
  if result.kind == gtInvalid:
    # an existing symbol cannot be `void` by definition, then it wouldn't be a symbol. Means
    # `allowArrayIdent` triggered due to an ident in the type. Use symbol for type instead
    result = n.getTypeInst.nimToGpuType()

proc maybeAddType*(ctx: var GpuContext, typ: GpuType) =
  ## Adds the given type to the table of known types, if it is some kind of
  ## object type.
  ##
  ## XXX: What about aliases and distincts?
  if typ.kind in [gtObject, gtGenericInst] and typ notin ctx.types:
    ctx.types[typ] = toTypeDef(typ)

proc parseProcParameters(ctx: var GpuContext, params: NimNode, attrs: set[GpuAttribute]): seq[GpuParam] =
  ## Returns all parameters of the given procedure from the `params` node
  ## of type `nnkFormalParams`.
  doAssert params.kind == nnkFormalParams, "Argument is not FormalParams, but: " & $params.treerepr
  for i in 1 ..< params.len:
    let param = params[i]
    let numParams = param.len - 2 # 3 if one param, one more for each of same type, example:
    let typIdx = param.len - 2 # second to last is the type
    # IdentDefs
    #   Ident "x"
    #   Ident "y"
    #   Ident "res"
    #   PtrTy
    #     Ident "float32"   # `param.len - 2`
    #   Empty               # `param.len - 1`
    let paramType = gpuTypeMaybeFromSymbol(param[typIdx], param[typIdx-1])
    ctx.maybeAddType(paramType)
    for i in 0 ..< numParams:
      var p = ctx.toGpuAst(param[i])
      let symKind = if attGlobal in attrs: gsGlobalKernelParam
                    else: gsDeviceKernelParam
      p.iTyp = paramType     ## Update the type of the symbol
      p.symbolKind = symKind ## and the symbol kind
      let param = GpuParam(ident: p, typ: paramType)
      result.add(param)

proc parseProcReturnType(ctx: var GpuContext, params: NimNode): GpuType =
  ## Returns the return type of the given procedure from the `params` node
  ## of type `nnkFormalParams`.
  doAssert params.kind == nnkFormalParams, "Argument is not FormalParams, but: " & $params.treerepr
  let retType = params[0] # arg 0 is return type
  if retType.kind == nnkEmpty:
    result = GpuType(kind: gtVoid) # actual void return
  else:
    # attempt to get type. If fails, we need to wait for a caller to this function to get types
    # (e.g. returns something like `array[FOO, BigInt]` where `FOO` is a constant defined outside
    # the macro. We then rely on our generics logic to later look this up when called
    result = nimToGpuType(retType, allowArrayIdent = true)
    if result.kind == gtVoid: # stop parsing this function
      result = GpuType(kind: gtInvalid)
  ctx.maybeAddType(result)

proc toGpuProcSignature(ctx: var GpuContext, params: NimNode, attrs: set[GpuAttribute]): GpuProcSignature =
  ## Creates a `GpuProcSignature` from the given `params` node of type `nnkFormalParams`

  ##
  ## NOTE: This procedure is only called from generically instantiated procs. Therefore,
  ## we shouldn't need to worry about getting `gtInvalid` return types here.
  doAssert params.kind == nnkFormalParams, "Argument is not FormalParams, but: " & $params.treerepr
  result = GpuProcSignature(params: ctx.parseProcParameters(params, attrs),
                            retType: ctx.parseProcReturnType(params))

proc addProcToGenericInsts(ctx: var GpuContext, node: NimNode, name: GpuAst) =
  ## Looks up the implementation of the given function and stores it in our table
  ## of generic instantiations.
  ##
  ## For any looked up procedure, we attach the `{.device.}` pragma.
  ##
  ## Mutates the `name` of the given function to match its generic name.
  # We need both `getImpl` for the *body* and `getTypeInst` for the actual signature
  # Only the latter contains e.g. correct instantiation of static array sizes
  let inst = node[0].getImpl()
  let sig = node[0].getTypeInst()
  inst.params = sig.params # copy over the parameters

  # turn the signature into a `GpuProcSignature`
  let attrs = collectProcAttributes(inst.pragma)
  let procSig = ctx.toGpuProcSignature(sig.params, attrs)
  if name in ctx.processedProcs:
    return
  else:
    # Need to add isym here so that if we have recursive calls, we don't end up
    # calling `toGpuAst` recursively forever
    ctx.processedProcs[name] = procSig

  let fn = ctx.toGpuAst(inst)
  if fn.kind == gpuVoid:
    # Should be an inbuilt proc, i.e. annotated with `{.builtin.}`. However,
    # functions that are available otherwise (e.g. in Nim's system like `abs`)
    # in Nim _and_ backends will also show up here. Unless we wanted to manually
    # wrap all of these, we can just skip the `isBuiltin` check here.
    # If the user uses something not available in the backend, they'll get a
    # compiler error from that compiler.
    # It's mostly a matter of usability: For common procs like `abs` we cannot
    # so easily define a custom overload `proc abs(...): ... {.builtin.}`, because
    # that would overwrite the Nim version.
    # doAssert inst.isBuiltIn()
    return
  else:
    fn.pAttributes.incl attDevice # make sure this is interpreted as a device function
    doAssert fn.pName.iSym == name.iSym, "Not matching"
    # now overwrite the identifier's `iName` field by its `iSym` so that different
    # generic insts have different
    fn.pName.iName = fn.pName.iSym
    name.iName = fn.pName.iSym ## update the name of the called function
    ctx.genericInsts[fn.pName] = fn

proc isExpression(n: GpuAst): bool =
  ## Returns whether the given AST node is an expression
  case n.kind
  of gpuCall: # only if it returns something!
    result = n.cIsExpr
  of gpuBinOp, gpuIdent, gpuLit, gpuArrayLit, gpuPrefix, gpuDot, gpuIndex, gpuObjConstr,
     gpuAddr, gpuDeref, gpuConv, gpuCast, gpuConstExpr:
    result = true
  else:
    result = false

proc maybeInsertResult(ast: var GpuAst, retType: GpuType, fnName: string) =
  ## Will insert a `gpuVar` for the implicit `result` variable, unless there
  ## is a user defined `var result` that shadows it at the top level of the proc
  ## body.
  ##
  ## Finally adds a `return result` statement if
  ## - we add a `result` variable
  ## - there is no `return` statement as the _last_ statement in the proc
  if retType.kind == gtVoid: return # nothing to do if the proc returns nothing

  proc hasCustomResult(n: GpuAst): bool =
    doAssert n.kind == gpuBlock
    for ch in n: # iterate all top level statements in the proc body
      case ch.kind
      of gpuVar:
        if ch.vName.ident() == "result":
          ## XXX: could maybe consider to emit a CT warning that `result` shadows the implicit
          ## result variable
          echo "[WARNING] ", fnName, " has a custom `result` variable, which shadows the implicit `result`."
          return true
      of gpuBlock: # need to look at `gpuBlock` from top level, because variables are defined in a block
        result = result or hasCustomResult(ch)
      else:
        discard

  proc lastIsReturn(n: GpuAst): bool =
    doAssert n.kind == gpuBlock
    if n.statements[^1].kind == gpuReturn: return true

  if not hasCustomResult(ast) and not lastIsReturn(ast):
    # insert `gpuVar` as the *first* statement
    let resId = GpuAst(kind: gpuIdent, iName: "result",
                       iSym: "result",
                       iTyp: retType,
                       symbolKind: gsLocal)
    let res = GpuAst(kind: gpuVar, vName: resId,
                     vType: retType,
                     vInit: GpuAst(kind: gpuVoid), # no initialization
                     vRequiresMemcpy: false,
                     vMutable: true)
    ast.statements.insert(res, 0)
    # NOTE: The compiler rewrites expressions at the end of a `proc` into
    # an assignment to `block: result = <expression>` for us.
    if not lastIsReturn(ast):
      # insert `return result`
      ast.statements.add GpuAst(kind: gpuReturn, rValue: resId)

proc fnReturnsValue(ctx: GpuContext, fn: GpuAst): bool =
  ## Returns true if the given `fn` (gpuIdent) returns a value.
  ## The function can either be:
  ## - an inbuilt function
  ## - a generic instantiation
  ## - contained in `allFnTab`
  if fn in ctx.allFnTab:
    result = ctx.allFnTab[fn].pRetType.kind != gtVoid
  elif fn in ctx.genericInsts:
    result = ctx.genericInsts[fn].pRetType.kind != gtVoid
  elif fn in ctx.builtins:
    result = ctx.builtins[fn].pRetType.kind != gtVoid
  elif fn in ctx.processedProcs:
    result = ctx.processedProcs[fn].retType.kind != gtVoid
  else:
    raiseAssert "The function: " & $fn & " is not known anywhere."

proc toGpuAst*(ctx: var GpuContext, node: NimNode): GpuAst =
  ## XXX: things still left to do:
  ## - support `result` variable? Currently not supported. Maybe we will won't

  #echo node.treerepr
  case node.kind
  of nnkEmpty: result = GpuAst(kind: gpuVoid) # nothing to do
  of nnkStmtList:
    result = GpuAst(kind: gpuBlock)
    for el in node:
      result.statements.add ctx.toGpuAst(el)
  of nnkBlockStmt:
    # BlockStmt
    #   Sym "unrolledIter_i0"  <- ignore the block label for now!
    #   Call
    #     Sym "printf"
    #     StrLit "i = %u\n"
    #     IntLit 0
    let blockLabel = if node[0].kind in {nnkSym, nnkIdent}: node[0].strVal
                     elif node[0].kind == nnkEmpty: ""
                     else: raiseAssert "Unexpected node in block label field: " & $node.treerepr
    result = GpuAst(kind: gpuBlock,
                    blockLabel: blockLabel)
    for i in 1 ..< node.len: # index 0 is the block label
      result.statements.add ctx.toGpuAst(node[i])
  of nnkBlockExpr:
    ## XXX: For CUDA just a block?
    let blockLabel = if node[0].kind in {nnkSym, nnkIdent}: node[0].strVal
                     elif node[0].kind == nnkEmpty: ""
                     else: raiseAssert "Unexpected node in block label field: " & $node.treerepr
    result = GpuAst(kind: gpuBlock, blockLabel: blockLabel, isExpr: true)
    for el in node:
      if el.kind != nnkEmpty:
        result.statements.add ctx.toGpuAst(el)
  of nnkStmtListExpr: # for statements that return a value.
    ## XXX: For CUDA just a block?
    result = GpuAst(kind: gpuBlock, isExpr: true)
    for el in node:
      if el.kind != nnkEmpty:
        result.statements.add ctx.toGpuAst(el)
  of nnkDiscardStmt:
    # just process the child node if any
    result = ctx.toGpuAst(node[0])

  of nnkProcDef, nnkFuncDef:
    # if it is a _generic_ function, we don't actually process it here. instead we add it to
    # the `generics` set. When we encounter a `gpuCall` we will then check if the function
    # being called is part of the generic set and look up its _instantiated_ implementation
    # to parse it. The parsed generics are stored in the `genericInsts` table.
    let name = ctx.getFnName(node.name)
    if node[2].kind == nnkGenericParams: # is a generic
      ctx.generics.incl name.iName # need to use raw name, *not* symbol
      result = GpuAst(kind: gpuVoid)
    elif node.body.kind == nnkEmpty: # just a forward declaration
      result = GpuAst(kind: gpuVoid)
    else:
      result = GpuAst(kind: gpuProc)
      result.pName = name
      result.pName.symbolKind = gsProc ## This is a procedure identifier
      let params = node[3]
      doAssert params.kind == nnkFormalParams
      result.pRetType = ctx.parseProcReturnType(params)
      if result.pRetType.kind == gtInvalid:
        ctx.generics.incl name.iName # need to use raw name, *not* symbol
        return GpuAst(kind: gpuVoid)

      # Process pragmas
      if node.pragma.kind != nnkEmpty:
        doAssert node.pragma.len > 0, "Pragma kind non empty, but no pragma?"
        result.pAttributes = collectProcAttributes(node.pragma)
        if result.pAttributes.len == 0: # means `nimonly` was applied / is a `builtin`
          ctx.builtins[name] = result # store in builtins, so that we know if it returns a value when called
          return GpuAst(kind: gpuVoid)
      # Process parameters
      result.pParams = ctx.parseProcParameters(params, result.pAttributes)
      result.pBody = ctx.toGpuAst(node.body)
        .ensureBlock() # single line procs should be a block to generate `;`
      result.pBody.maybeInsertResult(result.pRetType, result.pName.ident())

      # Add to table of known functions
      if result.pName notin ctx.allFnTab:
        ctx.allFnTab[result.pName] = result

  of nnkLetSection, nnkVarSection:
    # For a section with multiple declarations, create a block
    result = GpuAst(kind: gpuBlock)
    for declaration in node:
      # Each declaration gets converted to a gpuVar
      var varNode = GpuAst(kind: gpuVar)
      case declaration[0].kind
      of nnkIdent, nnkSym:
        # IdentDefs               # declaration
        #   Sym "res"             # declaration[0]
        #   Sym "uint32"
        #   Empty
        varNode.vName = ctx.toGpuAst(declaration[0])
      of nnkPragmaExpr:
        # IdentDefs               # declaration
        #   PragmaExpr            # declaration[0]
        #     Sym "res"           # declaration[0][0]
        #     Pragma              # declaration[0][1]
        #       Ident "volatile"
        #   Sym "uint32"
        #   Empty
        varNode.vName = ctx.toGpuAst(declaration[0][0])
        doAssert declaration[0][1].kind == nnkPragma
        varNode.vAttributes = collectAttributes(declaration[0][1])
      else: raiseAssert "Unexpected node kind for variable: " & $declaration.treeRepr
      varNode.vType = gpuTypeMaybeFromSymbol(declaration, declaration[0])
      ctx.maybeAddType(varNode.vType)
      varNode.vName.iTyp = varNode.vType # also store the type in the symbol, for easier lookup later
      # This is a *local* variable (i.e. `function` address space on WGSL) unless it is
      # annotated with `{.shared.}` (-> `workspace` in WGSL)
      varNode.vName.symbolKind = if atvShared in varNode.vAttributes: gsShared
                                 elif atvPrivate in varNode.vAttributes: gsPrivate
                                 else: gsLocal
      varNode.vMutable = node.kind == nnkVarSection
      ## XXX: handle initialization for array types. Need a memcpy!
      ## In principle should be straightforward. Turn e.g.
      ## ```nim
      ## let someData: array[8, uint32] = foo()
      ## let x = BigInt(limbs: someData)
      ## ```
      ## into
      ## ```cuda
      ## unsigned int someData[8] = foo();
      ## BigInt x = {{}};
      ## memcpy((&x.limbs), (&someData), sizeof(unsigned int) * 8);
      ## ```
      ## Or something along those lines.
      if declaration.len > 2 and declaration[2].kind != nnkEmpty:  # Has initialization
        varNode.vInit = ctx.toGpuAst(declaration[2])
        varNode.vRequiresMemcpy = requiresMemcpy(declaration[2])
      else:
        varNode.vInit = ctx.toGpuAst(declaration[2])
      result.statements.add(varNode)

  of nnkAsgn:
    result = GpuAst(kind: gpuAssign)
    result.aLeft = ctx.toGpuAst(node[0])
    result.aRight = ctx.toGpuAst(node[1])
    result.aRequiresMemcpy = requiresMemcpy(node[1])

  of nnkIfStmt:
    result = GpuAst(kind: gpuIf)
    let branch = node[0]  # First branch
    result.ifCond = ctx.toGpuAst(branch[0])
    result.ifThen = ensureBlock ctx.toGpuAst(branch[1])
    if node.len > 1 and node[^1].kind == nnkElse:
      result.ifElse = ensureBlock ctx.toGpuAst(node[^1][0])
    else:
      result.ifElse = GpuAst(kind: gpuVoid)

  of nnkForStmt:
    result = GpuAst(kind: gpuFor)
    doAssert node[0].kind in {nnkIdent, nnkSym}, "The variable in the for loop is not an identifier or symbol, but: " & $node[0].treerepr
    result.fVar = ctx.toGpuAst(node[0])
    result.fVar.symbolKind = gsLocal
    result.fVar.iTyp = initGpuType(gtInt32) ## XXX: do not force this type
    # Assuming range expression
    result.fStart = ctx.toGpuAst(node[1][1])
    result.fEnd = ctx.toGpuAst(node[1][2])
    result.fBody = ensureBlock ctx.toGpuAst(node[2])
  of nnkWhileStmt:
    result = GpuAst(kind: gpuWhile)
    result.wCond = ctx.toGpuAst(node[0]) # the condition
    result.wBody = ensureBlock ctx.toGpuAst(node[1])

  of nnkTemplateDef:
    ## NOTE: Currently we process templates, but we expect them to be already
    ## expanded by the Nim compiler. Thus we could in theory expand them manually
    ## but fortunately we don't need to.
    return GpuAst(kind: gpuVoid)
    let tName = node[0].strVal

    # Extract parameters
    var tParams = newSeq[string]()
    for i in 1 ..< node[3].len:
      let param = node[3][i]
      tParams.add param[0].strVal
    # and the body
    let tBody = ctx.toGpuAst(node.body)

    # Store template in context
    ctx.templates[tName] = TemplateInfo(
      params: tParams,
      body: tBody
    )

    result = GpuAst(kind: gpuVoid)

  of nnkCall, nnkCommand:
    # `name` below is name + signature hash. Check if this is a generic based on node repr
    let name = ctx.getFnName(node[0]) # cannot use `strVal`, might be a symchoice
    if node[0].repr in ctx.generics or name notin ctx.allFnTab:
      # process the generic instantiaton and store *or* pull in a proc defined outside
      # the `cuda` macro by its implementation.
      ## XXX: for CUDA backend need to annotate all pulled in procs with `{.device.}`!
      ctx.addProcToGenericInsts(node, name)

    let args = node[1..^1].mapIt(ctx.toGpuAst(it))
    # Producing a template call something like this (but problematic due to overloads etc)
    # we could then perform manual replacement of the template in the CUDA generation pass.
    if false: #  name in ctx.templates: #
      result = GpuAst(kind: gpuTemplateCall)
      result.tcName = name
      result.tcArgs = args
    else:
      let fnIsExpr = ctx.fnReturnsValue(name)
      result = GpuAst(kind: gpuCall, cIsExpr: fnIsExpr)
      result.cName = name
      result.cArgs = args

  of nnkInfix:
    result = GpuAst(kind: gpuBinOp)
    # Using `getType` to get the types of the arguuments
    let typ = node[0].getTypeImpl() # e.g.
    doAssert typ.kind == nnkProcTy, "Infix node is not a proc but: " & $typ.treerepr
    # BracketExpr
    #   Sym "proc"
    #   Sym "int"  <- return type
    #   Sym "int"  <- left op type
    #   Sym "int"  <- right op type
    result.bLeftTyp = nimToGpuType(typ[0][1])
    result.bRightTyp = nimToGpuType(typ[0][2])
    # if either is not a base type (`gtBool .. gtSize_t`) we actually deal with a _function call_
    # instead of an binary operation. Will thus rewrite.
    proc ofBasicType(t: GpuType, allowPtrLhs: bool): bool =
      ## Determines if the given type is a basic POD type *or* a simple pointer to it.
      ## This is because some infix nodes, e.g. `x += y` will have LHS arguments that are
      ## `var T`, which appear as an implicit pointer here.
      ##
      ## TODO: Handle the case of backend inbuilt special types (like `vec3`), which may indeed
      ## have inbuilt infix operators. Either by checking if the type has a `{.builtin.}` pragma
      ## _or_ if there is a wrapped proc for this operator and if so do not rewrite as `gpuCall`
      ## if that exists.
      result = (t.kind in gtBool .. gtSize_t)
      if allowPtrLhs:
        result = result or ((t.kind == gtPtr) and t.implicit and t.to.kind in gtBool .. gtSize_t)

    if not result.bLeftTyp.ofBasicType(true) or not result.bRightTyp.ofBasicType(false):
      result = GpuAst(kind: gpuCall)
      result.cName = ctx.getFnName(node[0])
      result.cArgs = @[ctx.toGpuAst(node[1]), ctx.toGpuAst(node[2])]
    else:
      # if left/right is boolean we need logical AND/OR, otherwise bitwise
      let isBoolean = result.bLeftTyp.kind == gtBool
      var op = GpuAst(kind: gpuIdent, iName: assignOp(node[0].repr, isBoolean)) # repr so that open sym choice gets correct name
      op.iSym = op.iName
      result.bOp = op
      result.bLeft = ctx.toGpuAst(node[1])
      result.bRight = ctx.toGpuAst(node[2])

      # We patch the types of int / float literals. WGSL does not automatically convert literals
      # to the target type. Determining the type here _can_ fail. In that case the
      # `lType` field will just be `gtVoid`, like the default.
      if result.bLeft.kind == gpuLit: # and result.bRight.kind != gpuLit:
        # determine literal type based on `bRight`
        result.bLeft.lType = result.bLeftTyp # nimToGpuType(node[2], allowToFail = true)
      elif result.bRight.kind == gpuLit: # and result.bLeft.kind != gpuLit:
        # determine literal type based on `bLeft`
        result.bRight.lType = result.bRightTyp #nimToGpuType(node[1], allowToFail = true)

  of nnkDotExpr:
    ## NOTE: As we use a typed macro, we only encounter `DotExpr` for *actual* field accesses and NOT
    ## for calls using method call syntax without parens
    result = GpuAst(kind: gpuDot)
    result.dParent = ctx.toGpuAst(node[0])
    result.dField = ctx.toGpuAst(node[1])

  of nnkBracketExpr:
    case node[0].typeKind
    of ntyTuple:
      # need to replace `[idx]` by field access
      let typ = nimToGpuType(node[0].getTypeImpl)
      ctx.maybeAddType(typ)
      #doAssert typ in ctx.types
      doAssert node[1].kind == nnkIntLit
      let idx = node[1].intVal
      let field = typ.oFields[idx].name
      result = GpuAst(kind: gpuDot,
                      dParent: ctx.toGpuAst(node[0]),
                      dField: ctx.toGpuAst(ident(field)))
    else:
      result = GpuAst(kind: gpuIndex)
      result.iArr = ctx.toGpuAst(node[0])
      result.iIndex = ctx.toGpuAst(node[1])

  of nnkIdent, nnkOpenSymChoice:
    result = newGpuIdent()
    result.iName = node.repr # for sym choices
    if result.iName == "_":
      result.iName = "tmp_" & $ctx.genSymCount
      inc ctx.genSymCount
  of nnkSym:
    let s = node.repr & "_" & node.signatureHash()
    # NOTE: The reason we have a tab of known symbols is not to keep the same _reference_ to each
    # symbol, but rather to allow having the same symbol kind and appropriate type for each
    # symbol `GpuAst` (of kind `gpuIdent`), which is set in the caller of this call.
    # For example in `nnkCall` nodes returning the value from the table automatically means the
    # `symbolKind` is local / function argument etc.
    if s notin ctx.sigTab:
      result = newGpuIdent()
      result.iName = node.repr
      result.iSym = s
      if result.iName == "_":
        result.iName = "tmp_" & $ctx.genSymCount
        inc ctx.genSymCount
      ctx.sigTab[s] = result
    else:
      result = ctx.sigTab[s]

  # literal types
  of nnkIntLit, nnkInt32Lit:
    result = GpuAst(kind: gpuLit)
    result.lValue = $node.intVal
    result.lType = initGpuType(gtInt32)
  of nnkUInt32Lit:
    result = GpuAst(kind: gpuLit)
    result.lValue = $node.intVal
    result.lType = initGpuType(gtUInt32)
  of nnkUIntLit:
    result = GpuAst(kind: gpuLit)
    result.lValue = $node.intVal
    result.lType = initGpuType(gtUInt64) ## XXX: base on target platform!
  of nnkFloat64Lit, nnkFloatLit:
    result = GpuAst(kind: gpuLit)
    result.lValue = $node.floatVal & "f"
    result.lType = initGpuType(gtFloat64)
  of nnkFloat32Lit:
    result = GpuAst(kind: gpuLit)
    result.lValue = $node.floatVal & "f"
    result.lType = initGpuType(gtFloat32)
  of nnkRStrLit:
    result = GpuAst(kind: gpuLit)
    result.lValue = node.strVal
    result.lType = initGpuType(gtString)
  of nnkStrLit:
    # For regular string literals escape them (but don't prefix/suffix with `"`)
    result = GpuAst(kind: gpuLit)
    result.lValue = node.strVal.escape("", "")
    result.lType = initGpuType(gtString)
  of nnkNilLit:
    result = GpuAst(kind: gpuLit)
    result.lValue = "NULL"
    result.lType = initGpuVoidPtr()

  of nnkPar:
    if node.len == 1: # just take body
      result = ctx.toGpuAst(node[0])
    else:
      error("`nnkPar` with more than one argument currently not supported. Got: " & $node.treerepr)

  of nnkReturnStmt:
    if node[0].kind == nnkAsgn and node[0][0].strVal == "result":
      # skip the result and just get the RHS
      result = GpuAst(kind: gpuReturn,
                      rValue: ctx.toGpuAst(node[0][1]))
    else:
      result = GpuAst(kind: gpuReturn,
                      rValue: ctx.toGpuAst(node[0]))

  of nnkPrefix:
    result = GpuAst(kind: gpuPrefix,
                    pVal: ctx.toGpuAst(node[1]))
    result.pOp = assignPrefixOp(node[0].strVal)

  of nnkTypeSection:
    result = GpuAst(kind: gpuBlock)
    for el in node: # walk each type def
      doAssert el.kind == nnkTypeDef
      result.statements.add ctx.toGpuAst(el)
  of nnkTypeDef:
    doAssert node.len == 3, "TypeDef node does not have 3 children: " & $node.len
    let name = ctx.toGpuAst(node[0])
    if node[1].kind == nnkGenericParams: # if this is a generic, only store existence of it
                                         # will store the instantiatons in `nnkObjConstr`
      result = GpuAst(kind: gpuVoid)
    else:
      let typ = nimToGpuType(node[0])
      case node[2].kind
      of nnkObjectTy: # regular `type foo = object`
        result = GpuAst(kind: gpuTypeDef, tTyp: typ)
        result.tFields = parseTypeFields(node[2])
      of nnkSym:      # a type alias `type foo = bar`
        result = GpuAst(kind: gpuAlias, aTyp: typ,
                        aTo: ctx.toGpuAst(node[2]))
      else:
        raiseAssert "Unexpected node kind in TypeDef: " & $node[2].kind

      # include this the set of known types to not generate duplicates
      ctx.types[typ] = result
      # Reset the type we return to void. We now generate _all_ types from the
      # `types`.
      result = GpuAst(kind: gpuVoid)
  of nnkObjConstr:
    ## this should never see `genericParam` I think
    let typ = nimToGpuType(node)
    ctx.maybeAddType(typ)
    result = GpuAst(kind: gpuObjConstr, ocType: typ)
    # get all fields of the type
    let flds = if typ.kind == gtObject: typ.oFields
               elif typ.kind == gtGenericInst: typ.gFields
               else: raiseAssert "ObjConstr must have an object type: " & $typ
    # find all fields that have been defined by the user
    var ocFields: seq[GpuFieldInit]
    for i in 1 ..< node.len: # all fields to be init'd
      doAssert node[i].kind == nnkExprColonExpr
      ocFields.add GpuFieldInit(name: node[i][0].strVal,
                                value: ctx.toGpuAst(node[i][1]),
                                typ: GpuType(kind: gtVoid))

    # now add fields in order of the type declaration
    for i in 0 ..< flds.len:
      let idx = findIdx(ocFields, flds[i].name)
      if idx >= 0:
        var f = ocFields[idx]
        f.typ = flds[i].typ
        result.ocFields.add f
      else:
        let dfl = GpuAst(kind: gpuLit, lValue: "DEFAULT", lType: GpuType(kind: gtVoid))
        result.ocFields.add GpuFieldInit(name: flds[i].name,
                                         value: dfl,
                                         typ: flds[i].typ)
  of nnkTupleConstr:
    let typ = nimToGpuType(node)
    ctx.maybeAddType(typ)

    result = GpuAst(kind: gpuObjConstr, ocType: typ)
    # get all fields of the type
    let flds = typ.oFields
    # find all fields that have been defined by the user
    var ocFields: seq[GpuFieldInit]
    for i in 0 ..< node.len: # all fields to be init'd
      case node[i].kind
      of nnkExprColonExpr:
        ocFields.add GpuFieldInit(name: node[i][0].strVal,
                                  value: ctx.toGpuAst(node[i][1]),
                                  typ: GpuType(kind: gtVoid))
      else:
        ocFields.add GpuFieldInit(name: "Field" & $i,
                                  value: ctx.toGpuAst(node[i]),
                                  typ: GpuType(kind: gtVoid))

    # now add fields in order of the type declaration
    for i in 0 ..< flds.len:
      let idx = findIdx(ocFields, flds[i].name)
      if idx >= 0:
        var f = ocFields[idx]
        f.typ = flds[i].typ
        result.ocFields.add f
      else:
        let dfl = GpuAst(kind: gpuLit, lValue: "DEFAULT", lType: GpuType(kind: gtVoid))
        result.ocFields.add GpuFieldInit(name: flds[i].name,
                                         value: dfl,
                                         typ: flds[i].typ)


  of nnkAsmStmt:
    doAssert node.len == 2
    doAssert node[0].kind == nnkEmpty
    result = GpuAst(kind: gpuInlineAsm,
                    stmt: node[1].strVal)

  of nnkBracket:
    let aLitTyp = nimToGpuType(node[0])
    var aValues = newSeq[GpuAst]()
    for el in node:
      aValues.add ctx.toGpuAst(el)
    result = GpuAst(kind: gpuArrayLit,
                    aValues: aValues,
                    aLitType: aLitTyp)

  of nnkCommentStmt:
    result = GpuAst(kind: gpuComment, comment: node.strVal)

  of nnkHiddenStdConv:
    doAssert node[0].kind == nnkEmpty
    result = ctx.toGpuAst(node[1])
  of nnkConv:
    # maps type conversion, e.g. `let i: int = 5; i.uint32`
    result = GpuAst(kind: gpuConv, convTo: nimToGpuType(node[0]), convExpr: ctx.toGpuAst(node[1]))
  of nnkCast:
    # only maps real bit casts
    result = GpuAst(kind: gpuCast, cTo: nimToGpuType(node[0]), cExpr: ctx.toGpuAst(node[1]))

  of nnkAddr, nnkHiddenAddr:
    # `HiddenAddr` appears for accesses to `var` passed arguments
    result = GpuAst(kind: gpuAddr, aOf: ctx.toGpuAst(node[0]))

  of nnkHiddenDeref:
    case node.typeKind
    of ntyUncheckedArray:
      # `getTypeInst(node)` would yield:
      # BracketExpr
      #   Sym "UncheckedArray"
      #   Sym "uint32"
      # i.e. it is a `ptr UncheckedArray[T]`
      # In this case we just ignore the deref, because on the CUDA
      # side it is just a plain pointer array we index into using
      # `foo[i]`.
      result = ctx.toGpuAst(node[0])
    else:
      # Otherwise we treat it like a regular deref
      # HiddenDeref
      #   Sym "x"
      # With e.g. `getTypeInst(node) = Sym "BigInt"`
      # and `node.typeKind = ntyObject`
      # due to a `var` parameter
      result = GpuAst(kind: gpuDeref, dOf: ctx.toGpuAst(node[0]))
  of nnkDerefExpr: #, nnkHiddenDeref:
    result = GpuAst(kind: gpuDeref, dOf: ctx.toGpuAst(node[0]))

  of nnkConstDef:
    result = GpuAst(kind: gpuConstexpr,
                    cIdent: ctx.toGpuAst(node[0]),
                    cValue: ctx.toGpuAst(node[2]),
                    cType: nimToGpuType(node))
    result.cIdent.iTyp = result.cType # also store the type in the symbol, for easier lookup later
    result.cIdent.symbolKind = gsLocal #if atvShared in result.vAttributes: gsShared
                               #elif atvPrivate in varNode.vAttributes: gsPrivate
                               #else: gsLocal

  of nnkConstSection:
    result = GpuAst(kind: gpuBlock)
    for el in node: # walk each type def
      doAssert el.kind == nnkConstDef
      result.statements.add ctx.toGpuAst(el)

  of nnkWhenStmt:
    raiseAssert "We shouldn't be seeing a `when` statement after sem check of the Nim code."
  else:
    echo "Unhandled node kind in toGpuAst: ", node.kind
    raiseAssert "Unhandled node kind in toGpuAst: " & $node.treerepr
    result = GpuAst(kind: gpuBlock)
