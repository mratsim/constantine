# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  constantine/platforms/llvm/llvm,
  constantine/math_compiler/codegen_amdgpu

echo "AMD GPU JIT compiler Hello World"

# Docs:
# - https://rocm.docs.amd.com/projects/llvm-project/en/latest/reference/rocmcc.html
# - https://llvm.org/docs/AMDGPUUsage.html


proc writeExampleAddMul(ctx: ContextRef, module: ModuleRef, addKernelName, mulKernelName: string) =

  # ######################################
  # Metadata

  const triple = "amdgcn-amd-amdhsa"

  # No mention of datalayout so using default

  # ######################################
  # LLVM IR codegen

  module.setTarget(triple)
  # module.setDataLayout(datalayout)
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

    addKernel.setCallingConvention(AMDGPU_KERNEL)

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

    mulKernel.setCallingConvention(AMDGPU_KERNEL)

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

proc getHipKernel(hipMod: HipModule, fnName: string): HipFunction =
  check hipModuleGetFunction(result, hipMod, fnName & "_public")

proc main() =

  #######################################
  # GPU init
  let hipDevice = hipDeviceInit()

  #######################################
  # LLVM IR
  let ctx = createContext()
  let module = ctx.createModule("test_nnvm")

  let addKernelName = "addKernel"
  let mulKernelName = "mulKernel"

  writeExampleAddMul(ctx, module, addKernelName, mulKernelName)
  module.verify(AbortProcessAction)

  #######################################
  # Compilation

  initializeFullAMDGPUTarget()
  const triple = "amdgcn-amd-amdhsa"

  let machine = createTargetMachine(
    target = toTarget(triple),
    triple = triple,
    cpu = cstring(getGcnArchName(deviceId = 0)),
    features = "",
    level = CodeGenLevelAggressive,
    reloc = RelocDefault,
    codeModel = CodeModelDefault
  )

  let machineCode = machine.emitToString(module, ObjectFile)
  let assembly = machine.emitToString(module, AssemblyFile)

  module.dispose()
  ctx.dispose()

  block:
    echo "================="
    echo "AMD GCN output"
    echo $assembly
    echo "================="

  #######################################
  # GPU JIT
  var hipCtx: HipContext
  var hipMod: HipModule
  check hipCtxCreate(hipCtx, 0, hipDevice)
  check hipModuleLoadData(hipMod, machineCode[0].addr)
  let addKernel = hipMod.getHipKernel(addKernelName)
  let mulKernel = hipMod.getHipKernel(mulKernelName)


  #######################################
  # Kernel launch
  var r{.noInit.}, a, b: array[2, uint64]

  a[1] = 0x00000000000001FF'u64; a[0] = 0xFFFFFFFFFFFFFFFF'u64
  b[1] = 0x0000000000000000'u64; b[0] = 0x0010000000000000'u64

  echo "r:   ", r.toString()
  echo "a:   ", a.toString()
  echo "b:   ", b.toString()

  var rGPU: HipDeviceptr
  check hipMalloc(rGPU, csize_t sizeof(r))

  let params = [pointer(rGPU.addr), pointer(a.addr), pointer(b.addr)]

  check hipModuleLaunchKernel(
          addKernel,
          1, 1, 1,
          1, 1, 1,
          0, HipStream(nil),
          params[0].unsafeAddr, nil)

  check hipMemcpyDtoH(r.addr, rGPU, csize_t sizeof(r))
  echo "a+b: ", r.toString()

  check hipModuleLaunchKernel(
          mulKernel,
          1, 1, 1,
          1, 1, 1,
          0, HipStream(nil),
          params[0].unsafeAddr, nil)

  check hipMemcpyDtoH(r.addr, rGPU, csize_t sizeof(r))
  echo "a*b: ", r.toString()

  #######################################
  # Cleanup

  check hipFree(rGPU)
  rGPU = HipDeviceptr(nil)

  check hipModuleUnload(hipMod)
  hipMod = HipModule(nil)

  check hipCtxDestroy(hipCtx)
  hipCtx = HipContext(nil)

main()
