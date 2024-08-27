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
  ./ir

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
