# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  ./bindings/nvidia_abi {.all.},
  ./bindings/utils,
  ./llvm

export
  nvidia_abi,
  Flag, flag

# ############################################################
#
#                     Nvidia GPUs API
#
# ############################################################

# Cuda Driver API
# ------------------------------------------------------------

template check*(status: CUresult) =
  ## Check the status code of a CUDA operation
  ## Exit program with error if failure
  
  let code = status # ensure that the input expression is evaluated once only
  if code != CUDA_SUCCESS:
    stderr.write(astToStr(status) & " " & $instantiationInfo() & " exited with error: " & $code & '\n')
    quit 1

func cuModuleLoadData*(module: var CUmodule, sourceCode: openArray[char]): CUresult {.inline.}=
  cuModuleLoadData(module, sourceCode[0].unsafeAddr)
func cuModuleGetFunction*(kernel: var CUfunction, module: CUmodule, fnName: openArray[char]): CUresult {.inline.}=
  cuModuleGetFunction(kernel, module, fnName[0].unsafeAddr)

proc cudaDeviceInit(): CUdevice =
  
  check cuInit(0)
  
  var devCount: int32
  check cuDeviceGetCount(devCount)
  if devCount == 0:
    echo "cudaDeviceInit error: no devices supporting CUDA"
    quit 1
  
  var cuDevice: CUdevice
  check cuDeviceGet(cuDevice, 0)
  var name = newString(128)
  check cuDeviceGetName(name[0].addr, name.len.int32, cuDevice)
  echo "Using CUDA Device [0]: ", name

  var major, minor: int32
  check cuDeviceGetAttribute(major, CU_DEVICE_ATTRIBUTE_COMPUTE_CAPABILITY_MAJOR, cuDevice)
  check cuDeviceGetAttribute(minor, CU_DEVICE_ATTRIBUTE_COMPUTE_CAPABILITY_MINOR, cuDevice)
  echo "Compute Capability: SM ", major, ".", minor
  if major < 6:
    echo "Error: Device 0 is not sm_60 (Pascal generation, GTX 1080) or later"
    quit 1
  
  return cuDevice

# ############################################################
#
#                       NVVM IR
#
# ############################################################

proc tagCudaKernel*(module: ModuleRef, function: ValueRef) =
  ## Tag a function as a Cuda Kernel, i.e. callable from host
  
  # Upstream bug, getReturnType returns tkFunction for void functions.
  # doAssert function.getTypeOf().getReturnType().isVoid(), block:
  #   "Kernels must not return values but function returns " & $function.getTypeOf().getReturnType().getTypeKind()

  let ctx = module.getContext()
  module.addNamedMetadataOperand(
    "nvvm.annotations",
    ctx.asValueRef(ctx.metadataNode([
      function.asMetadataRef(),
      ctx.metadataNode("kernel"),
      constInt(ctx.int32_t(), 1, LlvmBool(false)).asMetadataRef()
    ]))
  )

# ############################################################
#
#                    Sanity Check
#
# ############################################################

when isMainModule:
  {.push hint[Name]: off.}

  template check(status: NvvmResult) =
    let code = status # Assign so execution is done once only.
    if code != NVVM_SUCCESS:
      echo astToStr(status), " ", instantiationInfo(), " exited with error: ", code
      echo code.nvvmGetErrorString()
      quit 1

  echo "Nvidia JIT compiler sanity check"

  #######################################
  # Metadata

  const triple = "nvptx64-nvidia-cuda"
  var irVersion: tuple[major, minor, majorDbg, minorDbg: int32]
  block:
    var version: tuple[major, minor: int32]
    check: nvvmVersion(version.major, version.minor)
    echo "nvvm v", version.major, ".", version.minor
    check: nvvmIRVersion(irVersion.major, irVersion.minor, irVersion.majorDbg, irVersion.minorDbg)
    echo "requires LLVM IR v", irVersion.major, ".", irVersion.minor

  #######################################
  # LLVM IR codegen

  # Datalayout for NVVM IR 1.8 (CUDA 11.6)
  const datalayout = "e-p:64:64:64-i1:8:8-i8:8:8-i16:16:16-i32:32:32-i64:64:64-i128:128:128-f32:32:32-f64:64:64-v16:16:16-v32:32:32-v64:64:64-v128:128:128-n16:32:64"

  let ctx = createContext()
  var module = ctx.createModule("test_nnvm")
  module.setTarget(triple)
  module.setDataLayout(datalayout)
  let i128 = ctx.int128_t()
  let void_t = ctx.void_t()

  let builder = ctx.createBuilder()

  block:
    let addType = function_t(void_t, [i128.pointer_t(), i128, i128], isVarArg = LlvmBool(false))
    let addKernel = module.addFunction("addKernel", addType)
    let blck = ctx.append_basic_block(addKernel, "addBody")
    builder.positionAtEnd(blck)
    let r = addKernel.getParam(0)
    let a = addKernel.getParam(1)
    let b = addKernel.getParam(2)
    let sum = builder.add(a, b, "sum")
    discard builder.store(sum, r)
    discard builder.retVoid()

    module.tagCudaKernel(addKernel)

  block:
    let mulType = function_t(void_t, [i128.pointer_t(), i128, i128], isVarArg = LlvmBool(false))
    let mulKernel = module.addFunction("mulKernel", mulType)
    let blck = ctx.append_basic_block(mulKernel, "mulBody")
    builder.positionAtEnd(blck)
    let r = mulKernel.getParam(0)
    let a = mulKernel.getParam(1)
    let b = mulKernel.getParam(2)
    let prod = builder.mul(a, b, "prod")
    discard builder.store(prod, r)
    discard builder.retVoid()

    module.tagCudaKernel(mulKernel)

  module.verify(AbortProcessAction)

  block:
    echo "================="
    echo "LLVM IR output"
    echo $module
    echo "================="

  #######################################
  # LLVM -> NNVM handover

  var prog{.noInit.}: NvvmProgram
  check nvvmCreateProgram(prog)

  # module.writeBitcodeToFile("arith.bc")
  let bitcode = module.toBitcode()
  check nvvmAddModuleToProgram(prog, bitcode, "arith")

  # Cleanup LLVM
  builder.dispose()
  module.dispose()
  ctx.dispose()

  #######################################
  # GPU init
  let cudaDevice = cudaDeviceInit()
  var sm: tuple[major, minor: int32]
  check cuDeviceGetAttribute(sm.major, CU_DEVICE_ATTRIBUTE_COMPUTE_CAPABILITY_MAJOR, cudaDevice)
  check cuDeviceGetAttribute(sm.minor, CU_DEVICE_ATTRIBUTE_COMPUTE_CAPABILITY_MINOR, cudaDevice)

  #######################################
  # GPU codegen

  check nvvmVerifyProgram(prog, 0, nil)

  block:
    var logSize: csize_t
    check nvvmGetProgramLogSize(prog, logSize)
    var log = newString(logSize)
    check nvvmGetProgramLog(prog, log[0].addr)
    echo "log:"
    echo log
    echo "----------------"

  let options = allocCStringArray(["-arch=compute_" & $sm.major & $sm.minor])
  check nvvmCompileProgram(prog, 1, options)
  deallocCStringArray(options)
  var ptxSize: csize_t
  check nvvmGetCompiledResultSize(prog, ptxSize)
  var ptx = newString(ptxSize)
  check nvvmGetCompiledResult(prog, ptx[0].addr)

  block:
    var logSize: csize_t
    check nvvmGetProgramLogSize(prog, logSize)
    var log = newString(logSize)
    check nvvmGetProgramLog(prog, log[0].addr)
    echo "log:"
    echo log
    echo "----------------"

  check nvvmDestroyProgram(prog)

  echo "================="
  echo "PTX output"
  echo ptx
  echo "================="

  var cuCtx: CUcontext
  var cuMod: CUmodule
  var addKernel, mulKernel: CUfunction
  check cuCtxCreate(cuCtx, 0, cudaDevice)
  check cuModuleLoadData(cuMod, ptx)
  check cuModuleGetFunction(addKernel, cuMod, "addKernel")
  check cuModuleGetFunction(mulKernel, cuMod, "mulKernel")

  #######################################
  # Kernel launch

  func toHex*(a: uint64): string =
    const hexChars = "0123456789abcdef"
    const L = 2*sizeof(uint64)
    result = newString(L)
    var a = a
    for j in countdown(result.len-1, 2):
      result[j] = hexChars[a and 0xF]
      a = a shr 4

  func toString*(a: openArray[uint64]): string =
    result = "0x"
    for i in countdown(result.len-1, 0):
      result.add toHex(a[i])

  var r{.noInit.}, a, b: array[2, uint64]

  a[1] = 0x00000000000001FF'u64; a[0] = 0xFFFFFFFFFFFFFFFF'u64
  b[1] = 0x0000000000000000'u64; b[0] = 0x0010000000000000'u64

  echo "r:   ", r.toString()
  echo "a:   ", a.toString()
  echo "b:   ", b.toString()

  var rGPU: CUdeviceptr
  check cuMemAlloc(rGPU, csize_t sizeof(r))

  let params = [pointer(rGPU.addr), pointer(a.addr), pointer(b.addr)]

  check cuLaunchKernel(
          addKernel,
          1, 1, 1,
          1, 1, 1,
          0, CUstream(nil),
          params[0].unsafeAddr, nil)

  check cuMemcpyDtoH(r.addr, rGPU, csize_t sizeof(r))
  echo "a+b: ", r.toString()

  check cuLaunchKernel(
          mulKernel,
          1, 1, 1,
          1, 1, 1,
          0, CUstream(nil),
          params[0].unsafeAddr, nil)

  check cuMemcpyDtoH(r.addr, rGPU, csize_t sizeof(r))
  echo "a*b: ", r.toString()

  #######################################
  # Cleanup

  check cuMemFree(rGPU)
  rGPU = CUdeviceptr(nil)

  check cuModuleUnload(cuMod)
  cuMod = CUmodule(nil)

  check cuCtxDestroy(cuCtx)
  cuCtx = CUcontext(nil)
