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

func cuModuleLoadData*(module: var CUmodule, sourceCode: openArray[char]): CUresult {.inline.}=
  cuModuleLoadData(module, sourceCode[0].unsafeAddr)

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
  # NOTE: In the destructor we don't want to quit on a `check` failure.
  # The reason is that if we throw an exception with an `NvidiaAssembler`
  # in scope, it will trigger the destructor here (with a likely invalid
  # state in the CUDA module / context). However, in this case
  # we will crash anyway and would just end up hiding the actual cause of
  # the error.
  # In the unlikely case that all CUDA operations worked correctly up
  # to this point, but then fail to unload, we currently ignore this
  # as a failure mode.
  # Hopefully we find a better solution in the future.
  check nv.cuMod.cuModuleUnload(), quitOnFailure = false
  check nv.cuCtx.cuCtxDestroy(), quitOnFailure = false
  `=destroy`(nv.asy)

proc getCudaKernel*(cuMod: CUmodule, fnName: string): CUfunction =
  check cuModuleGetFunction(result, cuMod, fnName[0].addr)

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
    coef_B = Fp[Name].Name.getCoefB(),
    curveOrderBitWidth = Fr[Name].bits()
  )
  result.fd = result.cd.fd
  result.asy.definePrimitives(result.cd)

proc compile*(nv: NvidiaAssembler, kernName: string): CUfunction =
  ## Overload of `compile` below.
  ## Call this version if you have manually used the Assembler_LLVM object
  ## to build instructions and have a kernel name you wish to compile.
  ##
  ## Use this overload if your generator function does not match the `FieldFnGenerator` or
  ## `CurveFnGenerator` signatures. This is useful if your function requires additional
  ## arguments that are compile time values in the context of LLVM.
  ##
  ## Example:
  ##
  ## ```nim
  ##  let nv = initNvAsm(EC, wordSize)
  ##  let kernel = nv.compile(asy.genEcMSM(cd, 3, 1000) # window size, num. points
  ## ```
  ## where `genEcMSM` returns the name of the kernel.

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

import ./experimental/cuda_execute_dsl
macro execCuda*(jitFn: CUfunction,
                res: typed,
                inputs: typed): untyped =
  ## See `execCuda` in `constantine/math_compiler/experimental/cuda_execute_dsl.nim`
  ## for an explanation.
  ##
  ## This LLVM overload makes sure we disallow passing simple structs
  ## via their pointer and instead always copy them (required due to our
  ## type definitions for finite field elements and elliptic curve points
  ## on the LLVM target).
  execCudaImpl(jitFn, newLit 1, newLit 1, res, inputs,
               passStructByPointer = false)
