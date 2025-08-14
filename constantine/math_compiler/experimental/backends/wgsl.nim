# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import std / [macros, strformat, strutils, sugar, sequtils, tables, sets, options]

import ../gpu_types

import ./common_utils

proc gpuTypeToString*(t: GpuType,
                      id: GpuAst = newGpuIdent(),
                      allowArrayToPtr = false,
                      allowEmptyIdent = false): string

proc size*(ctx: var GpuContext, a: GpuType): string = size(gpuTypeToString(a, allowEmptyIdent = true))

proc literalSuffix(t: GpuType): string =
  ## Returns the correct literal suffix for the given literal value for the WebGPU target
  case t.kind
  of gtUint32: "u"
  of gtInt32: "" # NOTE: We DON'T give as suffix to `i32` literals so that we can rely on more cases
                 # where WebGPU allows literals to be converted automatically!
  of gtFloat32: "f"
  else: ""

proc toAddressSpace(symKind: GpuSymbolKind): AddressSpace =
  case symKind
  of gsDeviceKernelParam: asFunction
  of gsGlobalKernelParam: asStorage
  of gsLocal: asFunction
  of gsShared: asWorkspace
  of gsPrivate: asPrivate
  of gsNone:
    asFunction
    #raiseAssert "Encountered a node without a symbol kind!"
  of gsProc:
    raiseAssert "Encountered a procedure symbol in the context of a type for a variable"

proc fromAddressSpace(addrSpace: AddressSpace): GpuSymbolKind =
  ## Very *lossy* conversion back from an address space. Only purpose is to assign a symbol kind
  ## for identifiers in the context of generic instantiations to then get the correct address
  ## space back. Hence multiple map to `gsLocal` as that maps to `function`.
  case addrSpace
  of asFunction: gsLocal
  of asStorage: gsGlobalKernelParam
  of asWorkspace: gsShared
  of asPrivate: gsPrivate
  of asUniform: raiseAssert "Uniform address space not supported yet"


proc constructPtrSignature(addrSpace: AddressSpace, idTyp: GpuType, ptrStr, typStr: string): string =
  ## Constructs the `ptr<addressSpace, typStr, [read / read_write]>` string, which only includes
  ## the RW string if the address space is `storage`
  let rw = if idTyp.kind != gtVoid: idTyp.mutable else: false # symbol is a pointer -> mutable (can be implicit via `var T`)
  let rwStr = if rw: "read_write" else: "read"
  case addrSpace
  of asStorage: result = &"{ptrStr}<{addrSpace}, {typStr}, {rwStr}>"
  else:         result = &"{ptrStr}<{addrSpace}, {typStr}>"

proc gpuTypeToString*(t: GpuTypeKind): string =
  case t
  of gtBool: "bool"
  of gtUint32: "u32"
  of gtInt32: "i32"
  of gtFloat32: "f32"
  of gtVoid: ""
  of gtSize_t: "u32" ##: Acceptable mapping?
  of gtPtr: "ptr" ## XXX: needs address space and target type, `ptr<address_space, target_type>`
  of gtUA: "array"
  of gtObject: "struct"
  of gtUint8, gtUint16, gtUint64, gtInt16, gtInt64, gtFloat64, gtVoidPtr, gtString:
    raiseAssert "The type " & $t & " does not exist on the WebGPU target."
  else:
    raiseAssert "Invalid type : " & $t

proc gpuTypeToString*(t: GpuType, id: GpuAst = newGpuIdent(), allowArrayToPtr = false,
                           allowEmptyIdent = false,
                    ): string =
  ## WebGPU type generation is a bit more complicated than CUDA, due to their pointer semantics.
  var skipIdent = false
  let ident = id.ident() # get the ident from the `gpuIdent`
  case t.kind
  of gtPtr:
    # Let `foo` be the symbol `id`. If for example we generate code for `addr(foo)`, the type
    # `t` will be `ptr typeof(foo)`. The type of the symbol `id` though is static.
    # Thus, can use `id's` type to determine if we need mutability or not. If `id` was a
    # pointer, `mutable` will be true and `false` otherwise.
    # If code called with default `id`, type will be nil
    let addrSpace = id.symbolKind.toAddressSpace()
    let ptrStr = gpuTypeToString(t.kind)
    let typStr = gpuTypeToString(t.to, allowEmptyIdent = true)
    result = constructPtrSignature(addrSpace, id.iTyp, ptrStr, typStr)
  of gtArray:
    # empty idents happen in e.g. function return types or casts
    if ident.len == 0 and not allowEmptyIdent: # and not allowArrayToPtr:
      #error("Invalid call, got an array type but don't have an identifier: " & $t)

      when nimvm:
        error("Invalid call, got an array type but don't have an identifier: " & $t)
      else:
        raise newException(ValueError, "Invalid call, got an array type but don't have an identifier: " & $t)

    let identPrefix = if ident.len > 0: ident & ": " else: ""
    let typ = gpuTypeToString(t.aTyp, allowEmptyIdent = true)
    if t.aLen == 0:
      result = &"{identPrefix}array<{typ}>"
    else:
      result = &"{identPrefix}array<{typ}, {t.aLen}>"
    skipIdent = true
  of gtObject: result = t.name
  of gtUA:     result = gpuTypeToString(t.kind) & "<" & gpuTypeToString(t.uaTo, allowEmptyIdent = allowEmptyIdent) & ">"
  else:        result = gpuTypeToString(t.kind)

  if ident.len > 0 and not skipIdent: # still need to add ident
    result = ident & ": " & result

proc genFunctionType*(typ: GpuType, fn: string, fnArgs: string): string =
  ## Returns the correct function with its return type
  if typ.kind == gtPtr and typ.to.kind == gtArray:
    ## TODO!
    # crazy stuff. Syntax to return a pointer to a statically sized array:
    # `Foo (*fnName(fnArgs))[ArrayLen]`
    # where the return type is actually:
    # `Foo (*)[ArrayLen]` (which already is hideous)
    let arrayTyp = typ.to.aTyp
    let innerTyp = gpuTypeToString(arrayTyp, allowEmptyIdent = true)
    let innerLen = $typ.to.aLen
    ## XXX: wrong
    result = &"{innerTyp} (*{fn}({fnArgs}))[{innerLen}]"
  else:
    # normal stuff
    result = &"{fn}({fnArgs})"
    let typ = gpuTypeToString(typ, allowEmptyIdent = true)
    if typ.len > 0:
      result.add &" -> {typ}"

proc isGlobal(fn: GpuAst): bool =
  doAssert fn.kind == gpuProc, "Not a function, but: " & $fn.kind
  result = attGlobal in fn.pAttributes

proc farmTopLevel(ctx: var GpuContext, ast: GpuAst, kernel: string, varBlock, typBlock: var GpuAst) =
  ## Farms the top level of the code for functions, variable and type definition.
  ## All functions are added to the `allFnTab`, while only global ones (or even only
  ## `kernel` if any) is added to the `fnTab` as the starting point for the remaining
  ## logic.
  ## Variables and types are collected in `varBlock` and `typBlock`.
  case ast.kind
  of gpuProc:
    ctx.allFnTab[ast.pName] = ast
    if kernel.len > 0 and ast.pName.ident() == kernel and ast.isGlobal():
      ctx.fnTab[ast.pName] = ast.clone() # store global function extra
    elif kernel.len == 0 and ast.isGlobal():
      ctx.fnTab[ast.pName] = ast.clone() # store global function extra
  of gpuBlock:
    # could be a type definition or global variable
    for ch in ast:
      ctx.farmTopLevel(ch, kernel, varBlock, typBlock)
  of gpuVar, gpuConstexpr:
    varBlock.statements.add ast
  of gpuTypeDef:
    typBlock.statements.add ast
  else:
    discard

proc patchType(t: GpuType): GpuType =
  ## Applies patches needed for WGSL support. E.g. `bool` cannot be a storage variable.
  result = t
  if result.kind == gtBool:
    result.kind = gtInt32
  elif result.kind == gtPtr and result.to.kind == gtBool:
    result.to.kind = gtInt32

proc patchSymbol(n: GpuAst): GpuAst =
  ## Applies patches needed for WGSL support. E.g. `bool` cannot be a storage variable.
  doAssert n.kind == gpuIdent, "Must be an ident, is: " & $n.kind
  result = n
  if n.symbolKind == gsGlobalKernelParam:
    result.iTyp = patchType(result.iTyp)

proc shortAddrSpace(addrSpace: AddressSpace): string =
  ## Shortens the address space to a single letter
  case addrSpace
  of asFunction: "l"
  of asUniform: "u"
  of asWorkspace: "w"
  of asPrivate: "p"
  of asStorage: "s"

proc determineSymKind(arg: GpuAst): GpuSymbolKind =
  ## Tries to determine the symbol kind of the argument.
  case arg.kind
  of gpuIdent: arg.symbolKind
  of gpuAddr: arg.aOf.determineSymKind()
  of gpuDeref: arg.dOf.determineSymKind()
  of gpuCall: gsLocal ## return value will be in local function scope?
  of gpuIndex: arg.iArr.determineSymKind()
  of gpuDot: arg.dParent.determineSymKind()
  of gpuLit: gsLocal
  of gpuBinOp: gsLocal # equivalent to constructing a local var
  of gpuBlock: arg.statements[^1].determineSymKind() # look at last element
  of gpuPrefix: gsLocal # equivalent to constructing a local var
  of gpuConv: gsLocal # a converted value will be a local var
  of gpuCast: arg.cExpr.determineSymKind() # symbol kind of the thing we cast
  else:
    raiseAssert "Not implemented to determine symbol kind from node: " & $arg

proc determineMutability(arg: GpuAst): bool =
  ## Tries to determine the mutability of the underlying symbol (for the context of
  ## determining the `read` or `read_write` property of a pointer; not whether
  ## it is a `let` or `var` symbol)
  case arg.kind # XXX: Consider to extend notion of mutable to `var` variables in Nim? I.e. assign `mutable`
                # if we construct a `var` instead of a let?
  of gpuIdent: (not arg.iTyp.isNil) and arg.iTyp.kind == gtPtr
  of gpuAddr: true # If we can take an address from it, it is mutable. E.g. `var t = BigInt(); t.add(r, a)` contains `addr t` in `add` call
  of gpuDeref: true # Similar to `addr`, if we can deref it must be mutable? Or it's explicitly _not_ mutable? arg.dOf.determineMutability() ## XXX: Or just mutable because it can be derefed?
  of gpuCall: false # can't return a mutable value from a function in WGSL
  of gpuIndex: arg.iArr.determineMutability()
  of gpuDot: arg.dParent.determineMutability()
  of gpuLit: false
  of gpuBinOp: false # equivalent to constructing a local var
  of gpuBlock: arg.statements[^1].determineMutability() # look at last element
  of gpuPrefix: false # equivalent to constructing a local var
  of gpuConv: false # a converted value will be immutable
  of gpuCast: arg.cExpr.determineMutability() # mutability of the thing we cast
  else:
    raiseAssert "Not implemented to determine mutability from node: " & $arg

proc determineIdent(arg: GpuAst): GpuAst =
  ## Tries to determine the underlying ident that is contained in this node.
  ## The issue is the argument to a `gpuCall` can be a complicated expression.
  ## Depending on the node it may be possible to extract a simple identifier,
  ## e.g. for `addr(foo)` (`gpuAddr` of `gpuIdent` node) we can get the ident.
  ## If this fails, we return a `gpuVoid` node.
  ##
  ## TODO: Think about if it ever makes sense to extract the ident underlying
  ## e.g. `deref` and use _that_ to determine mutability & address space.
  template dfl(): untyped = GpuAst(kind: gpuVoid)
  case arg.kind
  of gpuIdent: arg
  of gpuAddr: arg.aOf.determineIdent()
  of gpuDeref: arg.dOf.determineIdent()
  of gpuCall: dfl()
  of gpuIndex: arg.iArr.determineIdent()
  of gpuDot: arg.dParent.determineIdent()
  of gpuLit: dfl()
  of gpuBinOp: dfl()
  of gpuBlock: arg.statements[^1].determineIdent()
  of gpuPrefix: dfl()
  of gpuConv: dfl()
  of gpuCast: arg.cExpr.determineIdent() # ident of the thing we cast
  else:
    raiseAssert "Not implemented to determine ident from node: " & $arg

proc getGenericArguments(args: seq[GpuAst], params: seq[GpuParam], callerParams: Table[string, GpuParam]): seq[GenericArg] =
  ## If an argument is not a ptr argument in the original function (`params`) then
  ## we just return the equivalent of a local, non mutable arg
  ##
  ## `params` are the parameters of the function being called by the `gpuCall` node `n.cName`.
  ## This argument is used to determine if we need to consider each argument of the call
  ## for 'generic-ness' at all or not (only required if pointer type).
  ##
  ## `callerParams` however are the parameters of the function *in which* the call to
  ## `n.cName` happens. This allows us to pass "down" the information of `storage` pointers
  ## recursively. It is a `Table[string, GpuParam]`, so that we can look up a call argument
  ## based on its identifier. Obviously we have to use `string` keys, because otherwise
  ## the information we precisely want to extract (different symbol kind etc) would make
  ## it so that we cannot look up elements.
  for i, arg in args:
    let p = params[i]
    if p.typ.kind != gtPtr: # not a pointer argument, fixed
      result.add GenericArg(addrSpace: asFunction, mutable: false)
    else:
      let argIdent = arg.determineIdent()
      var lArg: GpuAst = arg
      if argIdent.kind != gpuVoid and argIdent.iSym in callerParams: # if it exists, we look up information based on _that_ argument instead
        lArg = callerParams[argIdent.iSym].ident

      let addrSpace = determineSymKind(lArg).toAddressSpace()
      let mutable = determineMutability(lArg)
      result.add GenericArg(addrSpace: addrSpace, mutable: mutable)

proc genGenericName(n: GpuAst, params: seq[GpuParam], callerParams: Table[string, GpuParam]): string =
  ## Generates a unique name for the given function, derived from the function name.
  ## Taking into account the symbol kinds of each argument.
  ##
  ## Given a WGSL function
  ## `fn foo(x: u32, y: ptr i32)`
  ## and a call site
  ## `foo(a, b)`
  ## where `a` is a local variable and `b` a value passed into the global host side function, then the
  ## generic is called:
  ## `foo_l_gmut`
  ## (suffix lg = local, global) for the arguments and `mut` for the fact that `y`
  ## is a mutable (pointer) argument.
  ##
  ## NOTE: *ANY* argument that is not actually a pointer argument in the original function
  ## definition will always receive an `l` by definition. The type of argument passed into the
  ## call is ignored, because there is nothing to handle on the WGSL side.
  ##
  ## `params` are the parameters of the function being called by the `gpuCall` node `n.cName`.
  ## This argument is used to determine if we need to consider each argument of the call
  ## for 'generic-ness' at all or not (only required if pointer type).
  ##
  ## `callerParams` however are the parameters of the function *in which* the call to
  ## `n.cName` happens. This allows us to pass "down" the information of `storage` pointers
  ## recursively. It is a `Table[string, GpuParam]`, so that we can look up a call argument
  ## based on its identifier. Obviously we have to use `string` keys, because otherwise
  ## the information we precisely want to extract (different symbol kind etc) would make
  ## it so that we cannot look up elements.
  doAssert n.kind == gpuCall, "Not a call, but: " & $n.kind
  result = n.cName.ident() & "_"
  for i, arg in n.cArgs:
    let p = params[i]
    var s: string
    if p.typ.kind != gtPtr: # not a pointer, force `l`
      s = "l"
    else:
      let argIdent = arg.determineIdent()
      var lArg: GpuAst = arg
      if argIdent.kind != gpuVoid and argIdent.iSym in callerParams: # if it exists, we look up information based on _that_ argument instead
        lArg = callerParams[argIdent.iSym].ident
      let addrSpace = lArg.determineSymKind().toAddressSpace()
      let mutable = lArg.determineMutability()
      let m = if mutable: "mut" else: ""
      s = shortAddrSpace(addrSpace) & m
    result.add s
    if i < n.cArgs.high:
      result.add "_"

proc makeFnGeneric(fn: GpuAst, gi: GenericInst): GpuAst =
  ## Returns a (shallow) copy of the input function (which is a clone of the
  ## non generic initial function!), updated such that the parameters
  ## match the requirements by the generic instantiation and its name, including
  ## all symbols in the function body.
  ##
  ## After updating the symbol kinds and types of the parameters, we use that
  ## to also update the information for every occurrence of the parameters in
  ## its function body.
  result = fn
  result.pName = GpuAst(kind: gpuIdent, iName: gi.name, symbolKind: gsProc)
  for i, p in mpairs(result.pParams):
    let arg = gi.args[i]
    # update the symbol kind and address space!
    p.ident.symbolKind = arg.addrSpace.fromAddressSpace()
    p.addressSpace = arg.addrSpace
    if p.ident.iTyp.kind == gtPtr:
      p.ident.iTyp.mutable = arg.mutable
    # now update the type to potentially replace e.g. bool -> i32
    p.ident = patchSymbol(p.ident)
    # overwrite GpuParam `typ` field
    p.typ = p.ident.iTyp

  proc getIf(params: seq[GpuParam], n: GpuAst): Option[GpuParam] =
    ## Returns the parameter if `n` is a `gpuIdent` and its `iSym` is one of the
    ## parameter's symbol
    doAssert n.kind == gpuIdent, "Must be an ident, but is: " & $n.kind
    for p in params:
      if p.ident.iSym == n.iSym: return some(p)

  proc updateSyms(n: var GpuAst, params: seq[GpuParam]) =
    ## Now update all occurences of the symbols corresponding to the parameters
    ## in its function body. We need to update the `symbolKind` for each occurrence,
    ## so that when we recurse _into_ this function, we can determine the correct
    ## type (e.g. `storage` buffer) from _any_ symbol in its body.
    case n.kind
    of gpuIdent:
      let pOpt = params.getIf(n)
      if pOpt.isSome:
        let p = pOpt.get
        n.symbolKind = p.ident.symbolKind
        n.iTyp = p.typ
    else:
      for ch in mitems(n):
        updateSyms(ch, params)
  # Now update all symbols in the function body to have the same symbol kind and type
  updateSyms(result.pBody, result.pParams)

proc scanGenerics(ctx: var GpuContext, n: GpuAst, callerParams: Table[string, GpuParam]) =
  ## Iterates over the given function and checks for all `gpuCall` nodes. Any function
  ## called in the scope is added to `fnTab`. This is a form of dead code elimination.
  ##
  ## If a called function has any pointer arguments, we generate a generic instantiation
  ## of that function (hence the name `scanGenerics`). The generic instance will be added
  ## to `fnTab` instead. The name of the generic will be derived based on the types
  ## of arguments with respect to mutability and address space.
  case n.kind
  of gpuCall:
    let fn = n.cName
    if fn in ctx.allFnTab:
      # Get parameters of function being called, required for generic inst handling
      let params = ctx.allFnTab[fn].pParams
      let gi = GenericInst(name: genGenericName(n, params, callerParams),
                           args: getGenericArguments(n.cArgs, params, callerParams))
      # Check if any of the parameters are pointers (otherwise non generic)
      let anyPointers = params.anyIt(it.typ.kind == gtPtr)
      if anyPointers:
        # replace the call node by the new name
        n.cName = GpuAst(kind: gpuIdent,
                         iName: gi.name,
                         symbolKind: gsProc,
                         iSym: gi.name) # for generics the `iSym` == `iName`. Already unique
        # now scan generics of the function we call, recursing, unless we already processed
        # this exact generic inst
        let gName = n.cName
        if gName notin ctx.fnTab:
          # Get clone of the original function, from which we will build the generic
          # variant. We produce a new function with arguments that reflect the pointer
          # type being *called*. Later we recurse _into_ the generic function, which now
          # has the updated parameters.
          # This way we pass e.g. accesses to storage buffers from the global function
          # recursively as deep into the call stack as needed.
          let fnCalled = ctx.allFnTab[fn].clone() # get a *CLONE* of the original function, so that we can mutate it freely
          let fnGen = makeFnGeneric(fnCalled, gi)
          ctx.fnTab[gName] = fnGen
          ctx.allFnTab[gName] = fnGen # add to `allFnTab`, so that when recurse, generic is found
          # we pass the parameters of _this_ function into the recursive call to pass information
          # of `storage` parameters down. We need to convert them to a table, to allow lookup
          # based on the identifier.
          var callParams = initTable[string, GpuParam]()
          for p in fnGen.pParams: # use the symbol as key. Makes sure it is _that_ symbol and not a local of same name
            callParams[p.ident.iSym] = p
          ctx.scanGenerics(fnGen, callParams)
      elif fn notin ctx.fnTab:
        # If the function does not have pointers in arguments _and_ it is not yet known in `fnTab`,
        # add it from the list of all fns. This code builds up only the non-generic functions actually
        # called from the global.
        let fnCalled = ctx.allFnTab[fn]
        ctx.fnTab[fn] = fnCalled
        # still "scan for generics", i.e. fill `fnTab` from inner calls
        for ch in fnCalled:
          ctx.scanGenerics(ch, callerParams)
      # else we don't do anything for this function
    # Harvest generics from arguments to this call!
    for arg in n.cArgs:
      ctx.scanGenerics(arg, callerParams)
  else:
    for ch in n:
      ctx.scanGenerics(ch, callerParams)


proc injectAddressOf(ctx: var GpuContext, n: var GpuAst) =
  ## Mutates the given AST and replaces every `gpuIdent` that is part of
  ## `ctx.globals` *AND* is of type `ptr` by `gpuAddr(gpuIdent)`.
  ##
  ## We do *NOT* perform the replacement, if the symbol is an implicit pointer type,
  ## that is a `var T` (nnkVarTy / ntyVar on the Nim side)
  ##
  ## This is only needed for `{.global.}` functions, because of the fact that using
  ## `ptr T` arguments leaves us with a disconnect between the `var<storage>` variables
  ## that we lift out from the global function's parameters. Accessing the parameters,
  ## which are *NOT* pointer types, would produce wrong code.
  ##
  ## proc bar(x: ptr BigInt): float = ...
  ## proc foo(x: ptr BigInt) {.global.} =
  ##   bar(x) # valid Nim code, passing pointer
  ##
  ## Becomes:
  ##
  ## var<storage, read_write> x: BigInt;
  ## fn bar(x: ptr<storage, BigInt, read_write>) -> float { ... }
  ## fn foo(@builtin(global_invocation_id) global_id: vec3<u32>) {
  ##   bar(x);
  ## }
  ##
  ## which is invalid code. So inside such global functions we _then_ have to replace
  ## all occurrences of symbols, `x` here, by `x.addr` / `&x`.
  ##
  ##
  ## Secondly, we replace any occurrence of a `ptr bool` identifier by an explicit
  ## conversion from (what will have become) `i32` to `bool`. This is the inverse operation
  ## of replacing `ptr bool` arguments by `i32` globals.
  ##
  ##
  ## Finally, remove the `Deref` any symbol that was a `ptr T` argument, as those are lifted
  ## to simple `T` globals.
  case n.kind
  of gpuIdent:
    if n.iSym in ctx.globals and (let p = ctx.globals[n.iSym]; p.typ.kind == gtPtr):
      # replace by address of
      n = GpuAst(kind: gpuAddr, aOf: n)
    elif n.iSym in ctx.globals and (let p = ctx.globals[n.iSym]; p.typ.kind == gtBool):
      # NOTE: Important that this branch is *after* the above. This implies that we only replace
      # `foo` by `bool(foo)` if this is *NOT* a `ptr bool` type being used somewhere as a pointer!
      # Replace boolean by _conversion to_ boolean, because we need to replace the type we emit
      # for the header by `i32`
      n = GpuAst(kind: gpuConv, convTo: GpuType(kind: gtBool), convExpr: n)
  of gpuDeref:
    # XXX: Don't really need to check if type is pointer if we already have `deref`
    if n.dOf.kind == gpuIdent and n.dOf.iSym in ctx.globals and (let p = ctx.globals[n.dOf.iSym]; p.typ.kind == gtPtr):
      # replace deref by access to itself
      n = n.dOf
  else:
    for ch in mitems(n):
      ctx.injectAddressOf(ch)

proc updateSymsInGlobals(ctx: var GpuContext, n: GpuAst) =
  ## Update symbols in global functions to have same mutability and symbolkind as
  ## parameters
  case n.kind
  of gpuIdent:
    if n.iSym in ctx.globals:
      n.symbolKind = gsGlobalKernelParam
      if n.iTyp.kind == gtPtr:
        let g = ctx.globals[n.iSym]
        n.iTyp.mutable = g.typ.kind == gtPtr # arguments as pointers == mutable
  else:
    for ch in n:
      ctx.updateSymsInGlobals(ch)

proc storagePass*(ctx: var GpuContext, ast: GpuAst, kernel: string = "") =
  ## If `kernel` is a global function, we *only* generate code for that kernel.
  ## This is useful if your GPU code contains multiple kernels with differing
  ## parameters to avoid having to fill dummy buffers for all the unused parameters
  ## or to work around conflicting paremeters.
  # 1. Fill table with all *global* functions or *only* the specific `kernel`
  #    if any given
  var varBlock = GpuAst(kind: gpuBlock)
  var typBlock = GpuAst(kind: gpuBlock)
  ctx.farmTopLevel(ast, kernel, varBlock, typBlock)
  ctx.globalBlocks.add varBlock
  ctx.globalBlocks.add typBlock

  # 2. Remove all arguments from global functions, as none are allowed in WGSL
  for (fnIdent, fn) in mpairs(ctx.fnTab): # mutating the function in the table
    if (fn.isGlobal() and kernel.len > 0 and fn.pName.ident() == kernel) or
        (kernel.len == 0 and fn.isGlobal()):
      for p in fn.pParams:
        ctx.globals[p.ident.iSym] = p # copy all parameters over to globals
      fn.pParams.setLen(0) # delete function's parameters
      # now update all appearances of the parameters, now globals, such that they reflect
      # the correct symbol kind and mutability
      ctx.updateSymsInGlobals(fn)
    else:
      discard

  # 3. Using all global functions, we traverse their AST for any `gpuCall` node. We inspect
  #    the functions called and record them in `fnTab`. If they have pointer arguments we
  #    generate a generic instantiation for the exact pointer types used.
  #    We start with a seq of all globals, because we need to modify `fnTab` during the iteration.
  let fns = toSeq(ctx.fnTab.pairs)
  for (fnIdent, fn) in fns: # everything in `fnTab` at this point is a global function
    # Get the original arguments (before lifting them) of this function. Needed in scan
    # to check if `gpuCall` argument is a parameter.
    let fnOrig = ctx.allFnTab[fnIdent]
    var callParams = initTable[string, GpuParam]()
    for p in fnOrig.pParams: # use the symbol as key. Makes sure it is _that_ symbol and not a local of same name
      callParams[p.ident.iSym] = p
    ctx.scanGenerics(fn, callParams)

  # 4. Finally, make all updates to the global functions that are necessary due to different
  #    pointer semantics and disallowance of e.g. `bool` arguments.
  for (fnIdent, fn) in mpairs(ctx.fnTab):
    if fn.isGlobal(): # non global functions don't need to be mutated
      ctx.injectAddressOf(fn)


  proc rewriteCompoundAssignment(n: GpuAst): GpuAst =
    doAssert n.kind == gpuBinOp

    template genAssign(left, rnode, op: typed): untyped =
      let right = GpuAst(kind: gpuBinOp, bOp: op, bLeft: left, bRight: rnode)
      GpuAst(kind: gpuAssign, aLeft: left, aRight: right, aRequiresMemcpy: false)

    let op = n.bOp
    if op.len >= 2 and op[^1] == '=':
      result = genAssign(n.bLeft, n.bRight, op[0 .. ^2]) # all but last
    else:
      # leave untouched
      result = n

  proc makeCodeValid(ctx: var GpuContext, n: var GpuAst) =
    case n.kind
    of gpuBinOp: n = rewriteCompoundAssignment(n)
    else:
      for ch in mitems(n):
        ctx.makeCodeValid(ch)
  # 5. (Actually finally) patch all additional things invalid in WGSL, e.g. `x += 5` -> `x = x + 5`
  for (fnIdent, fn) in mpairs(ctx.fnTab):
    ctx.makeCodeValid(fn)


proc genWebGpu*(ctx: var GpuContext, ast: GpuAst, indent = 0): string
proc size(ctx: var GpuContext, a: GpuAst): string = size(ctx.genWebGpu(a))
proc address(ctx: var GpuContext, a: GpuAst): string = address(ctx.genWebGpu(a))

proc genWebGpu*(ctx: var GpuContext, ast: GpuAst, indent = 0): string =
  #echo "AST: ", $ast
  let indentStr = "  ".repeat(indent)
  case ast.kind
  of gpuVoid: return # nothing to emit
  of gpuProc:
    let attrs = collect:
      for att in ast.pAttributes:
        $att

    var params: seq[string]
    for p in ast.pParams:
      params.add gpuTypeToString(p.typ, p.ident, allowEmptyIdent = false)
    var fnArgs = params.join(", ")
    if $attGlobal in attrs:
      doAssert fnArgs.len == 0, "Global function `" & $ast.pName.ident() & "` still has arguments!"
      ## XXX: make this more flexible. In theory can be any name
      fnArgs = "@builtin(global_invocation_id) global_id: vec3<u32>"
    let fnSig = genFunctionType(ast.pRetType, ast.pName.ident(), fnArgs)

    result = indentStr & "fn " & fnSig & " {\n"

    result &= ctx.genWebGpu(ast.pBody, indent + 1)
    result &= "\n" & indentStr & "}"

  of gpuBlock:
    result = ""
    if ast.blockLabel.len > 0:
      result.add "\n" & indentStr & "{ // " & ast.blockLabel & "\n"
    for i, el in ast.statements:
      result.add ctx.genWebGpu(el, indent)
      if el.kind != gpuBlock and not ctx.skipSemicolon: # nested block ⇒ ; already added
        result.add ";"
      if i < ast.statements.high:
        result.add "\n"
    if ast.blockLabel.len > 0:
      result.add "\n" & indentStr & "} // " & ast.blockLabel & "\n"

  of gpuVar:
    let letOrVar = if ast.vMutable: "var" else: "let"
    var attrs = ast.vAttributes.join(", ")
    if attrs.len > 0: attrs = &"<{attrs}>"
    result = &"{indentStr}{letOrVar}{attrs} {gpuTypeToString(ast.vType, ast.vName)}"
    # If there is an initialization, the type might require a memcpy
    doAssert not ast.vInit.isNil, "Variable initialization is nil. Should not happen."
    if ast.vInit.kind != gpuVoid and not ast.vRequiresMemcpy:
      result &= " = " & ctx.genWebGpu(ast.vInit)
    elif ast.vInit.kind != gpuVoid:
      when nimvm:
        error("Types that require memcpy not supported on WGSL. Probably a better solution.")
      else:
        raise newException(ValueError, "Types that require memcpy not supported on WGSL. Probably a better solution.")
      when false:
        result.add ";\n"
        result.add indentStr & genMemcpy(address(ast.vName.ident()), ctx.address(ast.vInit),
                                         size(ast.vName.ident()))

  of gpuAssign:
    if ast.aRequiresMemcpy:
      when nimvm:
        error("Types that require memcpy not supported on WGSL. Probably a better solution.")
      else:
        raise newException(ValueError, "Types that require memcpy not supported on WGSL. Probably a better solution.")
      when false:
        result = indentStr & genMemcpy(ctx.address(ast.aLeft), ctx.address(ast.aRight),
                                       ctx.size(ast.aLeft))
    else:
      let leftId = ast.aLeft.determineIdent()
      if leftId.kind != gpuVoid and leftId.iTyp.kind == gtPtr and leftId.iTyp.to.kind == gtInt32:
        # If the LHS is `i32` then a conversion to `i32` is either a no-op, if the left always was
        # `i32` (and the Nim compiler type checked it for us) *OR* the RHS is a boolean expression and
        # we patched the `bool -> i32` and thus need to convert it.
        result = indentStr & ctx.genWebGpu(ast.aLeft) & " = i32(" & ctx.genWebGpu(ast.aRight) & ")"
      else:
        result = indentStr & ctx.genWebGpu(ast.aLeft) & " = " & ctx.genWebGpu(ast.aRight)

  of gpuIf:
    # skip semicolon in the condition. Otherwise can lead to problematic code
    ctx.withoutSemicolon: # skip semicolon for if bodies
      ## Compile time `bool` is turned into int literals 0 and 1 in typed AST
      if ast.ifCond.kind == gpuLit and ast.ifCond.lType.kind == gtInt32 and ast.ifCond.lValue == "1":
        result = indentStr & "if (true) {\n"
      elif ast.ifCond.kind == gpuLit and ast.ifCond.lType.kind == gtInt32 and ast.ifCond.lValue == "0":
        result = indentStr & "if (false) {\n"
      else:
        result = indentStr & "if (" & ctx.genWebGpu(ast.ifCond) & ") {\n"
    result &= ctx.genWebGpu(ast.ifThen, indent + 1) & "\n"
    result &= indentStr & "}"
    if ast.ifElse.kind != gpuVoid:
      result &= " else {\n"
      result &= ctx.genWebGpu(ast.ifElse, indent + 1) & "\n"
      result &= indentStr & "}"

  of gpuFor:
    result = indentStr & "for(var " & ast.fVar.ident() & ": i32 = " &
             ctx.genWebGpu(ast.fStart) & "; " &
             ast.fVar.ident() & " < " & ctx.genWebGpu(ast.fEnd) & "; " &
             ast.fVar.ident() & "++) {\n"
    result &= ctx.genWebGpu(ast.fBody, indent + 1) & "\n"
    result &= indentStr & "}"
  of gpuWhile:
    ctx.withoutSemicolon:
      result = indentStr & "while (" & ctx.genWebGpu(ast.wCond) & "){\n"
    result &= ctx.genWebGpu(ast.wBody, indent + 1) & "\n"
    result &= indentStr & "}"

  of gpuDot:
    result = ctx.genWebGpu(ast.dParent) & "." & ctx.genWebGpu(ast.dField)

  of gpuIndex:
    result = ctx.genWebGpu(ast.iArr) & "[" & ctx.genWebGpu(ast.iIndex) & "]"

  of gpuCall:
    ctx.withoutSemicolon:
      result = indentStr & ast.cName.ident() & "(" &
               ast.cArgs.mapIt(ctx.genWebGpu(it)).join(", ") & ")"

  of gpuTemplateCall:
    when nimvm:
      error("Template calls are not supported at the moment. In theory there shouldn't even _be_ any template " &
        "calls in the expanded body of the `cuda` macro.")
    else:
      raise newException(ValueError, "Template calls are not supported at the moment. In theory there shouldn't even _be_ any template " &
        "calls in the expanded body of the `cuda` macro.")

    when false: # Template replacement would look something like this:
      let templ = ctx.templates[ast.tcName]
      let expandedBody = substituteTemplateArgs(
        templ.body,
        templ.params,
        ast.tcArgs
      )
      result = ctx.genWebGpu(expandedBody, indent)

  of gpuBinOp:
    result = indentStr & "(" & ctx.genWebGpu(ast.bLeft) & " " &
             ast.bOp & " " &
             ctx.genWebGpu(ast.bRight) & ")"

  of gpuIdent:
    result = ast.ident()

  of gpuLit:
    if ast.lType.kind == gtString: result = "\"" & ast.lValue & "\""
    elif ast.lValue == "DEFAULT":
      ## TODO: We could "manually" construct a zero version!
      ## NOTE: There *are* default initializations to zero. Just not for fields that
      ## are either pointers or runtime arrays!
      #raiseAssert "There is no way to default initialize a variable on the WebGPU target."
      result = ""
    else:
      result = ast.lValue & literalSuffix(ast.lType)

  of gpuArrayLit:
    result = "array("
    for i, el in ast.aValues:
      result.add gpuTypeToString(ast.aLitType) & "(" & el & ")"
      if i < ast.aValues.high:
        result.add ", "
    result.add ")"

  of gpuReturn:
    result = indentStr & "return " & ctx.genWebGpu(ast.rValue)

  of gpuPrefix:
    result = ast.pOp & ctx.genWebGpu(ast.pVal)

  of gpuTypeDef:
    result = "struct " & ast.tName & "{\n"
    for el in ast.tFields:
      result.add "  " & gpuTypeToString(el.typ, newGpuIdent(el.name)) & ",\n"
    result.add "}"

  of gpuObjConstr:
    result = ast.ocName & "("
    for i, el in ast.ocFields:
      if el.value.kind == gpuLit and el.value.lValue == "DEFAULT":
        # use type to construct a default value
        let typStr = gpuTypeToString(el.typ, allowEmptyIdent = true)
        result.add typStr & "()"
      else:
        result.add ctx.genWebGpu(el.value)
      if i < ast.ocFields.len - 1:
        result.add ", "
    result.add ")"

  of gpuInlineAsm:
    raiseAssert "Inline assembly not supported on the WebGPU target."

  of gpuComment:
    result = indentStr & "/* " & ast.comment & " */"

  of gpuConv:
    result = gpuTypeToString(ast.convTo, allowEmptyIdent = true) & "(" & ctx.genWebGpu(ast.convExpr) & ")"

  of gpuCast:
    result = "bitcast<" & gpuTypeToString(ast.cTo, allowEmptyIdent = true) & ">(" & ctx.genWebGpu(ast.cExpr) & ")"

  of gpuAddr:
    result = "(&" & ctx.genWebGpu(ast.aOf) & ")"

  of gpuDeref:
    result = "(*" & ctx.genWebGpu(ast.dOf) & ")"

  of gpuConstexpr:
    result = indentStr & "const " & ctx.genWebGpu(ast.cIdent) & ": " & gpuTypeToString(ast.cType, allowEmptyIdent = true) & " = " & ctx.genWebGpu(ast.cValue)

  else:
    echo "Unhandled node kind in genWebGpu: ", ast.kind
    raiseAssert "Unhandled node kind in genWebGpu: " & ast.repr
    result = ""

proc codegen*(ctx: var GpuContext): string =
  ## Generate the actual code for all pieces of the puzzle
  ##
  ## NOTE: WGSL does not require forward declarations / does not care about
  ## the order in which functions are defined

  var bindingCounter = 0
  proc mutateToAllowedTypes(p: GpuType): GpuType =
    ## We strip pointer types `ptr T` to only emit `T`. This is because all global parameters
    ## must be global storage buffers. These cannot be of `ptr` type. If an implicit, runtime
    ## sized array is desired, use `ptr UncheckedArray[T]`, which will emit `array<T>`.
    ##
    ## If we have a `bool` type, we need to convert it to a `i32` (also applies to `ptr bool`)
    case p.kind
    of gtPtr: mutateToAllowedTypes(p.to) # if it is `ptr bool`
    of gtBool: ## boolean must become `i32`. Will inject `bool(foo)` into globals
      GpuType(kind: gtInt32)
    else: p
  proc genGlobal(p: GpuParam): string =
    ## XXX: deduce read or read_write based on argument type!
    let rw = if p.typ.kind == gtPtr: "read_write" else: "read"
    result = &"@group(0) @binding({bindingCounter}) var<storage, " & rw & "> "
    let typ = mutateToAllowedTypes(p.typ)
    result.add gpuTypeToString(typ, p.ident, allowEmptyIdent = false) & ";\n"
    inc bindingCounter

  # 1. Generate the header for all global variables
  for id, g in ctx.globals:
    result.add genGlobal(g)
  result.add "\n"

  # 2. generate code for the global blocks (types, global vars etc)
  for blk in ctx.globalBlocks:
    result.add ctx.genWebGpu(blk) & "\n\n"

  # 3. generate all regular functions
  for fnIdent, fn in ctx.fnTab:
    if fn.isGlobal():
      ## XXX: make adjustable!
      result.add "@compute @workgroup_size(WORKGROUP_SIZE)\n"
    result.add ctx.genWebGpu(fn) & "\n\n"
