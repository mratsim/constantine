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
  constantine/math/io/[io_bigints, io_fields, io_ec],
  constantine/math/arithmetic,
  constantine/math/elliptic/ec_shortweierstrass_jacobian,
  constantine/platforms/abstractions,
  constantine/platforms/llvm/llvm,
  constantine/math_compiler/[ir, pub_fields, pub_curves, codegen_nvidia, impl_fields_globals],
  # Test utilities
  helpers/prng_unsafe

template genGetComponent*(asy: Assembler_LLVM, ed: CurveDescriptor, fn: typed): string =
  let name = ed.name & astToStr(fn)
  asy.llvmPublicFnDef(name, "ctt." & ed.name, asy.void_t, [ed.fd.fieldTy, ed.curveTy]):
    let M = asy.getModulusPtr(ed.fd)
    let (r, a) = llvmParams

    let ec = asy.asEcPoint(a, ed.curveTy)
    let rA = asy.asField(r, ed.fd.fieldTy)

    let x = fn(ec)
    asy.store(rA, x)

    asy.br.retVoid()
  name

proc genGetX*(asy: Assembler_LLVM, ed: CurveDescriptor): string =
  result = asy.genGetComponent(ed, getX)
proc genGetY*(asy: Assembler_LLVM, ed: CurveDescriptor): string =
  result = asy.genGetComponent(ed, getY)
proc genGetZ*(asy: Assembler_LLVM, ed: CurveDescriptor): string =
  result = asy.genGetComponent(ed, getZ)

proc exec*[T; U](jitFn: CUfunction, r: var T; a: U) =
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

  var rGPU, aGPU: CUdeviceptr
  check cuMemAlloc(rGPU, csize_t sizeof(r))
  check cuMemAlloc(aGPU, csize_t sizeof(a))

  check cuMemcpyHtoD(aGPU, a.addr, csize_t sizeof(a))

  let params = [pointer(rGPU.addr), pointer(aGPU.addr)]

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

# Init LLVM
# -------------------------
initializeFullNVPTXTarget()

# Init GPU
# -------------------------
let cudaDevice = cudaDeviceInit()
var sm: tuple[major, minor: int32]
check cuDeviceGetAttribute(sm.major, CU_DEVICE_ATTRIBUTE_COMPUTE_CAPABILITY_MAJOR, cudaDevice)
check cuDeviceGetAttribute(sm.minor, CU_DEVICE_ATTRIBUTE_COMPUTE_CAPABILITY_MINOR, cudaDevice)

template test[Name: static Algebra](field: type FF[Name], wordSize: int, a: EC_ShortW_Jac[field, G1], fn, cpuField: untyped): untyped =
  # Codegen
  # -------------------------
  let name = if field is Fp: $Name & "_fp"
             else: $Name & "_fr"
  let asy = Assembler_LLVM.new(bkNvidiaPTX, cstring("t_nvidia_" & name & $wordSize))
  let ed = asy.ctx.configureCurve(
    name, field.bits(),
    field.getModulus().toHex(),
    v = 1, w = wordSize
  )

  asy.definePrimitives(ed)

  let kernName = asy.fn(ed)
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

  # For CPU:
  var rCPU: field
  rCPU = a.cpuField

  # For GPU:
  var rGPU: field
  kernel.exec(rGPU, a)

  echo "Input: ", a.toHex()
  echo "CPU:   ", rCPU.toHex()
  echo "GPU:   ", rGPU.toHex()
  doAssert bool(rCPU == rGPU)

proc testX[Name: static Algebra](field: type FF[Name], wordSize: int, a: EC_ShortW_Jac[field, G1]) =
  test(field, wordSize, a, genGetX, x)
proc testY[Name: static Algebra](field: type FF[Name], wordSize: int, a: EC_ShortW_Jac[field, G1]) =
  test(field, wordSize, a, genGetY, y)
proc testZ[Name: static Algebra](field: type FF[Name], wordSize: int, a: EC_ShortW_Jac[field, G1]) =
  test(field, wordSize, a, genGetZ, z)

let x = "0x2ef34a5db00ff691849861d49415d8081d9d0e10cba33b57b2dd1f37f13eeee0"
let y = "0x2beb0d0d6115007676f30bcc462fe814bf81198848f139621a3e9fa454fe8e6a"
let pt = EC_ShortW_Jac[Fp[BN254_Snarks], G1].fromHex(x, y)
echo pt.toHex()

testX(Fp[BN254_Snarks], 64, pt)
testY(Fp[BN254_Snarks], 64, pt)
testZ(Fp[BN254_Snarks], 64, pt)
