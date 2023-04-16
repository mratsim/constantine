# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import ../../constantine/platforms/gpu/[llvm, nvidia, bindings/c_abi]

# ############################################################
#
#                         NVVM
#
# ############################################################

# https://docs.nvidia.com/cuda/libnvvm-api/index.html
# https://docs.nvidia.com/pdf/libNVVM_API.pdf
# https://docs.nvidia.com/cuda/nvvm-ir-spec/index.html
# https://docs.nvidia.com/cuda/pdf/NVVM_IR_Specification.pdf

# ⚠ NVVM IR is based on LLVM 7.0.1 IR which dates from december 2018.
# There are a couple of caveats:
# - LLVM 7.0.1 is usually not available in repo, making installation difficult
# - There was a ABI breaking bug making the 7.0.1 and 7.1.0 versions messy (https://www.phoronix.com/news/LLVM-7.0.1-Released)
# - LLVM 7.0.1 does not have LLVMBuildCall2 and relies on the deprecated LLVMBuildCall meaning
#   supporting that and latest LLVM (for AMDGPU and SPIR-V backends) will likely have heavy costs
# - When generating a add-with-carry kernel with inline ASM calls from LLVM-14,
#   if the LLVM IR is passed as bitcode,
#   the kernel content is silently discarded, this does not happen with built-in add.
#   It is unsure if it's call2 or inline ASM incompatibility that causes the issues
# - When generating a add-with-carry kernel with inline ASM calls from LLVM-14,
#   if the LLVM IR is passed as testual IR, the code is refused with NVVM_ERROR_INVALID_IR

# Hence, using LLVM NVPTX backend instead of libNVVM is likely the sustainable way forward

static: echo "[Constantine] Using library libnvvm.so"
{.passl: "-L/opt/cuda/nvvm/lib64 -lnvvm".}

type
  NvvmResult* {.size: sizeof(cint).} = enum
    NVVM_SUCCESS = 0
    NVVM_ERROR_OUT_OF_MEMORY = 1
    NVVM_ERROR_PROGRAM_CREATION_FAILURE = 2
    NVVM_ERROR_IR_VERSION_MISMATCH = 3
    NVVM_ERROR_INVALID_INPUT = 4
    NVVM_ERROR_INVALID_PROGRAM = 5
    NVVM_ERROR_INVALID_IR = 6
    NVVM_ERROR_INVALID_OPTION = 7
    NVVM_ERROR_NO_MODULE_IN_PROGRAM = 8
    NVVM_ERROR_COMPILATION = 9

  NvvmProgram = distinct pointer

{.push cdecl, importc, dynlib: "libnvvm.so".}

proc nvvmGetErrorString*(r: NvvmResult): cstring
proc nvvmVersion*(major, minor: var int32): NvvmResult
proc nvvmIRVersion*(majorIR, minorIR, majorDbg, minorDbg: var int32): NvvmResult

proc nvvmCreateProgram*(prog: var NvvmProgram): NvvmResult
proc nvvmDestroyProgram*(prog: var NvvmProgram): NvvmResult
proc nvvmAddModuleToProgram*(prog: NvvmProgram, buffer: openArray[byte], name: cstring): NvvmResult {.wrapOpenArrayLenType: csize_t.}
proc nvvmLazyAddModuleToProgram*(prog: NvvmProgram, buffer: openArray[byte], name: cstring): NvvmResult {.wrapOpenArrayLenType: csize_t.}
proc nvvmCompileProgram*(prog: NvvmProgram; numOptions: int32; options: cstringArray): NvvmResult
proc nvvmVerifyProgram*(prog: NvvmProgram; numOptions: int32; options: cstringArray): NvvmResult
proc nvvmGetCompiledResultSize*(prog: NvvmProgram; bufferSizeRet: var csize_t): NvvmResult
proc nvvmGetCompiledResult*(prog: NvvmProgram; buffer: ptr char): NvvmResult
proc nvvmGetProgramLogSize*(prog: NvvmProgram; bufferSizeRet: var csize_t): NvvmResult
proc nvvmGetProgramLog*(prog: NvvmProgram; buffer: ptr char): NvvmResult

{.pop.} # {.push cdecl, importc, header: "<nvvm.h>".}

# ############################################################
#
#                    PTX Codegen
#
# ############################################################

template check*(status: NvvmResult) =
  let code = status # Assign so execution is done once only.
  if code != NVVM_SUCCESS:
    stderr.write astToStr(status) & " " & $instantiationInfo() & " exited with error: " & $code
    quit 1

proc getNvvmLog(prog: NvvmProgram): string {.used.} =
  var logSize: csize_t
  check nvvmGetProgramLogSize(prog, logSize)

  if logSize > 0:
    result = newString(logSize)
    check nvvmGetProgramLog(prog, result[0].addr)

proc ptxCodegenViaNvidiaNvvm(module: ModuleRef, sm: tuple[major, minor: int32]): string =
  ## PTX codegen via Nvidia NVVM

  # ######################################
  # LLVM -> NNVM handover

  var prog{.noInit.}: NvvmProgram
  check nvvmCreateProgram(prog)

  let bitcode = module.toBitcode()
  check nvvmAddModuleToProgram(prog, bitcode, cstring module.getIdentifier())

  # ######################################
  # GPU codegen

  check nvvmVerifyProgram(prog, 0, nil)

  let options = allocCStringArray(["-arch=compute_" & $sm.major & $sm.minor])
  check nvvmCompileProgram(prog, 1, options)
  deallocCStringArray(options)
  var ptxSize: csize_t
  check nvvmGetCompiledResultSize(prog, ptxSize)
  result = newString(ptxSize-1) # The NNVM size includes '\0' ending char while Nim excludes it.
  check nvvmGetCompiledResult(prog, result[0].addr)

  check nvvmDestroyProgram(prog)

proc ptxCodegenViaLlvmNvptx(module: ModuleRef, sm: tuple[major, minor: int32]): string =
  ## PTX codegen via LLVM NVPTX

  module.verify(AbortProcessAction)

  initializeFullNVPTXTarget()
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

  machine.emitToString(module, AssemblyFile)

# ############################################################
#
#                    Hello world
#
# ############################################################

echo "Nvidia JIT compiler Hello World"

proc writeExampleAddMul(ctx: ContextRef, module: ModuleRef, addKernelName, mulKernelName: string) =

  # ######################################
  # Metadata

  const triple = "nvptx64-nvidia-cuda"
  # Datalayout for NVVM IR 1.8 (CUDA 11.6)
  const datalayout = "e-p:64:64:64-i1:8:8-i8:8:8-i16:16:16-i32:32:32-i64:64:64-i128:128:128-f32:32:32-f64:64:64-v16:16:16-v32:32:32-v64:64:64-v128:128:128-n16:32:64"

  # ######################################
  # LLVM IR codegen

  module.setTarget(triple)
  module.setDataLayout(datalayout)
  let i128 = ctx.int128_t()
  let void_t = ctx.void_t()

  let builder = ctx.createBuilder()
  defer: builder.dispose()

  block:
    let addType = function_t(void_t, [i128.pointer_t(), i128, i128], isVarArg = LlvmBool(false))
    let addKernel = module.addFunction(addKernelName, addType)
    let blck = ctx.appendBasicBlock(addKernel, "addBody")
    builder.positionAtEnd(blck)
    let r = addKernel.getParam(0)
    let a = addKernel.getParam(1)
    let b = addKernel.getParam(2)
    let sum = builder.add(a, b, "sum")
    builder.store(sum, r)
    builder.retVoid()

    module.setCallableCudaKernel((addType, addKernel))

  block:
    let mulType = function_t(void_t, [i128.pointer_t(), i128, i128], isVarArg = LlvmBool(false))
    let mulKernel = module.addFunction(mulKernelName, mulType)
    let blck = ctx.appendBasicBlock(mulKernel, "mulBody")
    builder.positionAtEnd(blck)
    let r = mulKernel.getParam(0)
    let a = mulKernel.getParam(1)
    let b = mulKernel.getParam(2)
    let prod = builder.mul(a, b, "prod")
    builder.store(prod, r)
    builder.retVoid()

    module.setCallableCudaKernel((mulType, mulKernel))

  module.verify(AbortProcessAction)

  block:
    echo "================="
    echo "LLVM IR output"
    echo $module
    echo "================="

func toHex*(a: uint64): string =
  const hexChars = "0123456789abcdef"
  const L = 2*sizeof(uint64)
  result = newString(L)
  var a = a
  for j in countdown(result.len-1, 0):
    result[j] = hexChars[a and 0xF]
    a = a shr 4

func toString*(a: openArray[uint64]): string =
  result = "0x"
  for i in countdown(a.len-1, 0):
    result.add toHex(a[i])

type
  CodegenBackend = enum
    PTXviaNvidiaNvvm
    PTXviaLlvmNvptx

proc getCudaKernel(cuMod: CUmodule, fnName: string): CUfunction =
  check cuModuleGetFunction(result, cuMod, fnName & "_public")

proc main(backend: CodegenBackend) =

  #######################################
  # GPU init
  let cudaDevice = cudaDeviceInit()
  var sm: tuple[major, minor: int32]
  check cuDeviceGetAttribute(sm.major, CU_DEVICE_ATTRIBUTE_COMPUTE_CAPABILITY_MAJOR, cudaDevice)
  check cuDeviceGetAttribute(sm.minor, CU_DEVICE_ATTRIBUTE_COMPUTE_CAPABILITY_MINOR, cudaDevice)

  #######################################
  # LLVM IR
  let ctx = createContext()
  let module = ctx.createModule("test_nnvm")

  let addKernelName = "addKernel"
  let mulKernelName = "mulKernel"

  writeExampleAddMul(ctx, module, addKernelName, mulKernelName)

  #######################################
  # PTX codegen
  let ptx = case backend
    of PTXviaNvidiaNvvm:
      module.ptxCodegenViaNvidiaNVVM(sm)
    of PTXviaLlvmNvptx:
      module.ptxCodegenViaLlvmNvptx(sm)

  module.dispose()
  ctx.dispose()

  block:
    echo "================="
    echo "PTX output"
    echo $ptx
    echo "================="

  #######################################
  # GPU JIT
  var cuCtx: CUcontext
  var cuMod: CUmodule
  check cuCtxCreate(cuCtx, 0, cudaDevice)
  check cuModuleLoadData(cuMod, ptx)
  let addKernel = cuMod.getCudaKernel(addKernelName)
  let mulKernel = cuMod.getCudaKernel(mulKernelName)

  #######################################
  # Kernel launch
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

echo "\n\nCompilation via Nvidia NVVM\n###########################\n"
main(PTXviaNvidiaNvvm)
echo "\n\nEnd: Compilation via Nvidia NVVM\n################################"

echo "\n\nCompilation via LLVM NVPTX\n##########################\n"
main(PTXviaLlvmNvptx)
echo "\n\nEnd: Compilation via LLVM NVPTX\n###############################"
