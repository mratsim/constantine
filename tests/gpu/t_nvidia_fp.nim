# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.


import
  # Standard library
  std/[unittest, times],
  # Internal
  ../../constantine/platforms/gpu/[llvm, nvidia, ir],
  ../../constantine/math/config/[curves, type_bigint],
  ../../constantine/math/io/io_bigints,
  ../../constantine/math/arithmetic,
  ../../constantine/math_gpu/fields_nvidia,
  # Test utilities
  ../../helpers/prng_unsafe

var rng: RngState
let seed = uint32(getTime().toUnix() and (1'i64 shl 32 - 1)) # unixTime mod 2^32
rng.seed(seed)
echo "\n------------------------------------------------------\n"
echo "test_nvidia_fp xoshiro512** seed: ", seed

const Iters = 10

proc init(T: type CurveMetadata, asy: Assembler_LLVM, curve: static Curve, wordSize: WordSize): T =
  CurveMetadata.init(
      asy.ctx,
      $curve & "_", wordSize,
      fpBits = uint32 curve.getCurveBitwidth(),
      fpMod = curve.Mod().toHex(),
      frBits = uint32 curve.getCurveOrderBitwidth(),
      frMod = curve.getCurveOrder().toHex()
    )

proc genFieldAddPTX(asy: Assembler_LLVM, cm: CurveMetadata) =
  let fpAdd = asy.field_add_gen(cm, fp)
  asy.module.setCallableCudaKernel(fpAdd)
  let frAdd = asy.field_add_gen(cm, fr)
  asy.module.setCallableCudaKernel(frAdd)

# Init LLVM
# -------------------------
initializeFullNVPTXTarget()
initializePasses()

# Init GPU
# -------------------------
let cudaDevice = cudaDeviceInit()
var sm: tuple[major, minor: int32]
check cuDeviceGetAttribute(sm.major, CU_DEVICE_ATTRIBUTE_COMPUTE_CAPABILITY_MAJOR, cudaDevice)
check cuDeviceGetAttribute(sm.minor, CU_DEVICE_ATTRIBUTE_COMPUTE_CAPABILITY_MINOR, cudaDevice)

proc t_field_add(curve: static Curve) =
  # Codegen
  # -------------------------
  let asy = Assembler_LLVM.new(bkNvidiaPTX, cstring("t_nvidia_" & $curve))
  let cm32 = CurveMetadata.init(asy, curve, size32)
  asy.genFieldAddPTX(cm32)
  let cm64 = CurveMetadata.init(asy, curve, size64)
  asy.genFieldAddPTX(cm64)

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

  let fpAdd32 = cuMod.getCudaKernel(cm32, opFpAdd)
  let fpAdd64 = cuMod.getCudaKernel(cm64, opFpAdd)
  let frAdd32 = cuMod.getCudaKernel(cm32, opFrAdd)
  let frAdd64 = cuMod.getCudaKernel(cm64, opFrAdd)

  # Fp
  for i in 0 ..< Iters:
    let a = rng.random_long01Seq(Fp[curve])
    let b = rng.random_long01Seq(Fp[curve])

    var rCPU, rGPU_32, rGPU_64: Fp[curve]

    rCPU.sum(a, b)
    fpAdd32.exec(rGPU_32, a, b)
    fpAdd64.exec(rGPU_64, a, b)

    doAssert bool(rCPU == rGPU_32)
    doAssert bool(rCPU == rGPU_64)

  # Fr
  for i in 0 ..< Iters:
    let a = rng.random_long01Seq(Fr[curve])
    let b = rng.random_long01Seq(Fr[curve])

    var rCPU, rGPU_32, rGPU_64: Fr[curve]

    rCPU.sum(a, b)
    frAdd32.exec(rGPU_32, a, b)
    frAdd64.exec(rGPU_64, a, b)

    doAssert bool(rCPU == rGPU_32)
    doAssert bool(rCPU == rGPU_64)

proc main() =
  const curves = [
    P224,
    BN254_Nogami,
    BN254_Snarks,
    Edwards25519,
    Bandersnatch,
    Pallas,
    Vesta,
    P256,
    Secp256k1,
    BLS12_377,
    BLS12_381,
    BW6_761
  ]

  suite "[Nvidia GPU] Field Addition":
    staticFor i, 0, curves.len:
      const curve = curves[i]
      test "Nvidia GPU field addition (𝔽p, 𝔽r) for " & $curve:
        t_field_add(curve)

main()