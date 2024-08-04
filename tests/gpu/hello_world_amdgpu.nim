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

  const datalayout1 {.used.} =
      "e-p:64:64-p1:64:64-p2:32:32-p3:32:32-p4:64:64-p5:32:32-p6:32:32-"               &
             "i64:64-"                                                                 &
             "v16:16-v24:32-"                                                          &
             "v32:32-v48:64-v96:128-v192:256-v256:256-v512:512-v1024:1024-v2048:2048-" &
             "n32:64-S32-A5-G1-ni:7"

  const datalayout2 =
      "e-p:64:64-p1:64:64-p2:32:32-p3:32:32-p4:64:64-p5:32:32-p6:32:32-p7:160:256:256:32-p8:128:128-" &
             "i64:64-"                                                                                &
             "v16:16-v24:32-v32:32-v48:64-v96:128-v192:256-v256:256-v512:512-v1024:1024-v2048:2048-"  &
             "n32:64-S32-A5-G1-ni:7:8"


  # ######################################
  # LLVM IR codegen

  module.setTarget(triple)
  module.setDataLayout(datalayout2)
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

    module.wrapInCallableHipKernel((addType, addKernel))

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

    module.wrapInCallableHipKernel((mulType, mulKernel))

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
  let gcnArchName = getGcnArchName(deviceId = 0)

  let machine = createTargetMachine(
    target = toTarget(triple),
    triple = triple,
    cpu = cstring(gcnArchName),
    features = "",
    level = CodeGenLevelAggressive,
    reloc = RelocDefault,
    codeModel = CodeModelDefault
  )

  let objectCode = machine.emitTo[:seq[byte]](module, ObjectFile)
  let assembly = machine.emitTo[:string](module, AssemblyFile)

  module.dispose()
  ctx.dispose()

  block:
    echo "================="
    echo "AMD GCN output"
    echo $assembly
    echo "================="

  let exeCode = objectCode.linkAmdGpu(gcnArchName)

  #######################################
  # GPU JIT
  var hipCtx: HipContext
  var hipMod: HipModule
  check hipCtxCreate(hipCtx, 0, hipDevice)
  check hipModuleLoadData(hipMod, exeCode[0].addr)
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
