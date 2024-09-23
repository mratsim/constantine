# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

#[
A basic example on how to store / load data on the GPU.

It showcases both how CUDA accepts value types by addresses on the host device (i.e. address
of a regular nim variable) and also how to do the same with manual allocation and then a
required `load2` instruction in the IR.
]#

import
  # Internal
  constantine/named/algebras,
  constantine/math/io/[io_bigints, io_fields],
  constantine/math/arithmetic,
  constantine/platforms/abstractions,
  constantine/platforms/llvm/llvm,
  constantine/math_compiler/[ir, pub_fields, codegen_nvidia]

type
  KernelGen = proc(asy: Assembler_LLVM, fd: FieldDescriptor): string
  ExecKernel = proc(jitFn: CUfunction, r: var bool; c: bool)

proc genStoreBool*(asy: Assembler_LLVM, fd: FieldDescriptor): string =
  let name = fd.name & "_store_bool"
  let ptrBool = pointer_t(asy.ctx.int1_t())
  asy.llvmPublicFnDef(name, "ctt." & fd.name, asy.void_t, [ptrBool, asy.ctx.int1_t()]):
    let (r, condition) = llvmParams
    asy.store(r, condition)
    asy.br.retVoid()
  return name

proc genStoreBoolPtr*(asy: Assembler_LLVM, fd: FieldDescriptor): string =
  let name = fd.name & "_store_bool_ptr"
  let ptrBool = pointer_t(asy.ctx.int1_t())
  asy.llvmPublicFnDef(name, "ctt." & fd.name, asy.void_t, [ptrBool, ptrBool]):
    let (r, condition) = llvmParams
    let x = asy.load2(asy.ctx.int1_t(), condition)
    asy.store(r, x)
    asy.br.retVoid()
  return name

proc execCondWorks*(jitFn: CUfunction, r: var bool; c: bool) =
  var rGPU: CUdeviceptr
  check cuMemAlloc(rGPU, csize_t sizeof(r))
  # no copy to GPU, only allocate
  let params = [pointer(rGPU.addr), pointer(c.addr)]

  check cuLaunchKernel(
          jitFn,
          1, 1, 1, # grid(x, y, z)
          1, 1, 1, # block(x, y, z)
          sharedMemBytes = 0,
          CUstream(nil),
          params[0].unsafeAddr, nil)

  check cuMemcpyDtoH(r.addr, rGPU, csize_t sizeof(r))
  check cuMemFree(rGPU)

proc execCondBroken*(jitFn: CUfunction, r: var bool; c: bool) =
  var rGPU, cGPU: CUdeviceptr
  check cuMemAlloc(rGPU, csize_t sizeof(r))
  check cuMemAlloc(cGPU, csize_t sizeof(c))

  check cuMemcpyHtoD(cGPU, c.addr, csize_t sizeof(c))
  let params = [pointer(rGPU.addr), pointer(cGPU.addr)]

  check cuLaunchKernel(
          jitFn,
          1, 1, 1, # grid(x, y, z)
          1, 1, 1, # block(x, y, z)
          sharedMemBytes = 0,
          CUstream(nil),
          params[0].unsafeAddr, nil)

  check cuMemcpyDtoH(r.addr, rGPU, csize_t sizeof(r))

  check cuMemFree(rGPU)
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

proc testName(wordSize: int, krn: KernelGen, execKrn: ExecKernel, inputNeedsPtr: bool) =
  # Codegen
  # -------------------------
  let name = "store_load"
  let asy = Assembler_LLVM.new(bkNvidiaPTX, cstring("t_nvidia_" & name & $wordSize))
  var fd: FieldDescriptor

  #asy.definePrimitives(fd)

  let kernName = asy.krn(fd)
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

  var cond = true #CtTrue
  var res: bool
  kernel.execKrn(res, cond)
  echo "Bool result ? ", res, " from : ", cond

  # Now verify also works using `execCuda`
  if inputNeedsPtr:
    ## If we need to pass an argument as a `ptr` type for the kernel, we also
    ## need to make sure we pass that argument to `inputs` either as a `ptr`
    ## or a `ref`!
    var condPtr: ref bool = new bool
    condPtr[] = cond
    kernel.execCuda(res = [res], inputs = [condPtr])
  else:
    kernel.execCuda(res = [res], inputs = [cond])

testName(64, genStoreBool, execCondWorks, false) # `cond` passed without copy to kernel
testName(64, genStoreBoolPtr, execCondBroken, true) # `cond` passed with copy to kernel as pointer
