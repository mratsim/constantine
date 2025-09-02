# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import std / [tables, sets, hashes, strutils, strformat]

type
  BackendKind* = enum
    bkCuda, ## CUDA backend
    bkWGSL  ## WebGPU WGSL backend

  GpuNodeKind* = enum
    gpuVoid         # Just an empty statement. Useful to not emit anything
    gpuProc         # Function definition (both device and global)
    gpuCall         # Function call
    gpuTemplateCall # Call to a Nim template
    gpuIf           # If statement
    gpuFor          # For loop
    gpuWhile        # While loop
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
    gpuAlias        # A type alias
    gpuObjConstr    # Object (struct) constructor
    gpuInlineAsm    # Inline assembly (PTX)
    gpuAddr         # Address of an expression
    gpuDeref        # Dereferences an expression
    gpuConv         # A type conversion, i.e. `let x = 5; x.float`
    gpuCast         # Cast expression
    gpuComment      # Just a comment
    gpuConstexpr    # A `constexpr`, i.e. compile time constant (Nim `const`)

  GpuTypeKind* = enum
    gtVoid,
    gtBool, gtUint8, gtUint16, gtInt16, gtUint32, gtInt32, gtUint64, gtInt64, gtFloat32, gtFloat64, gtSize_t, # atomics
    gtArray,       # Static array `array[N, dtype]` -> `dtype[N]`
    gtString,
    gtObject,      # Struct types
    gtPtr,         # Pointer type, carries inner type
    gtUA,          # UncheckedArray (UA) mapped to runtime sized arrays
    gtGenericInst, # Instantiated generic type with one or more generic arguments (instantiated!)
    gtVoidPtr      # Opaque void pointer
    gtInvalid      # Can be returned to indicate a call to `nimToGpuType` failed to determine a type
                   ## XXX: make this the default value and replace all `gtVoid` placeholders by it


  GpuTypeField* = object
    name*: string
    typ*: GpuType

  GpuType* = ref object
    builtin*: bool ## Whether the type refers to a builtin type or not
    case kind*: GpuTypeKind
    of gtPtr:
      to*: GpuType # `ptr T` points to `to`
      implicit*: bool # Whether the type was implicitly a pointer, i.e. `var T`.
      mutable*: bool # WebGPU "Generics" only: Mutable (read write) or immutable pointer (read only)?
                    # If a function is called with a raw pointer as an argument or `implicit == true / var T` argument,
                    # `mutable` will be true. If on the other hand we have a non pointer type and take its address
                    # via `foo.addr`, mutable will be false.
    of gtUA: uaTo*: GpuType # `UncheckedArray[T]`
    of gtObject:
      name*: string
      oFields*: seq[GpuTypeField]
    of gtArray:
      aTyp*: GpuType # the inner type (must be some atomic base type at the moment)
      aLen*: int     # The length of the array. If `aLen == -1` we look at a generic (static) array. Will be given at instantiation time
                    # On both CUDA and WebGPU a length of `0` is also used to generate `int foo[]` (CUDA)
                    # `array<foo>` (WebGPU) (runtime sized arrays), which are generated from `ptr UncheckedArray[float32]` for example.
    of gtGenericInst:
      gName*: string # name of the generic type
      gArgs*: seq[GpuType] # list of the instantiated generic arguments e.g. `vec3<f32>` on WGSL backend
      gFields*: seq[GpuTypeField] # same as `oFields` for `gtObject`
    else: discard

  GpuAttribute* = enum
    attDevice = "__device__"
    attGlobal = "__global__"
    attForceInline = "__forceinline__"

  GpuVarAttribute* = enum
    atvExtern = "extern"
    atvShared = "__shared__"
    atvPrivate = "private" # WebGPU only
    atvVolatile = "volatile"
    atvConstant = "__constant__" # use `{.constant.}` pragma, e.g. `var foo {.constant.}`

  GpuAst* = ref object
    case kind*: GpuNodeKind
    of gpuVoid: discard
    of gpuProc:
      pName*: GpuAst ## Will be a `GpuIdent`
      pRetType*: GpuType
      pParams*: seq[GpuParam]
      pBody*: GpuAst
      pAttributes*: set[GpuAttribute] # order not important, hence set
      forwardDeclare*: bool ## can be set to true to _only_ generate a forward declaration
    of gpuCall:
      cIsExpr*: bool ## If the call returns a value
      cName*: GpuAst ## Will be a `GpuIdent`
      cArgs*: seq[GpuAst]
    of gpuTemplateCall:
      tcName*: GpuAst ## Will be a `GpuIdent`
      tcArgs*: seq[GpuAst]  # Arguments for template instantiation
    of gpuIf:
      ifCond*: GpuAst
      ifThen*: GpuAst
      ifElse*: GpuAst # will be `GpuAst(kind*: gpuVoid)` if no else branch
    of gpuFor:
      fVar*: GpuAst ## Will be a `GpuIdent`
      fStart*, fEnd*: GpuAst
      fBody*: GpuAst
    of gpuWhile:
      wCond*: GpuAst
      wBody*: GpuAst
    of gpuBinOp:
      bOp*: GpuAst # `gpuIdent` of the binary operation
      bLeft*, bRight*: GpuAst
      # types of left and right nodes. Determined from Nim symbol associated with `bOp`
      bLeftTyp*, bRightTyp*: GpuType
    of gpuVar:
      vName*: GpuAst ## Will be a `GpuIdent`
      vType*: GpuType
      vInit*: GpuAst
      vRequiresMemcpy*: bool
      vMutable*: bool # `true == var`, `false == let`
      vAttributes*: seq[GpuVarAttribute] # order is important, hence seq
    of gpuAssign:
      aLeft*, aRight*: GpuAst
      aRequiresMemcpy*: bool
    of gpuIdent:
      iName*: string
      iSym*: string ## The actual unique identifier of the symbol
      iTyp*: GpuType = GpuType(kind: gtVoid) ## The type of this symbol. Might be empty for some types, but is guaranteed to be
                    ## correct for variables & function parameters.
      symbolKind*: GpuSymbolKind
    of gpuLit:
      lValue*: string
      lType*: GpuType
    of gpuConstexpr:
      cIdent*: GpuAst # the identifier
      cValue*: GpuAst # not just a string to support different types easily
      cType*: GpuType
    of gpuArrayLit:
      aValues*: seq[GpuAst]
      aLitType*: GpuType # type of first element
    of gpuBlock:
      isExpr*: bool ## Whether this block represents an expression, i.e. it returns something
      blockLabel*: string # optional name of the block. If any given, will open a `{ }` scope in CUDA
      statements*: seq[GpuAst]
      ## XXX: we could add a `locals` argument here, which would refer to all local variables
    of gpuReturn:
      rValue*: GpuAst
    of gpuDot:
      dParent*: GpuAst
      dField*: GpuAst #string
    of gpuIndex:
      iArr*: GpuAst
      iIndex*: GpuAst
    of gpuPrefix:
      pOp*: string
      pVal*: GpuAst
    of gpuTypeDef:
      tTyp*: GpuType ## the actual type. Used to generate the name
      tFields*: seq[GpuTypeField]
    of gpuAlias:
      aTyp*: GpuType ## Name of the type alias
      aTo*: GpuAst ## Type the alias maps to
      aDistinct*: bool ## If the alias is a distinct type in Nim.
    of gpuObjConstr:
      ocType*: GpuType  # type we construct
      ## XXX: it would be better if we already fill the fields with default values here
      ocFields*: seq[GpuFieldInit] # the fields we initialize
    of gpuInlineAsm:
      stmt*: string
    of gpuComment:
      comment*: string
    of gpuConv:
      convTo*: GpuType # type to cast to
      convExpr*: GpuAst # expression we convert
    of gpuCast:
      cTo*: GpuType # type to cast to
      cExpr*: GpuAst # expression we cast
    of gpuAddr:
      aOf*: GpuAst
    of gpuDeref:
      dOf*: GpuAst

  GpuSymbolKind* = enum
    gsNone,              ## Default to mark not explicitly set
    gsDeviceKernelParam, ## Parameter of a device kernel (`function`)
    gsGlobalKernelParam, ## Parameter of a global kernel (`storage`) for WebGPU
    gsLocal,             ## Local variable (`function`)
    gsProc,              ## Kernel
    gsShared,            ## A shared variable (`{.shared.}` / `workspace`)
    gsPrivate,           ## A private variable (to each thread)

  ## WebGPU only: Address space of a variable.
  ## - storage: Storage buffer allocated on host and passed to device
  ## - function: Local variable within a function
  ## - workspace: Shared variable for all execution units in a block (like CUDA `shared`)
  ## - uniform: ??
  ## - private: Each thread has its own instance of the variable, e.g. useful for `carry`
  ## On the CUDA backend the address space is ignored.
  AddressSpace* = enum
    asFunction = "function"
    asStorage = "storage"
    asWorkspace = "workspace"
    asUniform = "uniform"
    asPrivate = "private"

  ## XXX: maybe merge into `GpuAst`, then can be kept in same table as `gpuVar` for locals
  GpuParam* = object
    ident*: GpuAst ## The actual parameter symbol, `GpuIdent`
    typ*: GpuType
    addressSpace*: AddressSpace

  GpuFieldInit* = object
    name*: string
    value*: GpuAst
    typ*: GpuType

  ## XXX: UNUSED
  TemplateInfo* = object
    params*: seq[string]
    body*: GpuAst

  GpuProcSignature* = object
    params*: seq[GpuParam]
    retType*: GpuType

  GpuContext* = object
    ## XXX: need table for generic invocations. Then when we encounter a type, need to map to
    ## the specific version
    ## However, also need to keep every *generic procedure*. In their bodies the types are
    ## only defined once they are called after all.
    skipSemicolon*: bool # whether we *currently* add semicolons at the end of a block or not
    ## XXX: UNUSED
    templates*: Table[string, TemplateInfo]  # Maps template names to their info
    allFnTab*: OrderedTable[GpuAst, GpuAst] ## map of all function definitions. For easy lookup by identifier
                                 ## Key is the `GpuAst` of the functions identifier / symbol
    fnTab*: OrderedTable[GpuAst, GpuAst] ## Map only of those function we generate code for. Includes
                                        ## generically instantiated functions.
    globalBlocks*: seq[GpuAst] ## Blocks in the global space. E.g. type defs or global variables.
    ## XXX: for now globals only store parameters, but we need to store `GpuAst` so that we can
    ## also add manually added globals or lifted `{.shared.}` variables!
    ## NOTE: The `globals` must store the type *AS IT WAS WRITTEN* in the Nim code. Any potential
    ## modifications we make locally for WebGPU (e.g. convert `bool` to `i32` for a global
    ## argument), must not be made to them. `globals` is used precisely to handle the *result* of
    ## that kind of transformation.
    ## As a result, the `globals` also *ONLY* contains the unique symbol as a key and not a `GpuAst`.
    globals*: OrderedTable[string, GpuParam] #Table[GpuAst, GpuAst] ## Maps global symbols (`{.shared.}` lifted to global, manually defined in global,
                         ## or `storage` buffer identifiers to the type? XXX to what?
    sigTab*: Table[string, GpuAst] ## Map the `nnkSym.signatureHash` to a `GpuAst` of kind `GpuIdent`
    #scopeStack: seq[Locals] ## Stack of all local variables. When we descend into processing a block, we push to the stack
    #                        ## when we finish, we pop. Before we pop, we assign the variable definitions to the `gpuBlock`
    #                        ## `locals`
    genSymCount*: int ## increases for every generated identifier (currently only underscore `_`), hence the basic solution
    ## Maps a struct type and field name, which is of pointer type to the value the user assigns
    ## in the constructor. Allows us to later replace `foo.ptrField` by the assignment in the `Foo()`
    ## constructor (WebGPU only).
    structsWithPtrs*: Table[(GpuType, string), GpuAst]
    ## Set of all generic proc names we have encountered in Nim -> GpuAst. When
    ## we see an `nnkCall` we check if we call a generic function. If so, look up
    ## the instantiated generic, parse it and store in `genericInsts` below.
    generics*: HashSet[string]

    ## Stores the unique identifiers (keys) and the implementations of the
    ## precise generic instantiations that are called.
    genericInsts*: OrderedTable[GpuAst, GpuAst]

    ## Table of procs and their signature to avoid looping infinitely for recursive procs
    ## Arguments are:
    ## - Key: ident of the proc
    ## - Value: signature of the (possibly generic) instantiation
    processedProcs*: OrderedTable[GpuAst, GpuProcSignature]

    ## Storse all builtin / nimonly / importc / ... functions we encounter so that we can
    ## check if they return a value when we encounter them in a `gpuCall`
    builtins*: OrderedTable[GpuAst, GpuAst]

    ## Table of all known types. Filled during Nim -> GpuAst. Includes generic
    ## instantiations, but also all other types.
    ## Key: the raw type. Value: a full `gpuTypeDef`
    types*: OrderedTable[GpuType, GpuAst]

    ## This is _effectively_ just a set of all already produced function symbols.
    ## We use it to determine if when encountering another function with the same
    ## name, but different arguments to instead of using `iName` to use `iSym` as
    ## the function name. This is to avoid overload issues in backends that don't
    ## allow overloading by function signatures.
    symChoices*: HashSet[string]

  ## We rely on being able to compute a `newLit` from the result of `toGpuAst`. Currently we
  ## only need the `genericInsts` field data (the values). Trying to `newLit` the full `GpuContext`
  ## causes trouble.
  GpuGenericsInfo* = object
    procs*: seq[GpuAst]
    types*: seq[GpuAst]

  GenericArg* = object
    addrSpace*: AddressSpace ## We store the address space, because that's what matters
    mutable*: bool # if the argument is mutable or not
  GenericInst* = object
    name*: string # unique name of this generic variant
    args*: seq[GenericArg] # kind of symbols passed in at the call site. To determine ptr types, if args are ptrs
    # types are not stored in the instantiation, because we look up the types from the original function when generating the code

proc newGpuIdent*(ident: string = "", symKind: GpuSymbolKind = gsNone): GpuAst =
  result = GpuAst(kind: gpuIdent, iName: ident, symbolKind: symKind)

proc clone*(typ: GpuType): GpuType =
  ## Returns a clone of the input type
  result = GpuType(kind: typ.kind)
  case result.kind
  of gtPtr:
    result.to = typ.to.clone()
    result.implicit = typ.implicit
    result.mutable = typ.mutable
  of gtUA:
    result.uaTo = typ.uaTo.clone()
  of gtObject:
    result.name = typ.name
    for f in typ.oFields:
      result.oFields.add GpuTypeField(name: f.name, typ: f.typ.clone())
  of gtArray:
    result.aTyp = typ.aTyp.clone()
    result.aLen = typ.aLen
  of gtGenericInst:
    result.gName = typ.gName
    for g in typ.gArgs:
      result.gArgs.add g.clone()
    for f in typ.gFields:
      result.gFields.add GpuTypeField(name: f.name, typ: f.typ.clone())
  else: discard

proc clone*(ast: GpuAst): GpuAst =
  if ast.isNil: return nil
  case ast.kind
  of gpuVoid: result = GpuAst(kind: gpuVoid)
  of gpuProc:
    result = GpuAst(kind: gpuProc)
    result.pName = ast.pName.clone()
    result.pRetType = ast.pRetType.clone()
    for p in ast.pParams:
      let clonedParam = GpuParam(
        ident: p.ident.clone(),
        typ: p.typ.clone(),
        addressSpace: p.addressSpace
      )
      result.pParams.add(clonedParam)
    result.pBody = ast.pBody.clone()
    result.pAttributes = ast.pAttributes
    result.forwardDeclare = result.forwardDeclare
  of gpuCall:
    result = GpuAst(kind: gpuCall)
    result.cIsExpr = ast.cIsExpr
    result.cName = ast.cName.clone()
    for arg in ast.cArgs:
      result.cArgs.add(arg.clone())
  of gpuTemplateCall:
    result = GpuAst(kind: gpuTemplateCall)
    result.tcName = ast.tcName.clone()
    for arg in ast.tcArgs:
      result.tcArgs.add(arg.clone())
  of gpuIf:
    result = GpuAst(kind: gpuIf)
    result.ifCond = ast.ifCond.clone()
    result.ifThen = ast.ifThen.clone()
    result.ifElse = ast.ifElse.clone()
  of gpuFor:
    result = GpuAst(kind: gpuFor)
    result.fVar = ast.fVar.clone()
    result.fStart = ast.fStart.clone()
    result.fEnd = ast.fEnd.clone()
    result.fBody = ast.fBody.clone()
  of gpuWhile:
    result = GpuAst(kind: gpuWhile)
    result.wCond = ast.wCond.clone()
    result.wBody = ast.wBody.clone()
  of gpuBinOp:
    result = GpuAst(kind: gpuBinOp)
    result.bOp = ast.bOp.clone()
    result.bLeft = ast.bLeft.clone()
    result.bRight = ast.bRight.clone()
    result.bLeftTyp = ast.bLeftTyp.clone()
    result.bRightTyp = ast.bRightTyp.clone()
  of gpuVar:
    result = GpuAst(kind: gpuVar)
    result.vName = ast.vName.clone()
    result.vType = ast.vType.clone()
    result.vInit = ast.vInit.clone()
    result.vRequiresMemcpy = ast.vRequiresMemcpy
    result.vMutable = ast.vMutable
    result.vAttributes = ast.vAttributes
  of gpuAssign:
    result = GpuAst(kind: gpuAssign)
    result.aLeft = ast.aLeft.clone()
    result.aRight = ast.aRight.clone()
    result.aRequiresMemcpy = ast.aRequiresMemcpy
  of gpuIdent:
    result = GpuAst(kind: gpuIdent)
    result.iName = ast.iName
    result.iSym = ast.iSym
    if ast.iTyp != nil:
      result.iTyp = ast.iTyp.clone()
    result.symbolKind = ast.symbolKind
  of gpuLit:
    result = GpuAst(kind: gpuLit)
    result.lValue = ast.lValue
    result.lType = ast.lType.clone()
  of gpuConstexpr:
    result = GpuAst(kind: gpuConstexpr)
    result.cIdent = ast.cIdent.clone()
    result.cValue = ast.cValue.clone()
    result.cType = ast.cType.clone()
  of gpuArrayLit:
    result = GpuAst(kind: gpuArrayLit)
    for a in ast.aValues:
      result.aValues.add a.clone()
    result.aLitType = ast.aLitType.clone()
  of gpuPrefix:
    result = GpuAst(kind: gpuPrefix)
    result.pOp = ast.pOp
    result.pVal = ast.pVal.clone()
  of gpuBlock:
    result = GpuAst(kind: gpuBlock)
    result.isExpr = ast.isExpr
    result.blockLabel = ast.blockLabel
    for stmt in ast.statements:
      result.statements.add(stmt.clone())
  of gpuReturn:
    result = GpuAst(kind: gpuReturn)
    result.rValue = ast.rValue.clone()
  of gpuDot:
    result = GpuAst(kind: gpuDot)
    result.dParent = ast.dParent.clone()
    result.dField = ast.dField.clone()
  of gpuIndex:
    result = GpuAst(kind: gpuIndex)
    result.iArr = ast.iArr.clone()
    result.iIndex = ast.iIndex.clone()
  of gpuTypeDef:
    result = GpuAst(kind: gpuTypeDef)
    result.tTyp = ast.tTyp.clone()
    for f in ast.tFields:
      result.tFields.add(GpuTypeField(name: f.name, typ: f.typ.clone()))
  of gpuAlias:
    result = GpuAst(kind: gpuAlias)
    result.aTyp = ast.aTyp.clone()
    result.aTo = ast.aTo.clone()
  of gpuObjConstr:
    result = GpuAst(kind: gpuObjConstr)
    result.ocType = ast.ocType.clone()
    for f in ast.ocFields:
      result.ocFields.add(
        GpuFieldInit(
          name: f.name,
          value: f.value.clone(),
          typ: f.typ.clone()
        )
      )
  of gpuInlineAsm:
    result = GpuAst(kind: gpuInlineAsm)
    result.stmt = ast.stmt
  of gpuAddr:
    result = GpuAst(kind: gpuAddr)
    result.aOf = ast.aOf.clone()
  of gpuDeref:
    result = GpuAst(kind: gpuDeref)
    result.dOf = ast.dOf.clone()
  of gpuConv:
    result = GpuAst(kind: gpuConv)
    result.convTo = ast.convTo.clone()
    result.convExpr = ast.convExpr.clone()
  of gpuCast:
    result = GpuAst(kind: gpuCast)
    result.cTo = ast.cTo.clone()
    result.cExpr = ast.cExpr.clone()
  of gpuComment:
    result = GpuAst(kind: gpuComment)
    result.comment = ast.comment

proc hash*(t: GpuType): Hash =
  var h = 0
  h = h !& hash(t.kind)
  case t.kind
  of gtPtr:
    h = h !& hash(t.to)
    h = h !& hash(t.implicit)
  of gtUA:
    h = h !& hash(t.uaTo)
  of gtObject:
    h = h !& hash(t.name)
    for f in t.oFields:
      h = h !& hash(f)
  of gtArray:
    h = h !& hash(t.aTyp)
    h = h !& hash(t.aLen)
  of gtGenericInst:
    h = h !& hash(t.gName)
    for g in t.gArgs:
      h = h !& hash(g)
    for f in t.gFields:
      h = h !& hash(f)
  else: discard
  result = !$ h

proc hash*(n: GpuAst): Hash =
  doAssert n.kind == gpuIdent, "Cannot hash a value other than `gpuIdents`! Input is: " & $n.kind
  var h = 0
  h = h !& hash(n.iSym) # In theory the only thing relevant is the `iSym`, as it is unique per Nim symbol
                        # but if we fail to update a type or symbolkind, we'd produce a different hash, which is good
  if n.iTyp != nil: # can be nil, e.g. `gpuProc` symbols don't define it
    h = h !& hash(n.iTyp)
  h = h !& hash(n.symbolKind)
  result = !$ h

proc `==`*(a, b: GpuType): bool =
  # If either or both are nil, they don't match
  if a.isNil or b.isNil: result = false
  elif a.kind != b.kind: result = false
  else:
    result = true
    case a.kind
    of gtPtr: result = a.to == b.to and a.implicit == b.implicit
    of gtUA:  result = a.uaTo == b.uaTo
    of gtObject:
      result = a.name == b.name
      if a.oFields.len != b.oFields.len: result = false
      else:
        for i in 0 ..< a.oFields.len:
          result = result and (a.oFields[i] == b.oFields[i])
    of gtGenericInst:
      result = a.gName == b.gName
      if a.gArgs.len != b.gArgs.len: result = false
      elif a.gFields.len != b.gFields.len: result = false
      else:
        for i in 0 ..< a.gArgs.len:
          result = result and (a.gArgs[i] == b.gArgs[i])
        for i in 0 ..< a.gFields.len:
          result = result and (a.gFields[i] == b.gFields[i])
    of gtArray: result = a.aTyp == b.aTyp and a.aLen == b.aLen
    else: discard

proc `==`*(a, b: GpuAst): bool =
  if a.kind != b.kind: result = false
  elif a.kind != gpuIdent:
    raiseAssert "Unsupported equality for GpuAst that are not idents"
  else:
    result = a.iSym == b.iSym and a.iTyp == b.iTyp and a.symbolKind == b.symbolKind

proc `==`*(a, b: GpuProcSignature): bool =
  if a.retType != b.retType: result = false
  elif a.params.len != b.params.len:
    result = false
  else:
    result = true
    for i in 0 ..< a.params.len:
      let ap = a.params[i]
      let bp = b.params[i]
      result = result and (ap == bp)

proc len*(ast: GpuAst): int =
  case ast.kind
  of gpuProc:      1
  of gpuCall:      1 + ast.cArgs.len
  of gpuBlock:     ast.statements.len
  of gpuIf:
    if ast.ifElse.kind != gpuVoid: 3
    else:          2
  of gpuFor:       3
  of gpuWhile:     2
  of gpuBinOp:     2
  of gpuVar:       1
  of gpuAssign:    2
  of gpuPrefix:    1
  of gpuReturn:    1
  of gpuDot:       2
  of gpuIndex:     2
  of gpuObjConstr: ast.ocFields.len
  of gpuAddr:      1
  of gpuDeref:     1
  of gpuConv:      1
  of gpuCast:      1
  of gpuConstexpr: 2
  else: 0

proc `$`*(x: GpuType): string =
  if x == nil:
    result = "GpuType(nil)"
  else:
    result = $x[]

proc removePrefix(s, p: string): string =
  result = s
  result.removePrefix(p)

proc pretty*(t: GpuType): string =
  ## returns a flat (but lossy) string representation of the type
  if t == nil:
    result = "GpuType(nil)"
  else:
    case t.kind
    of gtPtr:
      result = if t.implicit: "var " else: "ptr "
      result.add pretty(t.to)
    of gtUA:
      result = "UncheckedArray[" & t.uaTo.pretty() & "]"
    of gtObject:
      result = t.name # just the name
    of gtArray:
      result = "array[" & $t.aLen & ", " & t.aTyp.pretty() & "]"
    of gtGenericInst:
      result = t.gName & "["
      for i, g in t.gArgs:
        result.add pretty(g)
        if i < t.gArgs.high:
          result.add ", "
      result.add "]"
    else:
      result = ($t.kind).removePrefix("gt")

proc pretty*(n: GpuAst, indent: int = 0): string =
  template id(): untyped = repeat(" ", indent)
  template idn(x): untyped = repeat(" ", indent) & $x
  template iddn(x): untyped = repeat(" ", indent + 2) & $x
  template id(x): untyped = idn(x) & "\n"
  template idd(x): untyped = iddn(x) & "\n"
  template id(x,y): untyped = repeat(" ", indent) & $x & " " & $y & "\n"
  template idd(x,y): untyped = repeat(" ", indent + 2) & $x & " " & $y & "\n"
  template spl(x): untyped = " " & $x & "\n"
  if n.isNil: return id("nil")

  result = idn(($n.kind).removePrefix("gpu"))
  if n.len > 0: result.add "\n"
  case n.kind
  of gpuVoid: result.add "\n"
  of gpuProc:
    result.add pretty(n.pName, indent + 2)
    result.add idd("RetType", n.pRetType)
    result.add idd("Params")
    for p in n.pParams:
      result.add pretty(p.ident, indent + 4)
    result.add pretty(n.pBody, indent + 2)
    if n.pAttributes.len > 0:
      result.add idd("Attributes")
      for attr in n.pAttributes:
        let indent = indent + 2
        result.add idd(attr)
  of gpuCall:
    result.add pretty(n.cName, indent + 2)
    for arg in n.cArgs:
      result.add pretty(arg, indent + 2)
  of gpuTemplateCall: discard
  of gpuIf:
    result.add idd("IfCond")
    result.add pretty(n.ifCond, indent + 4)
    result.add idd("IfThen")
    result.add pretty(n.ifThen, indent + 4)
    if n.ifElse.kind != gpuVoid:
      result.add idd("IfElse")
      result.add pretty(n.ifElse, indent + 4)
  of gpuFor:
    result.add pretty(n.fVar, indent + 2)
    result.add pretty(n.fStart, indent + 2)
    result.add pretty(n.fEnd, indent + 2)
    result.add pretty(n.fBody, indent + 2)
  of gpuWhile:
    result.add pretty(n.wCond, indent + 2)
    result.add pretty(n.wBody, indent + 2)
  of gpuBinOp:
    result.add pretty(n.bOp, indent + 2)
    result.add pretty(n.bLeft, indent + 2)
    result.add pretty(n.bRight, indent + 2)
  of gpuVar:
    result.add pretty(n.vName, indent + 2)
    result.add pretty(n.vInit, indent + 2)
    if n.vAttributes.len > 0:
      result.add idd("Attributes")
      for attr in n.vAttributes:
        let indent = indent + 2
        result.add idd(attr)
  of gpuAssign:
    result.add pretty(n.aLeft, indent + 2)
    result.add pretty(n.aRight, indent + 2)
  of gpuIdent:
    result.add spl(n.iName & "(" & n.iSym & ")")
  of gpuLit:
    result.add spl(n.lValue)
  of gpuConstexpr:
    result.add pretty(n.cIdent, indent + 2)
    result.add pretty(n.cValue, indent + 2)
  of gpuArrayLit:
    for el in n.aValues:
      result.add pretty(el, indent + 2)
  of gpuBlock:
    if n.blockLabel.len > 0:
      result.add id("Label", n.blockLabel)
    for stmt in n.statements:
      result.add pretty(stmt, indent + 2)
  of gpuReturn:
    result.add pretty(n.rValue, indent + 2)
  of gpuDot:
    result.add pretty(n.dParent, indent + 2)
    result.add pretty(n.dField, indent + 2)
  of gpuIndex:
    result.add pretty(n.iArr, indent + 2)
    result.add pretty(n.iIndex, indent + 2)
  of gpuPrefix:
    result.add id("Op", n.pOp)
    result.add pretty(n.pVal, indent + 2)
  of gpuTypeDef:
    result.add id("Type", pretty(n.tTyp))
    result.add id("Fields")
    for t in n.tFields:
      let indent = indent + 2
      result.add id(t.name)
  of gpuAlias:
    result.add id("Alias", pretty(n.aTyp))
    result.add pretty(n.aTo, indent + 2)
  of gpuObjConstr:
    result.add idd("Ident", pretty(n.ocType))
    result.add idd("Fields")
    for f in n.ocFields:
      var indent = indent + 2
      result.add idd("Field")
      indent = indent + 2
      result.add idd("Name", f.name)
      result.add pretty(f.value, indent + 2)
  of gpuInlineAsm:
    result.add id(n.stmt)
  of gpuComment:
    result.add id(n.comment)
  of gpuConv:
    result.add id($n.convTo)
    result.add pretty(n.convExpr, indent + 2)
  of gpuCast:
    result.add id($n.cTo)
    result.add pretty(n.cExpr, indent + 2)
  of gpuAddr:
    result.add pretty(n.aOf, indent + 2)
  of gpuDeref:
    result.add pretty(n.dOf, indent + 2)

proc `$`*(n: GpuAst): string =
  result = pretty(n, 0)

template iterImpl(ast: untyped, mutable: static bool): untyped =
  template ya(field: untyped): untyped =
    yield ast.field
  case ast.kind
  of gpuProc: # body
    ya(pBody)
  of gpuCall: # args
    when mutable:
      for el in mitems(ast.cArgs):
        yield el
    else:
      for el in ast.cArgs:
        yield el
  of gpuIf:
    ya(ifCond)
    ya(ifThen)
    if ast.ifElse.kind != gpuVoid:
      yield ast.ifElse
  of gpuFor:
    ya(fStart)
    ya(fEnd)
    ya(fBody)
  of gpuWhile:
    ya(wCond)
    ya(wBody)
  of gpuBinOp:
    ya(bLeft)
    ya(bRight)
  of gpuVar:
    ya(vInit)
  of gpuAssign:
    ya(aLeft)
    ya(aRight)
  of gpuPrefix:
    ya(pVal)
  of gpuBlock:
    when mutable:
      for ch in mitems(ast.statements):
        yield ch
    else:
      for ch in ast.statements:
        yield ch
  of gpuReturn:
    ya(rValue)
  of gpuDot:
    ya(dParent)
    ya(dField)
  of gpuIndex:
    ya(iArr)
    ya(iIndex)
  of gpuObjConstr:
    when mutable:
      for el in mitems(ast.ocFields):
        yield el.value
    else:
      for el in ast.ocFields:
        yield el.value
  of gpuAddr:
    ya(aOf)
  of gpuDeref:
    ya(dOf)
  of gpuConv:
    ya(convExpr)
  of gpuCast:
    ya(cExpr)
  of gpuConstexpr:
    ya(cIdent)
    ya(cValue)
  else:
    discard # nothing to yield

iterator mitems*(ast: var GpuAst): var GpuAst =
  ## Iterate over all child nodes of the given AST
  iterImpl(ast, mutable = true)

iterator items*(ast: GpuAst): GpuAst =
  iterImpl(ast, mutable = false)

iterator mpairs*(ast: var GpuAst): (int, var GpuAst) =
  ## Iterate over all child nodes of the given AST and the index
  var i = 0
  for el in mitems(ast):
    yield (i, el)
    inc i

iterator pairs*(ast: GpuAst): (int, GpuAst) =
  var i = 0
  for el in items(ast):
    yield (i, el)
    inc i


## General utility helpers

proc ident*(n: GpuAst): string =
  ## Returns the associated identifier (string) of the given symbol. The input
  ## must be a `gpuIdent`
  doAssert n.kind == gpuIdent, "The input is not a `gpuIdent`, but a " & $n.kind
  result = n.iName

template withoutSemicolon*(ctx: var GpuContext, body: untyped): untyped =
  if not ctx.skipSemicolon: # if we are already skipping, leave true
    ctx.skipSemicolon = true
    body
    ctx.skipSemicolon = false
  else:
    body

proc getInnerArrayLengths*(t: GpuType): string =
  ## Returns the lengths of the inner array types for a nested array.
  case t.kind
  of gtArray:
    let inner = getInnerArrayLengths(t.aTyp)
    result = &"[{$t.aLen}]"
    if inner.len > 0:
      result.add &"{inner}"
  else:
    result = ""
