# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  ../primitives,
  ./ir, ./llvm, ./nvidia

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
  ## - initializePasses()
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

  # https://www.llvm.org/docs/Passes.html
  let pm = createPassManager()

  machine.addAnalysisPasses(pm)
  pm.addDeduceFunctionAttributesPass()
  pm.addMemCpyOptPass()
  pm.addScalarReplacementOfAggregatesPass()
  pm.addPromoteMemoryToRegisterPass()
  pm.addGlobalValueNumberingPass()
  pm.addDeadStoreEliminationPass()
  pm.addInstructionCombiningPass()
  pm.addFunctionInliningPass()
  pm.addAggressiveDeadCodeEliminationPass()

  when false:
    # As most (all?) of our code is straightline, unoptimizable inline assembly, no loop and no branches
    # most optimizations, even at -O3, are not applicable
    let pmb = createPassManagerBuilder()
    pmb.setOptLevel(3)
    pmb.populateModulePassManager(pm)
    pmb.dispose()

  pm.run(asy.module)
  pm.dispose()

  return machine.emitToString(asy.module, AssemblyFile)

# ############################################################
#
#                      Code execution
#
# ############################################################

proc getCudaKernel*(cuMod: CUmodule, cm: CurveMetadata, opcode: Opcode): CUfunction =
  # Public kernels are appended _public
  let fnName = cm.genSymbol(opcode) & "_public"
  check cuModuleGetFunction(result, cuMod, fnName)

proc exec*[T](jitFn: CUfunction, r: var T, a, b: T) =
  ## Execute a binary operation in the form r <- op(a, b)
  ## on Nvidia GPU
  # The execution wrapper provided are mostly for testing and debugging low-level kernels
  # that serve as building blocks, like field addition or multiplication.
  # They aren't parallelizable so we are not concern about the grid and block size.
  # We also aren't concerned about the cuda stream
  
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