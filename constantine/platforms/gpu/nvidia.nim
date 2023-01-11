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
  ./llvm,
  ./nvidia_inlineasm

export
  nvidia_abi, nvidia_inlineasm,
  Flag, flag

# ############################################################
#
#                     Nvidia GPUs API
#
# ############################################################

# Versioning and hardware support
# ------------------------------------------------------------

# We likely want to use unified memory in the future to avoid having to copy back and from device explicitly
# - https://developer.nvidia.com/blog/unified-memory-cuda-beginners/
# - https://developer.nvidia.com/blog/unified-memory-in-cuda-6/
#
# Unified memory is fully supported starting from Pascal GPU (GTX 1080, 2016, Compute Capability SM6.0)
# Due to high demand for deep learning and cryptocurrency mining and an affordable price point
# It is unlikely that users have an older Nvidia GPU available.
#
# Hence we can target Cuda 9 at minimum (Sept 2017): https://developer.nvidia.com/cuda-toolkit-archive
# which corresponds to PTX ISA 6.0: https://docs.nvidia.com/cuda/parallel-thread-execution/index.html#release-notes__ptx-release-history
#
# Unfortunately, there is no easy programmatic way to retrieve the PTX ISA version supported
# only the Cuda/Compiler version (https://docs.nvidia.com/cuda/ptx-compiler-api/index.html#group__versioning)
# Hence it's likely easier to ask users to update Cuda in case of ISA incompatibility.

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

# LLVM IR
# ------------------------------------------------------------

proc tagCudaKernel(module: ModuleRef, fn: FnDef) =
  ## Tag a function as a Cuda Kernel, i.e. callable from host
  
  doAssert fn.fnTy.getReturnType().isVoid(), block:
    "Kernels must not return values but function returns " & $fn.fnTy.getReturnType().getTypeKind()

  let ctx = module.getContext()
  module.addNamedMetadataOperand(
    "nvvm.annotations",
    ctx.asValueRef(ctx.metadataNode([
      fn.fnImpl.asMetadataRef(),
      ctx.metadataNode("kernel"),
      constInt(ctx.int32_t(), 1, LlvmBool(false)).asMetadataRef()
    ]))
  )

proc setCallableCudaKernel*(module: ModuleRef, fn: FnDef) =
  ## Create a public wrapper of a cuda device function
  ##
  ## A function named `addmod` can be found by appending _public
  ##   check cuModuleGetFunction(fnPointer, cuModule, "addmod_public")
  
  let pubName = fn.fnImpl.getName() & "_public"
  let pubFn = module.addFunction(cstring(pubName), fn.fnTy)
  
  let ctx = module.getContext()
  let builder = ctx.createBuilder()
  defer: builder.dispose()

  let blck = ctx.appendBasicBlock(pubFn, "publicKernelBody")
  builder.positionAtEnd(blck)

  var args = newSeq[ValueRef](fn.fnTy.countParamTypes())
  for i, arg in mpairs(args):
    arg = pubFn.getParam(i.uint32)
  discard builder.call2(fn.fnTy, fn.fnImpl, args)

  # A public kernel must return void
  builder.retVoid()
  module.tagCudaKernel((fn.fnTy, pubFn))
