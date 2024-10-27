# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  constantine/platforms/abis/nvidia_abi {.all.},
  constantine/platforms/abis/c_abi,
  constantine/platforms/llvm/llvm,
  constantine/platforms/primitives,
  constantine/named/algebras,
  constantine/math/elliptic/ec_shortweierstrass_jacobian,
  ./ir,
  std / macros # for `execCuda`

export
  nvidia_abi,
  Flag, flag, wrapOpenArrayLenType

# ############################################################
#
#                     Nvidia GPUs API
#
# ############################################################

# Versioning and hardware support
# ------------------------------------------------------------

# GPU architectures:
# - Kepler   Geforce GTX 780,  2012, Compute Capability SM3.5
# - Maxwell  Geforce GTX 980,  2014, Compute Capability SM5.2
# - Pascal   Geforce GTX 1080, 2016, Compute Capability SM6.1
# - Volta    Tesla V100,       2017, Compute Capability SM7.0
# - Turing   Geforce RTX 2080, 2018, Compute Capability SM7.5
# - Ampere   Geforce RTX 3080, 2020, Compute Capability SM8.6
# - Ada      Geforce RTX 4080, 2022, Compute Capability SM8.9

# We likely want to use unified memory in the future to avoid having to copy back and from device explicitly
# - https://developer.nvidia.com/blog/unified-memory-cuda-beginners/
# - https://developer.nvidia.com/blog/unified-memory-in-cuda-6/
#
# Unified memory is fully supported starting from Pascal GPU (GTX 1080, 2016, Compute Capability SM6.0)
# and require Kepler at minimum.
#
# Cuda 9 exposes the current explicit synchronization primitives (cooperative groups) and deprecated the old ones
# Those primitives are particularly suitable for Volta GPUs (GTX 2080, 2018, Compute Capability SM7.5)
# and requiring.
#
# Furthermore Pascal GPUs predates the high demand for deep learning and cryptocurrency mining
# and were widely available at an affordable price point.
# Also given iven that it's a 7 years old architecture,
# it is unlikely that users have an older Nvidia GPU available.
#
# Hence we can target Cuda 9 at minimum (Sept 2017): https://developer.nvidia.com/cuda-toolkit-archive
# which corresponds to PTX ISA 6.0: https://docs.nvidia.com/cuda/parallel-thread-execution/index.html#release-notes__ptx-release-history
#
# Unfortunately, there is no easy programmatic way to retrieve the PTX ISA version supported
# only the Cuda/Compiler version (https://docs.nvidia.com/cuda/ptx-compiler-api/index.html#group__versioning)
# Hence it's likely easier to ask users to update Cuda in case of ISA incompatibility.
#
#  Due to the following bug on 32-bit fused multiply-add with carry
#    https://forums.developer.nvidia.com/t/wrong-result-returned-by-madc-hi-u64-ptx-instruction-for-specific-operands/196094
#  We require Cuda 12 at minimum.
#  Requirement will be bumped when 64-bit fused multiply-add with carry
#    https://forums.developer.nvidia.com/t/incorrect-result-of-ptx-code/221067
#  is also fixed.

# Cuda Driver API
# ------------------------------------------------------------

template check*(status: CUresult) =
  ## Check the status code of a CUDA operation
  ## Exit program with error if failure

  let code = status # ensure that the input expression is evaluated once only
  if code != CUDA_SUCCESS:
    writeStackTrace()
    stderr.write(astToStr(status) & " " & $instantiationInfo() & " exited with error: " & $code & '\n')
    quit 1

func cuModuleLoadData*(module: var CUmodule, sourceCode: openArray[char]): CUresult {.inline.}=
  cuModuleLoadData(module, sourceCode[0].unsafeAddr)
func cuModuleGetFunction*(kernel: var CUfunction, module: CUmodule, fnName: openArray[char]): CUresult {.inline.}=
  cuModuleGetFunction(kernel, module, fnName[0].unsafeAddr)

proc cudaDeviceInit*(deviceID = 0'i32): CUdevice =

  check cuInit(deviceID.uint32)

  var devCount: int32
  check cuDeviceGetCount(devCount)
  if devCount == 0:
    echo "cudaDeviceInit error: no devices supporting CUDA"
    quit 1

  var cuDevice: CUdevice
  check cuDeviceGet(cuDevice, deviceID)
  var name = newString(128)
  check cuDeviceGetName(name[0].addr, name.len.int32, cuDevice)
  echo "Using CUDA Device [", deviceID, "]: ", cstring(name)

  var major, minor: int32
  check cuDeviceGetAttribute(major, CU_DEVICE_ATTRIBUTE_COMPUTE_CAPABILITY_MAJOR, cuDevice)
  check cuDeviceGetAttribute(minor, CU_DEVICE_ATTRIBUTE_COMPUTE_CAPABILITY_MINOR, cuDevice)
  echo "Compute Capability: SM ", major, ".", minor
  if major < 6:
    echo "Error: Device ",deviceID," is not sm_60 (Pascal generation, GTX 1080) or later"
    quit 1

  return cuDevice

# ############################################################
#
#                      Code generation
#
# ############################################################

proc codegenNvidiaPTX*(asy: Assembler_LLVM, sm: tuple[major, minor: int32]): string =
  ## Generate Nvidia PTX via LLVM
  ## SM corresponds to the target GPU architecture Compute Capability
  ## - https://developer.nvidia.com/cuda-gpus
  ## - https://docs.nvidia.com/cuda/cuda-c-programming-guide/index.html#compute-capabilities
  ##
  ## This requires the following function to be called beforehand:
  ## - initializeFullNVPTXTarget()

  debug: doAssert asy.backend == bkNvidiaPTX

  asy.module.verify(AbortProcessAction)

  const triple = "nvptx64-nvidia-cuda"

  let machine = createTargetMachine(
    target = toTarget(triple),
    triple = triple,
    cpu = cstring("sm_" & $sm.major & $sm.minor),
    features = "",
    level = CodeGenLevelAggressive,
    reloc = RelocDefault,
    codeModel = CodeModelDefault
  )

  let pbo = createPassBuilderOptions()
  pbo.setMergeFunctions()
  let err = asy.module.runPasses(
    "default<O3>,function-attrs,memcpyopt,sroa,mem2reg,gvn,dse,instcombine,inline,adce",
    machine,
    pbo
  )
  if not err.pointer().isNil():
    writeStackTrace()
    let errMsg = err.getErrorMessage()
    stderr.write("\"codegenNvidiaPTX\" for module '" & astToStr(module) & "' " & $instantiationInfo() &
                 " exited with error: " & $cstring(errMsg) & '\n')
    errMsg.dispose()
    quit 1

  return machine.emitTo[:string](asy.module, AssemblyFile)

# ############################################################
#
#                      Code execution
#
# ############################################################

proc getCudaKernel*(cuMod: CUmodule, fnName: string): CUfunction =
  check cuModuleGetFunction(result, cuMod, fnName)

proc exec*[T](jitFn: CUfunction, r: var T, a, b: T) =
  ## Execute a binary operation in the form r <- op(a, b)
  ## on Nvidia GPU
  # The execution wrapper provided are mostly for testing and debugging low-level kernels
  # that serve as building blocks, like field addition or multiplication.
  # They aren't parallelizable so we are not concern about the grid and block size.
  # We also aren't concerned about the cuda stream when testing.
  #
  # This is not the case for production kernels (multi-scalar-multiplication, FFT)
  # as we want to execute kernels asynchronously then merge results which might require multiple streams.

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

  # We assume that all arguments are passed by reference in the Cuda kernel, hence the need for GPU alloc.

  var rGPU, aGPU, bGPU: CUdeviceptr
  check cuMemAlloc(rGPU, csize_t sizeof(r))
  check cuMemAlloc(aGPU, csize_t sizeof(a))
  check cuMemAlloc(bGPU, csize_t sizeof(b))

  check cuMemcpyHtoD(aGPU, a.unsafeAddr, csize_t sizeof(a))
  check cuMemcpyHtoD(bGPU, b.unsafeAddr, csize_t sizeof(b))

  let params = [pointer(rGPU.addr), pointer(aGPU.addr), pointer(bGPU.addr)]

  check cuLaunchKernel(
          jitFn,
          1, 1, 1, # grid(x, y, z)
          1, 1, 1, # block(x, y, z)
          sharedMemBytes = 0,
          CUstream(nil),
          params[0].unsafeAddr, nil)

  check cuMemcpyDtoH(r.addr, rGPU, csize_t sizeof(r))

  check cuMemFree(rGPU)
  check cuMemFree(aGPU)
  check cuMemFree(bGPU)

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
  case n.typeKind
  of ntyBool, ntyChar, ntyInt .. ntyUint64: # range includes all floats
    result = false
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

proc sizeArg(n: NimNode): NimNode =
  ## The argument to `sizeof` must be the size of the data we copy. If the
  ## input type is already given as a `ptr T` type, we need the size of
  ## `T` and not `ptr`.
  case n.typeKind
  of ntyPtr: result = n.getTypeInst()[0]
  else: result = n

# little helper macro constructors
template check(arg): untyped = nnkCall.newTree(ident"check", arg)
template size(arg): untyped = nnkCall.newTree(ident"sizeof", sizeArg arg)
template address(arg): untyped = nnkCall.newTree(ident"addr", arg)
template csize_t(arg): untyped = nnkCall.newTree(ident"csize_t", arg)
template pointer(arg): untyped = nnkCall.newTree(ident"pointer", arg)

proc maybeAddress(n: NimNode): NimNode =
  ## Returns the address of the given node, *IFF* the type is not a
  ## pointer type already
  case n.typeKind
  of ntyPtr: result = n
  else: result = address(n)

proc genParams(pId, r, i: NimNode, iTypes: seq[NimNode]): NimNode =
  ## Generates the parameter `params` variable
  let ps = assembleParams(r, i, iTypes)
  result = nnkBracket.newTree()
  for p in ps:
    result.add pointer(maybeAddress p)
  result = nnkLetSection.newTree(
    nnkIdentDefs.newTree(pId, newEmptyNode(), result)
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

proc execCudaImpl(jitFn, res, inputs: NimNode): NimNode =
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
        x[0],
        csize_t size(x[1])
      )
    )
    # `check cuMemcpyHtoD(aGPU, a.addr, csize_t sizeof(a))`
    result.add(
      check nnkCall.newTree(
        ident"cuMemcpyHtoD",
        x[0],
        maybeAddress x[1],
        csize_t size(x[1])
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
    check cuLaunchKernel(
            `jitFn`,
            1, 1, 1, # grid(x, y, z)
            1, 1, 1, # block(x, y, z)
            sharedMemBytes = 0,
            CUstream(nil),
      `pId`[0].unsafeAddr, nil)

  # copy back results
  let devPtrsRes = determineDevicePtrs(res, nnkBracket.newTree(), @[])
  for x in devPtrsRes:
    result.add(
      check nnkCall.newTree(
        ident"cuMemcpyDtoH",
        maybeAddress x[1],
        x[0],
        csize_t size(x[1])
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
  result = execCudaImpl(jitFn, res, inputs)

macro execCuda*(jitFn: CUfunction,
                res: typed): untyped =
  ## Overload of the above for empty `inputs`
  result = execCudaImpl(jitFn, res, nnkBracket.newTree())

# ############################################################
#
#                   Compilation helper
#
# ############################################################

type
  ## The type for all the public `genPubX` procedures for fields in `pub_fields.nim`
  FieldFnGenerator = proc(asy: Assembler_LLVM, fd: FieldDescriptor): string
  CurveFnGenerator = proc(asy: Assembler_LLVM, cd: CurveDescriptor): string

  NvidiaAssemblerObj* = object
    sm*: tuple[major, minor: int32] # compute capability version
    device*: CUdevice

    asy*: Assembler_LLVM
    fd*: FieldDescriptor
    cd*: CurveDescriptor

    cuCtx*: CUcontext
    cuMod*: CUmodule

  NvidiaAssembler* = ref NvidiaAssemblerObj

proc `=destroy`*(nv: NvidiaAssemblerObj) =
  ## XXX: Need to also call the finalizer for `asy` in the future!
  check nv.cuMod.cuModuleUnload()
  check nv.cuCtx.cuCtxDestroy()
  `=destroy`(nv.asy)

proc initNvAsm*[Name: static Algebra](field: type FF[Name], wordSize: int = 32, backend = bkNvidiaPTX): NvidiaAssembler =
  ## Constructs an `NvidiaAssembler` object, which compiles code for the Nvidia target
  ## using the LLVM backend.
  result = NvidiaAssembler()

  # Init LLVM
  # -------------------------
  initializeFullNVPTXTarget()

  # Init GPU
  # -------------------------
  result.device = cudaDeviceInit()

  check cuDeviceGetAttribute(result.sm.major, CU_DEVICE_ATTRIBUTE_COMPUTE_CAPABILITY_MAJOR, result.device)
  check cuDeviceGetAttribute(result.sm.minor, CU_DEVICE_ATTRIBUTE_COMPUTE_CAPABILITY_MINOR, result.device)

  # Codegen
  # -------------------------
  let name = if field is Fp: $Name & "_fp"
             else: $Name & "_fr"
  result.asy = Assembler_LLVM.new(bkNvidiaPTX, cstring("nvidia_" & name & $wordSize))
  result.fd = result.asy.ctx.configureField(
    name, field.bits(),
    field.getModulus().toHex(),
    v = 1, w = wordSize
  )
  result.asy.definePrimitives(result.fd)

proc initNvAsm*[Name: static Algebra](field: type EC_ShortW_Jac[Fp[Name], G1], wordSize: int = 32, backend = bkNvidiaPTX): NvidiaAssembler =
  ## Constructs an `NvidiaAssembler` object, which compiles code for the Nvidia target
  ## using the LLVM backend.
  result = NvidiaAssembler()

  # Init LLVM
  # -------------------------
  initializeFullNVPTXTarget()

  # Init GPU
  # -------------------------
  result.device = cudaDeviceInit()

  check cuDeviceGetAttribute(result.sm.major, CU_DEVICE_ATTRIBUTE_COMPUTE_CAPABILITY_MAJOR, result.device)
  check cuDeviceGetAttribute(result.sm.minor, CU_DEVICE_ATTRIBUTE_COMPUTE_CAPABILITY_MINOR, result.device)

  # Codegen
  # -------------------------
  let name = if field is Fp: $Name & "_fp"
             else: $Name & "_fr"
  result.asy = Assembler_LLVM.new(bkNvidiaPTX, cstring("nvidia_" & name & $wordSize))
  result.cd = result.asy.ctx.configureCurve(
    name, Fp[Name].bits(),
    Fp[Name].getModulus().toHex(),
    v = 1, w = wordSize,
    coef_a = Fp[Name].Name.getCoefA(),
    coef_B = Fp[Name].Name.getCoefB()
  )
  result.fd = result.cd.fd
  result.asy.definePrimitives(result.cd)

proc compile*(nv: NvidiaAssembler, kernName: string): CUfunction =
  ## Overload of `compile` below.
  ## Call this version if you have manually used the Assembler_LLVM object
  ## to build instructions and have a kernel name you wish to compile.
  let ptx = nv.asy.codegenNvidiaPTX(nv.sm) # convert to PTX

  # GPU exec
  # -------------------------
  check cuCtxCreate(nv.cuCtx, 0, nv.device)
  check cuModuleLoadData(nv.cuMod, ptx)
  # will be cleaned up when `NvidiaAssembler` goes out of scope

  result = nv.cuMod.getCudaKernel(kernName)

proc compile*(nv: NvidiaAssembler, fn: FieldFnGenerator): CUfunction =
  ## Given a function that generates code for a finite field operation, compile
  ## that function on the given Nvidia target and return a CUDA function.
  # execute the `fn`
  let kernName = nv.asy.fn(nv.fd)
  result = nv.compile(kernName)

proc compile*(nv: NvidiaAssembler, fn: CurveFnGenerator): CUfunction =
  ## Given a function that generates code for an elliptic curve operation, compile
  ## that function on the given Nvidia target and return a CUDA function.
  # execute the `fn`
  let kernName = nv.asy.fn(nv.cd)
  result = nv.compile(kernName)
