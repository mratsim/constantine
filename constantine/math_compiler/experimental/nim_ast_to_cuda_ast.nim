import std / [macros, strutils, sequtils, options, sugar, tables]

type
  GpuNodeKind = enum
    gpuVoid         # Just an empty statement. Useful to not emit anything
    gpuProc         # Function definition (both device and global)
    gpuCall         # Function call
    gpuTemplateCall # Call to a Nim template
    gpuIf           # If statement
    gpuFor          # For loop
    gpuBinOp        # Binary operation
    gpuVar          # Variable declaration
    gpuAssign       # Assignment
    gpuIdent        # Identifier
    gpuLit          # Literal value
    gpuArrayLit     # Literal array constructor `[1, 2, 3]`
    gpuPrefix       # Prefix e.g. `-`
    gpuBlock        # Block of statements
    gpuReturn       # Return statement
    gpuDot          # Member access (a.b)
    gpuIndex        # Array indexing (a[b])
    gpuTypeDef      # Type definition
    gpuObjConstr    # Object (struct) constructor
    gpuInlineAsm    # Inline assembly (PTX)
    gpuAddr         # Address of an expression
    gpuDeref        # Dereferences an expression
    gpuCast         # Cast expression
    gpuComment      # Just a comment

  GpuTypeKind = enum
    gtVoid,
    gtUint8, gtUint16, gtInt16, gtUint32, gtInt32, gtUint64, gtInt64, gtFloat32, gtFloat64, gtSize_t, # atomics
    gtArray,     # Static array `array[N, dtype]` -> `dtype[N]`
    gtString,
    gtObject,    # Struct types
    gtPtr        # Pointer type, carries inner type

  GpuTypeField = object
    name: string
    typ: GpuType

  GpuType = ref object
    case kind: GpuTypeKind
    of gtPtr: to: GpuType # points to `to`
    of gtObject:
      name: string
      oFields: seq[GpuTypeField]
    of gtArray:
      aTyp: GpuType # the inner type (must be some atomic base type at the moment)
      aLen: int     # The length of the array. If `aLen == -1` we look at a generic (static) array. Will be given at instantiation time
    else: discard

  GpuAttribute = enum
    attDevice = "__device__"
    attGlobal = "__global__"
    attForceInline = "__forceinline__"

  GpuAst = ref object
    case kind: GpuNodeKind
    of gpuVoid: discard
    of gpuProc:
      pName: string
      pRetType: GpuType
      pParams: seq[tuple[name: string, typ: GpuType]]
      pBody: GpuAst
      pAttributes: set[GpuAttribute]
    of gpuCall:
      cName: string
      cArgs: seq[GpuAst]
    of gpuTemplateCall:
      tcName: string
      tcArgs: seq[GpuAst]  # Arguments for template instantiation
    of gpuIf:
      ifCond: GpuAst
      ifThen: GpuAst
      ifElse: Option[GpuAst]  # None if no else branch
    of gpuFor:
      fVar: string
      fStart, fEnd: GpuAst
      fBody: GpuAst
    of gpuBinOp:
      bOp: string
      bLeft, bRight: GpuAst
    of gpuVar:
      vName: string
      vType: GpuType
      vInit: GpuAst
    of gpuAssign:
      aLeft, aRight: GpuAst
    of gpuIdent:
      iName: string
    of gpuLit:
      lValue: string
      lType: GpuType
    of gpuArrayLit:
      aValues: seq[string]
      aLitType: GpuType # type of first element
    of gpuBlock:
      statements: seq[GpuAst]
    of gpuReturn:
      rValue: GpuAst
    of gpuDot:
      dParent: GpuAst
      dField: GpuAst #string
    of gpuIndex:
      iArr: GpuAst
      iIndex: GpuAst
    of gpuPrefix:
      pOp: string
      pVal: GpuAst
    of gpuTypeDef:
      tName: string
      tFields: seq[GpuTypeField]
    of gpuObjConstr:
      ocName: string # type we construct
      ## XXX: it would be better if we already fill the fields with default values here
      ocFields: seq[GpuFieldInit] # the fields we initialize
    of gpuInlineAsm:
      stmt: string
    of gpuComment:
      comment: string
    of gpuCast:
      cTo: GpuType # type to cast to
      cExpr: GpuAst # expression we cast
    of gpuAddr:
      aOf: GpuAst
    of gpuDeref:
      dOf: GpuAst

  GpuFieldInit = object
    name: string
    value: GpuAst

  TemplateInfo = object
    params: seq[string]
    body: GpuAst

  GpuContext = object
    ## XXX: need table for generic invocations. Then when we encounter a type, need to map to
    ## the specific version
    ## However, also need to keep every *generic procedure*. In their bodies the types are
    ## only defined once they are called after all.
    templates: Table[string, TemplateInfo]  # Maps template names to their info

proc `$`(x: GpuType): string =
  if x == nil:
    result = "GpuType(nil)"
  else:
    result = $x[]

proc initGpuType(kind: GpuTypeKind): GpuType =
  ## If `kind` is `gtPtr` `to` must be the type we point to
  if kind in [gtObject, gtPtr, gtArray]: raiseAssert "Objects/Pointers/Arrays must be constructed using `initGpuPtr/Object/ArrayType` "
  result = GpuType(kind: kind)

proc initGpuPtrType(to: GpuType): GpuType =
  ## If `kind` is `gtPtr` `to` must be the type we point to
  result = GpuType(kind: gtPtr, to: to)

proc initGpuObjectType(name: string, flds: seq[GpuTypeField]): GpuType =
  ## If `kind` is `gtPtr` `to` must be the type we point to
  result = GpuType(kind: gtObject, name: name, oFields: flds)

proc initGpuArrayType(aTyp: GpuTypeKind, len: int): GpuType =
  ## If `kind` is `gtPtr` `to` must be the type we point to
  ## XXX: support arrays to structs!
  result = GpuType(kind: gtArray, aTyp: initGpuType(aTyp), aLen: len)

proc toGpuTypeKind(t: NimTypeKind): GpuTypeKind =
  case t
  #of ntyBool, ntyChar:
    # , ntyEmpty, ntyAlias, ntyNil, ntyExpr, ntyStmt, ntyTypeDesc, ntyGenericInvocation, ntyGenericBody, ntyGenericInst, ntyGenericParam, ntyDistinct, ntyEnum, ntyOrdinal, ntyArray, ntyObject, ntyTuple, ntySet, ntyRange, ntyPtr, ntyRef, ntyVar, ntySequence, ntyProc,
  #of ntyPointer, ntyUncheckedArray, ntyOpenArray, ntyString, ntyCString
  # , ntyForward, ntyInt, ntyInt8,
  of ntyInt16: gtInt16
  of ntyInt32: gtInt32
  of ntyInt64: gtInt64
  of ntyInt:   gtInt64
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

proc toGpuTypeKind(t: NimNode): GpuTypeKind =
  let tKind = t.typeKind
  if tKind == ntyGenericInst:
    let impl = getTypeImpl(t)
    case impl.kind
    of nnkDistinctTy: # just skip the distinct
      result = toGpuTypeKind(impl[0].typeKind)
    else:
      raiseAssert "Unsupport type so far: " & $t.treerepr & " of impl: " & $impl.treerepr
  else:
    result = toGpuTypeKind(tKind)

proc nimToGpuType(n: NimNode): GpuType
proc getInnerPointerType(n: NimNode): GpuType =

  ## XXX: instead of returning `GpuTypeKind` return a `GpuType` by calling back into `nimToGpuType`!

  doAssert n.typeKind in {ntyPtr, ntyPointer, ntyUncheckedArray} or n.kind == nnkPtrTy, "But was: " & $n.treerepr & " of typeKind " & $n.typeKind
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
  else:
    raiseAssert "Found what: " & $n.treerepr

proc parseTypeFields(node: NimNode): seq[GpuTypeField]
proc nimToGpuType(n: NimNode): GpuType =
  ## Maps a Nim type to a type on the GPU
  case n.kind
  of nnkIdentDefs: # extract type for let / var based on explicit or implicit type
    if n[n.len - 2].kind != nnkEmpty: # explicit type
      result = nimToGpuType(n[n.len - 2])
    else: # take from last element
      result = nimToGpuType(n[n.len - 1].getTypeInst())
  else:
    if n.kind == nnkEmpty: return initGpuType(gtVoid)
    case n.typeKind
    of ntyInt .. ntyUint64: # includes all float types
      result = initGpuType(toGpuTypeKind n.typeKind)
    of ntyPtr:
      result = initGpuPtrType(getInnerPointerType(n))
    of ntyUncheckedArray:
      ## Note: this is just the internal type of the array. It is only a pointer due to
      ## `ptr UncheckedArray[T]`. We simply remove the `UncheckedArray` part.
      result = getInnerPointerType(n)
    of ntyObject:
      let impl = n.getTypeImpl
      let flds = impl.parseTypeFields()
      result = initGpuObjectType(n.strVal, flds)
    of ntyArray:
      # For a generic, static array type, e.g.:
      # BracketExpr
      #   Sym "array"
      #   Ident "N"
      #   Sym "uint32"
      doAssert n.len == 3
      doAssert n[0].strVal == "array"
      let len = if n[1].kind in {nnkSym, nnkIdent}: -1
                else:
                  case n[1].kind
                  of nnkIntLit: n[1].intVal
                  else:
                    #doAssert n[1].kind == nnkIntLit, "No is: " & $n.treerepr
                    doAssert n[1].kind == nnkInfix, "No is: " & $n.treerepr
                    doAssert n[1][1].kind == nnkIntLit, "No is: " & $n.treerepr
                    doAssert n[1][1].intVal == 0, "No is: " & $n.treerepr
                    n[1][2].intVal + 1
      result = initGpuArrayType(toGpuTypeKind n[2], len)
    #of ntyCompositeTypeClass:
    #  echo n.getTypeImpl.treerepr
    #  error("o")
    of ntyGenericInvocation:
      result = initGpuType(gtVoid)
      error("Generics are not supported in the CUDA DSL so far.")
    of ntyGenericInst:
      case n.kind
      of nnkUIntLit:
        result = initGpuType(toGpuTypeKind ntyUint64)
      else:
        raiseAssert "Unsupported generic inst: " & $n.treerepr & " of typekind " & $n.typeKind

    else: raiseAssert "Type : " & $n.typeKind & " not supported yet: " & $n.treerepr

proc assignOp(op: string): string =
  ## Returns the correct CUDA operation given the Nim operator.
  ## This is to replace things like `shl`, `div` or `mod`
  case op
  of "div": result = "/"
  of "mod": result = "%"
  of "shl": result = "<<"
  of "shr": result = ">>"
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

proc toGpuAst(ctx: var GpuContext, node: NimNode): GpuAst =
  ## XXX: things still left to do:
  ## - support `result` variable? Currently not supported. Maybe we will won't

  #echo node.treerepr
  case node.kind
  of nnkStmtList, nnkBlockStmt:
    result = GpuAst(kind: gpuBlock)
    for el in node:
      result.statements.add ctx.toGpuAst(el)
  of nnkStmtListExpr: # for statements that return a value.
    ## XXX: For CUDA just a block?
    result = GpuAst(kind: gpuBlock)
    for el in node:
      if el.kind != nnkEmpty:
        result.statements.add ctx.toGpuAst(el)

  of nnkProcDef:
    result = GpuAst(kind: gpuProc)
    result.pName = node.name.strVal
    doAssert node[3].kind == nnkFormalParams
    result.pRetType = nimToGpuType(node[3][0]) # arg 0 is return type
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
      for i in 0 ..< numParams:
        result.pParams.add((param[i].strVal, paramType))

    # Process pragmas
    if node.pragma.kind != nnkEmpty:
      for pragma in node.pragma:
        if pragma.kind in {nnkIdent, nnkSym}:
          case pragma.strVal
          of "device": result.pAttributes.incl attDevice
          of "global": result.pAttributes.incl attGlobal
          of "forceinline": result.pAttributes.incl attForceInline

    result.pBody = ctx.toGpuAst(node.body)

  of nnkLetSection, nnkVarSection:
    # For a section with multiple declarations, create a block
    result = GpuAst(kind: gpuBlock)
    for declaration in node:
      # Each declaration gets converted to a gpuVar
      var varNode = GpuAst(kind: gpuVar)
      varNode.vName = declaration[0].strVal
      varNode.vType = nimToGpuType(declaration)
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
      result.statements.add(varNode)

  of nnkAsgn:
    result = GpuAst(kind: gpuAssign)
    result.aLeft = ctx.toGpuAst(node[0])
    result.aRight = ctx.toGpuAst(node[1])

  of nnkIfStmt:
    result = GpuAst(kind: gpuIf)
    let branch = node[0]  # First branch
    result.ifCond = ctx.toGpuAst(branch[0])
    result.ifThen = ensureBlock ctx.toGpuAst(branch[1])
    if node.len > 1 and node[^1].kind == nnkElse:
      result.ifElse = some(ensureBlock ctx.toGpuAst(node[^1][0]))

  of nnkForStmt:
    result = GpuAst(kind: gpuFor)
    result.fVar = node[0].strVal
    # Assuming range expression
    result.fStart = ctx.toGpuAst(node[1][1])
    result.fEnd = ctx.toGpuAst(node[1][2])
    result.fBody = ensureBlock ctx.toGpuAst(node[2])

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

  of nnkCall:
    # Check if this is a template call
    let name = node[0].repr # cannot use `strVal`, might be a symchoice
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
    result.bOp = assignOp(node[0].repr) # repr so that open sym choice gets correct name
    result.bLeft = ctx.toGpuAst(node[1])
    result.bRight = ctx.toGpuAst(node[2])

  of nnkDotExpr:
    result = GpuAst(kind: gpuDot)
    result.dParent = ctx.toGpuAst(node[0])
    result.dField = ctx.toGpuAst(node[1])

  of nnkBracketExpr:
    result = GpuAst(kind: gpuIndex)
    result.iArr = ctx.toGpuAst(node[0])
    result.iIndex = ctx.toGpuAst(node[1])

  of nnkIdent, nnkSym, nnkOpenSymChoice:
    result = GpuAst(kind: gpuIdent)
    result.iName = node.repr # for sym choices

  # literal types
  of nnkIntLit:
    result = GpuAst(kind: gpuLit)
    result.lValue = $node.intVal
    result.lType = initGpuType(gtInt32)
  of nnkUInt32Lit:
    result = GpuAst(kind: gpuLit)
    result.lValue = $node.intVal
    result.lType = initGpuType(gtUInt32)
  of nnkFloat64Lit:
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
                    pOp: node[0].strVal,
                    pVal: ctx.toGpuAst(node[1]))

  of nnkHiddenStdConv:
    doAssert node[0].kind == nnkEmpty
    result = ctx.toGpuAst(node[1])

  of nnkHiddenDeref:
    # just ignore the deref
    ## XXX: add real deref! (Q: always?)
    result = ctx.toGpuAst(node[0])

  of nnkTypeSection:
    result = GpuAst(kind: gpuBlock)
    for el in node: # walk each type def
      doAssert el.kind == nnkTypeDef
      result.statements.add ctx.toGpuAst(el)
  of nnkTypeDef:
    result = GpuAst(kind: gpuTypeDef, tName: node[0].strVal)
    result.tFields = parseTypeFields(node[2])
  of nnkObjConstr:
    result = GpuAst(kind: gpuObjConstr, ocName: node[0].strVal)
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
      ## XXX: do not use `repr`, e.g. if `1'u32` we'll get the `'u32` suffix
      aValues.add $el.intVal
    result = GpuAst(kind: gpuArrayLit,
                    aValues: aValues,
                    aLitType: aLitTyp)

  of nnkCommentStmt:
    result = GpuAst(kind: gpuComment, comment: node.strVal)

  of nnkCast:
    result = GpuAst(kind: gpuCast, cTo: nimToGpuType(node[0]), cExpr: ctx.toGpuAst(node[1]))

  of nnkAddr:
    result = GpuAst(kind: gpuAddr, aOf: ctx.toGpuAst(node[0]))

  of nnkDerefExpr:
    result = GpuAst(kind: gpuDeref, dOf: ctx.toGpuAst(node[0]))

  else:
    echo "Unhandled node kind in toGpuAst: ", node.kind
    raiseAssert "Unhandled node kind in toGpuAst: " & $node.treerepr
    result = GpuAst(kind: gpuBlock)

proc gpuTypeToString(t: GpuTypeKind): string =
  case t
  of gtUint8: "unsigned char"
  of gtUint16: "unsigned short"
  of gtUint32: "unsigned int"
  of gtUint64: "unsigned long long"
  of gtInt16: "short"
  of gtInt32: "int"
  of gtInt64: "long long"
  of gtFloat32: "float"
  of gtFloat64: "double"
  of gtVoid: "void"
  of gtSize_t: "size_t"
  of gtPtr: "*"
  of gtObject: "struct"
  of gtString: "const char*"
  else:
    raiseAssert "Invalid type : " & $t

proc gpuTypeToString(t: GpuType, ident: string = "", allowArrayToPtr = false): string =
  ## Given an optional identifier required for array types
  ##
  ## XXX: we don't support this at the moment, it occured to me as something that
  ## could be useful sometimes...
  ## If `allowArrayToPtr` we allow casting a statically sized array to a pointer
  case t.kind
  of gtPtr: result = gpuTypeToString(t.to) & gpuTypeToString(t.kind)
  of gtObject: result = t.name
  of gtArray:
    if ident.len == 0: # and not allowArrayToPtr:
      error("Invalid call, got an array type but don't have an identifier: " & $t)
    else:
      result = gpuTypeToString(t.aTyp) & " " & ident & "[" & $t.aLen & "]"
  else: result = gpuTypeToString(t.kind)

  if ident.len > 0 and t.kind != gtArray: # still need to add ident
    result.add " " & ident

proc genCuda(ctx: GpuContext, ast: GpuAst, indent = 0): string =
  let indentStr = "  ".repeat(indent)

  #echo "At: ", ast.repr

  case ast.kind
  of gpuVoid: return # nothing to emit
  of gpuProc:
    let attrs = collect:
      for att in ast.pAttributes:
        $att

    # extern "C" is needed to avoid name mangling
    result = indentStr & " extern \"C\" " & attrs.join(" ") & " " &
             gpuTypeToString(ast.pRetType) & " " &
             ast.pName & "("

    # Parameters
    var params: seq[string]
    for (name, typ) in ast.pParams:
      params.add gpuTypeToString(typ, name)
    result &= params.join(", ") & ") {\n"

    result &= ctx.genCuda(ast.pBody, indent + 1)
    result &= "\n" & indentStr & "}"

  of gpuBlock:
    result = ""
    for i, el in ast.statements:
      result.add ctx.genCuda(el, indent)
      if el.kind != gpuBlock: # nested block ⇒ ; already added
        result.add ";"
      if i < ast.statements.high:
        result.add "\n"

  of gpuVar:
    result = indentStr & gpuTypeToString(ast.vType, ast.vName)
    if ast.vInit != nil:
      result &= " = " & ctx.genCuda(ast.vInit)

  of gpuAssign:
    result = indentStr & ctx.genCuda(ast.aLeft) & " = " & ctx.genCuda(ast.aRight)

  of gpuIf:
    result = indentStr & "if (" & ctx.genCuda(ast.ifCond) & ") {\n"
    result &= ctx.genCuda(ast.ifThen, indent + 1) & "\n"
    result &= indentStr & "}"
    if ast.ifElse.isSome:
      result &= " else {\n"
      result &= ctx.genCuda(ast.ifElse.get, indent + 1) & "\n"
      result &= indentStr & "}"

  of gpuFor:
    result = indentStr & "for(int " & ast.fVar & " = " &
             ctx.genCuda(ast.fStart) & "; " &
             ast.fVar & " < " & ctx.genCuda(ast.fEnd) & "; " &
             ast.fVar & "++) {\n"
    result &= ctx.genCuda(ast.fBody, indent + 1) & "\n"
    result &= indentStr & "}"

  of gpuDot:
    result = ctx.genCuda(ast.dParent) & "." & ctx.genCuda(ast.dField)

  of gpuIndex:
    result = ctx.genCuda(ast.iArr) & "[" & ctx.genCuda(ast.iIndex) & "]"

  of gpuCall:
    result = indentStr & ast.cName & "(" &
             ast.cArgs.mapIt(ctx.genCuda(it)).join(", ") & ")"

  of gpuTemplateCall:
    error("Template calls are not supported at the moment. In theory there shouldn't even _be_ any template " &
      "calls in the expanded body of the `cuda` macro.")
    when false: # Template replacement would look something like this:
      let templ = ctx.templates[ast.tcName]
      let expandedBody = substituteTemplateArgs(
        templ.body,
        templ.params,
        ast.tcArgs
      )
      result = ctx.genCuda(expandedBody, indent)

  of gpuBinOp:
    result = indentStr & "(" & ctx.genCuda(ast.bLeft) & " " &
             ast.bOp & " " &
             ctx.genCuda(ast.bRight) & ")"

  of gpuIdent:
    result = ast.iName

  of gpuLit:
    if ast.lType.kind == gtString: result = "\"" & ast.lValue & "\""
    elif ast.lValue == "DEFAULT": result = "{}" # default initialization, `DEFAULT` placeholder
    else: result = ast.lValue

  of gpuArrayLit:
    result = "{"
    for i, el in ast.aValues:
      result.add "(" & gpuTypeToString(ast.aLitType) & ")" & el
      if i < ast.aValues.high:
        result.add ", "
    result.add "}"

  of gpuReturn:
    result = indentStr & "return " & ctx.genCuda(ast.rValue)

  of gpuPrefix:
    result = ast.pOp & ctx.genCuda(ast.pVal)

  of gpuTypeDef:
    result = "struct " & ast.tName & "{\n"
    for el in ast.tFields:
      result.add "  " & gpuTypeToString(el.typ, el.name) & ";\n"
    result.add "};"

  of gpuObjConstr:
    result = "{"
    for i, el in ast.ocFields:
      result.add ctx.genCuda(el.value)
      if i < ast.ocFields.len - 1:
        result.add ", "
    result.add "}"

  of gpuInlineAsm:
    result = indentStr & "asm(" & ast.stmt.strip & ");"

  of gpuComment:
    result = indentStr & "/* " & ast.comment & " */"

  of gpuCast:
    result = "(" & gpuTypeToString(ast.cTo) & ")" & ctx.genCuda(ast.cExpr)

  of gpuAddr:
    result = "(&" & ctx.genCuda(ast.aOf) & ")"

  of gpuDeref:
    result = "(*" & ctx.genCuda(ast.dOf) & ")"

  else:
    echo "Unhandled node kind in genCuda: ", ast.kind
    raiseAssert "Unhandled node kind in genCuda: " & ast.repr
    result = ""

macro cuda*(body: typed): string =
  ## WARNING: The following are *not* supported:
  ## - UFCS: because this is a pure untyped DSL, there is no way to disambiguate between
  ##         what is a field access and a function call. Hence we assume any `nnkDotExpr`
  ##         is actually a field access!
  ## - most regular Nim features :)
  var ctx = GpuContext()
  let gpuAst = ctx.toGpuAst(body)
  ## NOTE: `header` is currently unused. Not sure yet if we'll ever need it.
  let header = """
// #include "foo.h"
"""

  let body = ctx.genCuda(gpuAst)
  result = newLit(header & body)

when isMainModule:
  # Mini example
  let kernel = cuda:
    proc square(x: float32): float32 {.device.} =
      if x < 0.0'f32:
        result = 0.0'f32
      else:
        result = x * x

    proc computeSquares(
      output: ptr float32,
      input: ptr float32,
      n: int32
    ) {.global.} =
      let idx: uint32 = blockIdx.x * blockDim.x + threadIdx.x
      if idx < n:
        var temp: float32 = 0.0'f32
        for i in 0..<4:
          temp += square(input[idx + i * n])
        output[idx] = temp

  echo kernel
