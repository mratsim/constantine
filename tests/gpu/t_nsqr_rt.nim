# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  # Internal
  constantine/named/algebras,
  constantine/math/io/[io_bigints, io_fields],
  constantine/math/arithmetic,
  constantine/platforms/abstractions,
  constantine/platforms/llvm/llvm,
  constantine/math_compiler/[ir, pub_fields, codegen_nvidia]

proc execNsqrRT*[T](jitFn: CUfunction, r: var T; a: T, count: int) =
  ## Execute a binary operation in the form r <- op(a) with `c` a condition
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

  var rGPU, aGPU, bGPU, cGPU: CUdeviceptr
  check cuMemAlloc(rGPU, csize_t sizeof(r))
  check cuMemAlloc(aGPU, csize_t sizeof(a))

  check cuMemcpyHtoD(aGPU, a.addr, csize_t sizeof(a))

  let params = [pointer(rGPU.addr), pointer(aGPU.addr), pointer(count.addr)]

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
  check cuMemFree(cGPU)

# Init LLVM
# -------------------------
initializeFullNVPTXTarget()

# Init GPU
# -------------------------
let cudaDevice = cudaDeviceInit()
var sm: tuple[major, minor: int32]
check cuDeviceGetAttribute(sm.major, CU_DEVICE_ATTRIBUTE_COMPUTE_CAPABILITY_MAJOR, cudaDevice)
check cuDeviceGetAttribute(sm.minor, CU_DEVICE_ATTRIBUTE_COMPUTE_CAPABILITY_MINOR, cudaDevice)

proc testName[Name: static Algebra](field: type FF[Name], wordSize: int, a: FF[Name], count: int) =
  # Codegen
  # -------------------------
  let name = if field is Fp: $Name & "_fp"
             else: $Name & "_fr"
  let asy = Assembler_LLVM.new(bkNvidiaPTX, cstring("t_nvidia_" & name & $wordSize))
  let fd = asy.ctx.configureField(
    name, field.bits(),
    field.getModulus().toHex(),
    v = 1, w = wordSize
  )

  asy.definePrimitives(fd)

  let kernName = asy.genFpNsqrRT(fd)
  let ptx = asy.codegenNvidiaPTX(sm)

  # GPU exec
  # -------------------------
  var cuCtx: CUcontext
  var cuMod: CUmodule
  check cuCtxCreate(cuCtx, 0, cudaDevice)
  check cuModuleLoadData(cuMod, ptx)
  defer:
    check cuMod.cuModuleUnload()
    check cuCtx.cuCtxDestroy()

  let kernel = cuMod.getCudaKernel(kernName)

  block Logic:
    # For CPU:
    var rCPU: field
    rCPU = a

    for i in countdown(count, 1):
      rCPU = rCPU * rCPU

    # For GPU:
    var rGPU: field
    kernel.execNsqrRT(rGPU, a, count)

    echo rCPU.toHex()
    echo rGPU.toHex()
    doAssert bool(rCPU == rGPU)

let a = Fp[BN254_Snarks].fromHex("0x12345678FF11FFAA00321321CAFECAFE")

testName(Fp[BN254_Snarks], 64, a, 2)
testName(Fp[BN254_Snarks], 64, a, 3)
testName(Fp[BN254_Snarks], 64, a, 4)
