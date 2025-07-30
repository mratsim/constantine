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

proc nimToGpuType(n: NimNode): GpuType

proc initGpuType(kind: GpuTypeKind): GpuType =
  ## If `kind` is `gtPtr` `to` must be the type we point to
  if kind in [gtObject, gtPtr, gtArray]: raiseAssert "Objects/Pointers/Arrays must be constructed using `initGpuPtr/Object/ArrayType` "
  result = GpuType(kind: kind)

proc initGpuPtrType(to: GpuType, implicitPtr: bool): GpuType =
  ## If `kind` is `gtPtr` `to` must be the type we point to
  result = GpuType(kind: gtPtr, to: to, implicit: implicitPtr)

proc initGpuUAType(to: GpuType): GpuType =
  ## Initializes a GPU type for an unchecked array (ptr wraps this)
  result = GpuType(kind: gtUA, uaTo: to)

proc initGpuVoidPtr(): GpuType =
  result = GpuType(kind: gtVoidPtr)

proc initGpuObjectType(name: string, flds: seq[GpuTypeField]): GpuType =
  ## If `kind` is `gtPtr` `to` must be the type we point to
  result = GpuType(kind: gtObject, name: name, oFields: flds)

proc initGpuArrayType(aTyp: NimNode, len: int): GpuType =
  ## Construct an statically sized array type
  result = GpuType(kind: gtArray, aTyp: nimToGpuType(aTyp), aLen: len)

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
  of ntyInt:
    case Backend
    of bkCuda: gtInt64
    of bkWGSL: gtInt32 ## XXX: we map Nim `int` to `int32`!
  of ntyFloat: gtFloat64
  of ntyFloat32: gtFloat32
  of ntyFloat64: gtFloat64
  #of ntyFloat128: gtFloat128
  of ntyUInt: gtUint64
  of ntyUInt8: gtUint8
  of ntyUInt16: gtUint16
  of ntyUInt32: gtUint32
  of ntyUInt64: gtUint64
  else:
    raiseAssert "Not supported yet: " & $t

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

proc getInnerPointerType(n: NimNode): GpuType =
  doAssert n.typeKind in {ntyPtr, ntyPointer, ntyUncheckedArray, ntyVar} or n.kind == nnkPtrTy, "But was: " & $n.treerepr & " of typeKind " & $n.typeKind
  if n.typeKind in {ntyPointer, ntyUncheckedArray}:
    let typ = n.getTypeInst()
    doAssert typ.kind == nnkBracketExpr, "No, was: " & $typ.treerepr
    doAssert typ[0].kind in {nnkIdent, nnkSym}
    doAssert typ[0].strVal in ["ptr", "UncheckedArray"]
    result = nimToGpuType(typ[1])
  elif n.kind == nnkPtrTy:
    result = nimToGpuType(n[0])
  elif n.kind == nnkAddr:
    let typ = n.getTypeInst()
    result = getInnerPointerType(typ)
  elif n.kind == nnkVarTy:
    # VarTy
    #   Sym "BigInt"
    result = nimToGpuType(n[0])
  else:
    raiseAssert "Found what: " & $n.treerepr

proc determineArrayLength(n: NimNode): int =
  case n[1].kind
  of nnkSym:
    # likely a constant, try to get its value
    result = n[1].getImpl.intVal
  of nnkIdent:
    let msg = """Found array with length given by identifier: $#!
You might want to create a typed template taking a typed parameter for this
constant to force the Nim compiler to bind the symbol.
""" % n[1].strVal
    raiseAssert msg
  else:
    case n[1].kind
    of nnkIntLit: result = n[1].intVal
    else:
      #doAssert n[1].kind == nnkIntLit, "No is: " & $n.treerepr
      doAssert n[1].kind == nnkInfix, "No is: " & $n.treerepr
      doAssert n[1][1].kind == nnkIntLit, "No is: " & $n.treerepr
      doAssert n[1][1].intVal == 0, "No is: " & $n.treerepr
      result = n[1][2].intVal + 1

proc getTypeName(n: NimNode): string =
  ## Returns the name of the type
  case n.kind
  of nnkIdent, nnkSym: result = n.strVal
  of nnkObjConstr:
    if n[0].kind == nnkEmpty:
      result = n.getTypeInst.strVal
    else:
      result = n[0].strVal # type is the first node
  else: raiseAssert "Unexpected node in `getTypeName`: " & $n.treerepr

proc parseTypeFields(node: NimNode): seq[GpuTypeField]
proc nimToGpuType(n: NimNode): GpuType =
  ## Maps a Nim type to a type on the GPU
  case n.kind
  of nnkIdentDefs: # extract type for let / var based on explicit or implicit type
    if n[n.len - 2].kind != nnkEmpty: # explicit type
      result = nimToGpuType(n[n.len - 2])
    else: # take from last element
      result = nimToGpuType(n[n.len - 1].getTypeInst())
  of nnkConstDef:
    if n[1].kind != nnkEmpty: # has an explicit type
      result = nimToGpuType(n[1])
    else:
      result = nimToGpuType(n[2]) # derive from the RHS literal
  else:
    if n.kind == nnkEmpty: return initGpuType(gtVoid)
    case n.typeKind
    of ntyBool, ntyInt .. ntyUint64: # includes all float types
      result = initGpuType(toGpuTypeKind n.typeKind)
    of ntyPtr:
      result = initGpuPtrType(getInnerPointerType(n), implicitPtr = false)
    of ntyVar:
      result = initGpuPtrType(getInnerPointerType(n), implicitPtr = true)
    of ntyPointer:
      result = initGpuVoidPtr()
    of ntyUncheckedArray:
      ## Note: this is just the internal type of the array. It is only a pointer due to
      ## `ptr UncheckedArray[T]`. We simply remove the `UncheckedArray` part.
      result = initGpuUAType(getInnerPointerType(n))
    of ntyObject:
      let impl = n.getTypeImpl
      let flds = impl.parseTypeFields()
      let typName = getTypeName(n) # might be an object construction
      result = initGpuObjectType(typName, flds)
    of ntyArray:
      # For a generic, static array type, e.g.:
      if n.kind == nnkSym:
        return nimToGpuType(getTypeImpl(n))
      if n.len == 3:
        # BracketExpr
        #   Sym "array"
        #   Ident "N"
        #   Sym "uint32"
        doAssert n.len == 3, "Length was not 3, but: " & $n.len & " for node: " & n.treerepr
        doAssert n[0].strVal == "array"
        let len = determineArrayLength(n)
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
      result = initGpuType(gtVoid)
      error("Generics are not supported in the CUDA DSL so far.")
    of ntyGenericInst:
      result = n.unpackGenericInst().nimToGpuType()
    else: raiseAssert "Type : " & $n.typeKind & " not supported yet: " & $n.treerepr

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
  doAssert node.kind == nnkObjectTy
  doAssert node[2].kind == nnkRecList
  for ch in node[2]:
    doAssert ch.kind == nnkIdentDefs and ch.len == 3
    result.add GpuTypeField(name: ch[0].strVal,
                            typ: nimToGpuType(ch[1]))

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

proc collectProcAttributes(n: NimNode): set[GpuAttribute] =
  doAssert n.kind == nnkPragma
  for pragma in n:
    doAssert pragma.kind in [nnkIdent, nnkSym], "Unexpected node kind: " & $pragma.treerepr
    case pragma.strVal
    of "device": result.incl attDevice
    of "global": result.incl attGlobal
    of "forceinline": result.incl attForceInline
    of "nimonly":
      # used to fully ignore functions!
      return
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
    case pragma.strVal
    of "cuExtern", "extern": result.add atvExtern
    of "shared": result.add atvShared
    of "private": result.add atvPrivate
    of "volatile": result.add atvVolatile
    of "constant": result.add atvConstant
    else:
      raiseAssert "Unexpected pragma: " & $pragma.treerepr

proc toGpuAst*(ctx: var GpuContext, node: NimNode): GpuAst

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
  else:
    # else we use the str representation (repr for open / closed sym choice nodes)
    result = toAst n.repr
    #raiseAssert "This fn identifier is not a symbol?! " & $n.repr
    # If it's not a symbol, there is no signature associated
    # ctx.sigTab[sig] = result
  result.symbolKind = gsProc # make sure it's a proc

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
  of nnkStmtListExpr: # for statements that return a value.
    ## XXX: For CUDA just a block?
    result = GpuAst(kind: gpuBlock)
    for el in node:
      if el.kind != nnkEmpty:
        result.statements.add ctx.toGpuAst(el)
  of nnkDiscardStmt:
    # just process the child node if any
    result = ctx.toGpuAst(node[0])

  of nnkProcDef, nnkFuncDef:
    result = GpuAst(kind: gpuProc)
    result.pName = ctx.toGpuAst(node.name)
    result.pName.symbolKind = gsProc ## This is a procedure identifier
    doAssert node[3].kind == nnkFormalParams
    result.pRetType = nimToGpuType(node[3][0]) # arg 0 is return type
    # Process pragmas
    if node.pragma.kind != nnkEmpty:
      doAssert node.pragma.len > 0, "Pragma kind non empty, but no pragma?"
      result.pAttributes = collectProcAttributes(node.pragma)
      if result.pAttributes.len == 0: # means `nimonly` was applied
        return GpuAst(kind: gpuVoid)
    # Process parameters
    for i in 1 ..< node[3].len:
      let param = node[3][i]
      let numParams = param.len - 2 # 3 if one param, one more for each of same type, example:
      let typIdx = param.len - 2 # second to last is the type
      # IdentDefs
      #   Ident "x"
      #   Ident "y"
      #   Ident "res"
      #   PtrTy
      #     Ident "float32"   # `param.len - 2`
      #   Empty               # `param.len - 1`
      let paramType = nimToGpuType(param[typIdx])
      #echo "Argument: ", param.treerepr, " has tpye: ", paramType
      for i in 0 ..< numParams:
        var p = ctx.toGpuAst(param[i])
        let symKind = if attGlobal in result.pAttributes: gsGlobalKernelParam
                      else: gsDeviceKernelParam
        p.iTyp = paramType     ## Update the type of the symbol
        p.symbolKind = symKind ## and the symbol kind
        let param = GpuParam(ident: p, typ: paramType)
        result.pParams.add(param)

    result.pBody = ctx.toGpuAst(node.body)
      .ensureBlock() # single line procs should be a block to generate `;`

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
      varNode.vType = nimToGpuType(declaration)
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
    # Check if this is a template call
    let name = ctx.getFnName(node[0]) # cannot use `strVal`, might be a symchoice
    let args = node[1..^1].mapIt(ctx.toGpuAst(it))
    # Producing a template call something like this (but problematic due to overloads etc)
    # we could then perform manual replacement of the template in the CUDA generation pass.
    if false: #  name in ctx.templates: #
      result = GpuAst(kind: gpuTemplateCall)
      result.tcName = name
      result.tcArgs = args
    else:
      result = GpuAst(kind: gpuCall)
      result.cName = name
      result.cArgs = args

  of nnkInfix:
    result = GpuAst(kind: gpuBinOp)
    # if left/right is boolean we need logical AND/OR, otherwise
    # bitwise
    let isBoolean = node[1].typeKind == ntyBool
    result.bOp = assignOp(node[0].repr, isBoolean) # repr so that open sym choice gets correct name
    result.bLeft = ctx.toGpuAst(node[1])
    result.bRight = ctx.toGpuAst(node[2])
    # We patch the types of int / float literals. WGSL does not automatically convert literals
    # to the target type.
    if result.bLeft.kind == gpuLit and result.bRight.kind != gpuLit:
      # determine literal type based on `bRight`
      result.bLeft.lType = nimToGpuType(node[2])
    elif result.bRight.kind == gpuLit and result.bLeft.kind != gpuLit:
      # determine literal type based on `bLeft`
      result.bRight.lType = nimToGpuType(node[1])

  of nnkDotExpr:
    ## NOTE: As we use a typed macro, we only encounter `DotExpr` for *actual* field accesses and NOT
    ## for calls using method call syntax without parens
    result = GpuAst(kind: gpuDot)
    result.dParent = ctx.toGpuAst(node[0])
    result.dField = ctx.toGpuAst(node[1])

  of nnkBracketExpr:
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
    # symbol, but rather to allow having the same symbol kind (set in the caller of this call).
    # For example in `nnkCall` nodes returning the value from the table automatically means the
    # `symbolKind` is local / function argument etc.
    if s notin ctx.sigTab:
      result = newGpuIdent()
      result.iName = node.repr
      result.iSym = s
      if result.iName == "_":
        result.iName = "tmp_" & $ctx.genSymCount
        inc ctx.genSymCount
        #ctx.sigTab[s] = result
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
    result = GpuAst(kind: gpuTypeDef, tName: node[0].strVal)
    result.tFields = parseTypeFields(node[2])
  of nnkObjConstr:
    let typName = getTypeName(node)
    result = GpuAst(kind: gpuObjConstr, ocName: typName)
    # get all fields of the type
    let flds = node[0].getTypeImpl.parseTypeFields() # sym
    # find all fields that have been defined by the user
    var ocFields: seq[GpuFieldInit]
    for i in 1 ..< node.len: # all fields to be init'd
      doAssert node[i].kind == nnkExprColonExpr
      ocFields.add GpuFieldInit(name: node[i][0].strVal,
                                value: ctx.toGpuAst(node[i][1]))
    # now add fields in order of the type declaration
    for i in 0 ..< flds.len:
      let idx = findIdx(ocFields, flds[i].name)
      if idx >= 0:
        result.ocFields.add ocFields[idx]
      else:
        let dfl = GpuAst(kind: gpuLit, lValue: "DEFAULT", lType: GpuType(kind: gtVoid))
        result.ocFields.add GpuFieldInit(name: flds[i].name,
                                         value: dfl)

  of nnkAsmStmt:
    doAssert node.len == 2
    doAssert node[0].kind == nnkEmpty
    result = GpuAst(kind: gpuInlineAsm,
                    stmt: node[1].strVal)

  of nnkBracket:
    let aLitTyp = nimToGpuType(node[0])
    var aValues = newSeq[string]()
    for el in node:
      ## XXX: Support not just int literals
      aValues.add $el.intVal
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

  else:
    echo "Unhandled node kind in toGpuAst: ", node.kind
    raiseAssert "Unhandled node kind in toGpuAst: " & $node.treerepr
    result = GpuAst(kind: gpuBlock)
