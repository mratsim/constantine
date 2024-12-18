## XXX: for now dependent on nimcuda for ease of development
## NOTE: this is essentially an adjusted version of the execution DSL
## in `constantine/constantine/math_compiler/codegen_nvidia.nim`.

import nimcuda/cuda12_5/[nvrtc, check, cuda, cuda_runtime_api, driver_types]
import std/macros

proc getTypes(n: NimNode): seq[NimNode] =
  case n.kind
  of nnkIdent, nnkSym: result.add getTypeInst(n)
  of nnkLiterals: result.add getTypeInst(n)
  of nnkBracket, nnkTupleConstr, nnkPar:
    for el in n:
      result.add getTypes(el)
  else:
    case n.typeKind
    of ntyPtr: result.add getTypeInst(n)
    else:
      error("Arguments to `execCuda` must be given as a bracket, tuple or typed expression. Instead: " & $n.treerepr)

proc requiresCopy(n: NimNode): bool =
  ## Returns `true` if the given type is not a trivial data type, which implies
  ## it will require copying its value manually.
  ##
  ## WARNING: For the moment we determine if something needs to be copied especially
  ## based on whether it is an object or ref type. That means *DO NOT* nest ref
  ## types in your objects. They *WILL NOT* be deep copied!
  case n.typeKind
  of ntyBool, ntyChar, ntyInt .. ntyUint64: # range includes all floats
    result = false
  of ntyObject:
    result = false # regular objects can just be copied!
    ## NOTE: strictly speaking this is not the case of course! If the object
    ## contains refs, it won't hold!
  of ntyGenericInst:
    let impl = n.getTypeImpl()
    result = impl.kind == nnkRefTy # if a ref, needs to be copied
  else:
    result = true

proc allowsCopy(n: NimNode): bool =
  ## Returns `true` if the given type is allowed to be copied. That means it is
  ## either `requiresCopy` or a `var` symbol.
  result = n.requiresCopy or n.symKind == nskVar

proc getIdent(n: NimNode): NimNode =
  ## Generate a `GPU` suffixed ident
  # Note: We want a deterministic name, because we call `getIdent` for the same symbol
  # in multiple places atm.
  case n.kind
  of nnkIdent, nnkSym: result = ident(n.strVal & "GPU")
  else: result = ident("`" & n.repr & "`GPU")

proc determineDevicePtrs(r, i: NimNode, iTypes: seq[NimNode]): seq[(NimNode, NimNode)] =
  ## Returns the device pointer ident and its associated original symbol.
  for el in r:
    if not el.allowsCopy:
      error("The argument for `res`: " & $el.repr & " of type: " & $el.getTypeImpl().treerepr &
        " does not allow copying. Copying to the address of all result variables is required.")
    result.add (getIdent(el), el)
  for idx in 0 ..< i.len:
    let input = i[idx]
    let t = iTypes[idx]
    if t.requiresCopy():
      result.add (getIdent(input), input)

proc assembleParams(r, i: NimNode, iTypes: seq[NimNode]): seq[NimNode] =
  ## Returns all parameters. Depending on whether they require copies or
  ## are `res` parameters, either the input parameter or the `GPU` parameter.
  for el in r: # for `res` we always copy!
    result.add getIdent(el)
  for idx in 0 ..< i.len:
    let input = i[idx]
    let t = iTypes[idx]
    if t.requiresCopy():
      result.add getIdent(input)
    else:
      result.add input

# little helper macro constructors
template check(arg): untyped = nnkCall.newTree(ident"check", arg)
template size(arg): untyped = nnkCall.newTree(ident"sizeof", arg)
template address(arg): untyped = nnkCall.newTree(ident"addr", arg)
template csize_t(arg): untyped = nnkCall.newTree(ident"csize_t", arg)
template pointer(arg): untyped = nnkCall.newTree(ident"pointer", arg)
template arrayTyp(num, typ): untyped = nnkBracketExpr.newTree(ident"array", newLit num, typ)
template lenOf(arg): untyped = nnkCall.newTree(ident"len", arg)
template mul(x, y): untyped = nnkInfix.newTree(ident"*", x, y)

proc getSizeOf(arg: NimNode): NimNode =
  ## Returns a call to `sizeof` for the given argument. The argument to `sizeof` must
  ## be the size of the data we copy. If the argument is a `seq` we take into account
  ## the number of elements. If the input type is already given as a `ptr T` type, we
  ## need the size of `T` and not `ptr`.
  case arg.typeKind
  of ntyPtr: result = size(arg.getTypeInst()[0])
  of ntySequence: result = mul(lenOf(arg), size(arg.getTypeInst()[1]))
  else: result = size(arg)

proc maybeAddress(n: NimNode): NimNode =
  ## Returns the address of the given node, *IFF* the type is not a
  ## pointer type already. In case the input is a `seq[T]`, we return `x[0].addr`.
  case n.typeKind
  of ntyPtr: result = n
  of ntySequence: result = address( nnkBracketExpr.newTree(n, newLit 0) )
  else: result = address(n)

proc genParams(pId, r, i: NimNode, iTypes: seq[NimNode]): NimNode =
  ## Generates the parameter `params` variable
  let ps = assembleParams(r, i, iTypes)
  result = nnkBracket.newTree()
  for p in ps:
    result.add pointer(maybeAddress p)
  result = nnkLetSection.newTree(
    nnkIdentDefs.newTree(pId, arrayTyp(ps.len, ident"pointer"), result)
  )

proc genVar(n: NimNode): (NimNode, NimNode) =
  ## Generates a let `tmp` variable and returns its identifier and
  ## the let section.
  result[0] = genSym(nskLet, "tmp")
  result[1] = nnkLetSection.newTree(
    nnkIdentDefs.newTree(
      result[0],
      getTypeInst(n),
      n
    )
  )

proc genLocalVars(inputs: NimNode): (NimNode, NimNode) =
  result[0] = newStmtList() # defines local vars
  result[1] = nnkBracket.newTree() # returns new bracket of vars for parameters
  for el in inputs:
    case el.kind
    of nnkLiterals, nnkConstDef: # define a local with the value of it
      let (s, v) = genVar(el)
      result[0].add v
      result[1].add s
    of nnkSym:
      if el.strVal in ["true", "false"]:
        let (s, v) = genVar(el)
        result[0].add v
        result[1].add s
      else:
        result[1].add el # keep symbol
    else:
      result[1].add el # keep symbol

proc maybeWrap(n: NimNode): NimNode =
  if n.kind notin {nnkBracket, nnkTupleConstr}:
    result = nnkBracket.newTree(n)
  else:
    result = n

proc endianCheck(): NimNode =
  result = quote do:
    static: doAssert cpuEndian == littleEndian, block:
      # From https://developer.nvidia.com/cuda-downloads?target_os=Linux
      # Supported architectures for Cuda are:
      # x86-64, PowerPC 64 little-endian, ARM64 (aarch64)
      # which are all little-endian at word-level.
      #
      # Due to limbs being also stored in little-endian, on little-endian host
      # the CPU and GPU will have the same binary representation
      # whether we use 32-bit or 64-bit words, so naive memcpy can be used for parameter passing.

      "Most CPUs (x86-64, ARM) are little-endian, as are Nvidia GPUs, which allows naive copying of parameters.\n" &
      "Your architecture '" & $hostCPU & "' is big-endian and GPU offloading is unsupported on it."

proc execCudaImpl(jitFn, numBlocks, threadsPerBlock, res, inputs: NimNode): NimNode =
  # Maybe wrap individually given arguments in a `[]` bracket, e.g.
  # `execCuda(res = foo, inputs = bar)`
  let res = maybeWrap res
  let inputs = maybeWrap inputs

  result = newStmtList()
  result.add endianCheck()

  # get the types of the inputs
  let rTypes = getTypes(res)
  let iTypes = getTypes(inputs)

  # determine all required `CUdeviceptr`
  let devPtrs = determineDevicePtrs(res, inputs, iTypes)

  # generate device pointers, allocate memory and copy data
  for x in devPtrs:
    # `var rGPU: CUdeviceptr`
    result.add nnkVarSection.newTree(
      nnkIdentDefs.newTree(
        x[0],
        ident"CUdeviceptr",
        newEmptyNode()
      )
    )

    # `check cuMemAlloc(rGPU, csize_t sizeof(r))`
    result.add(
      check nnkCall.newTree(
        ident"cuMemAlloc",
        address x[0],
        csize_t getSizeOf(x[1])
      )
    )
    # `check cuMemcpyHtoD(aGPU, a.addr, csize_t sizeof(a))`
    result.add(
      check nnkCall.newTree(
        ident"cuMemcpyHtoD",
        x[0],
        maybeAddress x[1],
        csize_t getSizeOf(x[1])
      )
    )

  # Generate local variables
  let (decl, vars) = genLocalVars(inputs)
  result.add decl

  # assemble the parameters
  let pId = ident"params"
  let params = genParams(pId, res, vars, iTypes)
  result.add params

  # launch the kernel
  result.add quote do:
    let pAr = if `pId`.len > 0: `pId`[0].unsafeAddr
              else: nil

    # Create timing events
    var start, stop: cudaEvent_t
    check cudaEventCreate(addr start)
    check cudaEventCreate(addr stop)

    check cudaEventRecord(start, nil)
    check cuLaunchKernel(
            `jitFn`,
            `numBlocks`, 1, 1, # grid(x, y, z)
            `threadsPerBlock`, 1, 1, # block(x, y, z)
            sharedMemBytes = 0,
            CUstream(nil),
            pAr, nil)
    check cudaEventRecord(stop, nil)
    check cudaDeviceSynchronize()

    var elapsedTime: float32
    check cudaEventElapsedTime(addr elapsedTime, start, stop)
    echo "[INFO]: Kernel execution took: ", elapsedTime, " ms"

    check cudaEventDestroy(start)
    check cudaEventDestroy(stop)


  # copy back results
  let devPtrsRes = determineDevicePtrs(res, nnkBracket.newTree(), @[])
  for x in devPtrsRes:
    result.add(
      check nnkCall.newTree(
        ident"cuMemcpyDtoH",
        maybeAddress x[1],
        x[0],
        csize_t getSizeOf(x[1])
      )
    )

  # free memory
  for x in devPtrs:
    result.add(
      check nnkCall.newTree(
        ident"cuMemFree",
        x[0]
      )
    )
  result = quote do:
    block:
      `result`

  echo result.repr

macro execCuda*(jitFn: CUfunction,
                res: typed,
                inputs: typed): untyped =
  ## Given a CUDA function, execute the kernel. Copies all non trivial data types to
  ## to the GPU via `cuMemcpyHtoD`. Any argument given as `res` will be copied back
  ## from the GPU after kernel execution finishes.
  ##
  ## IMPORTANT:
  ## The arguments passed to the CUDA kernel will be in the order in which they are
  ## given to the macro. This especially means `res` arguments will be passed first.
  ##
  ## Example:
  ## ```nim
  ## execCuda(fn, res = [r, s], inputs = [a, b, c]) # if all arguments have the same type
  ## # or
  ## execCuda(fn, res = (r, s), inputs = (a, b, c)) # if different types
  ## ```
  ## will pass the parameters as `[r, s, a, b, c]`.
  ##
  ## For more examples see the test case `tests/gpu/t_exec_literals_consts.nim`.
  ##
  ## We do not perform any checks on whether the given types are valid as arguments to
  ## the CUDA target! Also, all arguments given as `res` are expected to be copied.
  ## To return a value for a simple data type, use a `ptr X` type. However, it is allowed
  ## to simply pass a `var` symbol as a `res` argument. We automatically copy to the
  ## the memory location.
  ##
  ## We also copy all `res` data to the GPU, so that a return value can also be used
  ## as an input.
  ##
  ## NOTE: This function is mainly intended for convenient execution of a single kernel
  result = execCudaImpl(jitFn, newLit 1, newLit 1, res, inputs)

macro execCuda*(jitFn: CUfunction,
                numBlocks, threadsPerBlock: int,
                res: typed,
                inputs: typed): untyped =
  ## Overload which takes a target number of threads and blocks
  result = execCudaImpl(jitFn, numBlocks, threadsPerBlock, res, inputs)

macro execCuda*(jitFn: CUfunction,
                res: typed): untyped =
  ## Overload of the above for empty `inputs`
  result = execCudaImpl(jitFn, newLit 1, newLit 1, res, nnkBracket.newTree())
