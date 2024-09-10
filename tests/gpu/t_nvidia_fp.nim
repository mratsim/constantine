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
  constantine/platforms/llvm/llvm,
  constantine/platforms/static_for,
  constantine/named/algebras,
  constantine/math/arithmetic,
  constantine/math/io/[io_bigints, io_fields],
  constantine/math_compiler/[ir, pub_fields, codegen_nvidia],
  # Test utilities
  helpers/prng_unsafe

var rng: RngState
let seed = uint32(getTime().toUnix() and (1'i64 shl 32 - 1)) # unixTime mod 2^32
rng.seed(seed)
echo "\n------------------------------------------------------\n"
echo "test_nvidia_fp xoshiro512** seed: ", seed

const Iters = 10

# Init LLVM
# -------------------------
initializeFullNVPTXTarget()

# Init GPU
# -------------------------
let cudaDevice = cudaDeviceInit()
var sm: tuple[major, minor: int32]
check cuDeviceGetAttribute(sm.major, CU_DEVICE_ATTRIBUTE_COMPUTE_CAPABILITY_MAJOR, cudaDevice)
check cuDeviceGetAttribute(sm.minor, CU_DEVICE_ATTRIBUTE_COMPUTE_CAPABILITY_MINOR, cudaDevice)

template gen_binop_test(
      testName: untyped,
      kernGenerator: untyped,
      cpuFn: untyped) =


  proc testName[Name: static Algebra](field: type FF[Name], wordSize: int) =
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

    let kernName = asy.kernGenerator(fd)
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

    for i in 0 ..< Iters:
      let a = rng.random_long01Seq(field)
      let b = rng.random_long01Seq(field)

      var rCPU, rGPU: field

      rCPU.cpuFn(a, b)
      kernel.exec(rGPU, a, b)

      doAssert bool(rCPU == rGPU)

gen_binop_test(t_field_add, genFpAdd, sum)
gen_binop_test(t_field_sub, genFpSub, diff)
gen_binop_test(t_field_mul, genFpMul, prod)

proc main() =
  const curves = [
    # P224,
    BN254_Nogami,
    BN254_Snarks,
    Edwards25519,
    Bandersnatch,
    Pallas,
    Vesta,
    # P256,
    # Secp256k1,
    BLS12_377,
    BLS12_381,
    BW6_761,
  ]

  suite "[Nvidia GPU] Field Arithmetic":
    staticFor i, 0, curves.len:
      const curve = curves[i]
      for wordSize in [32, 64]:
        test "Nvidia GPU field addition 𝔽p " & $wordSize & "-bit for " & $curve:
          t_field_add(Fp[curve], wordSize)
        test "Nvidia GPU field substraction 𝔽p " & $wordSize & "-bit for " & $curve:
          t_field_sub(Fp[curve], wordSize)
        test "Nvidia GPU field multiplication 𝔽p " & $wordSize & "-bit for " & $curve:
          if wordSize == 64:
            skip()
            # 64-bit integer fused-multiply-add with carry is buggy:
            # https://gist.github.com/mratsim/a34df1e091925df15c13208df7eda569#file-mul-py
            # https://forums.developer.nvidia.com/t/incorrect-result-of-ptx-code/221067
          else:
            t_field_mul(Fp[curve], wordSize)

        test "Nvidia GPU field addition 𝔽r " & $wordSize & "-bit for " & $curve:
          t_field_add(Fr[curve], wordSize)
        test "Nvidia GPU field substraction 𝔽r " & $wordSize & "-bit for " & $curve:
          t_field_sub(Fr[curve], wordSize)
        test "Nvidia GPU field multiplication 𝔽r " & $wordSize & "-bit for " & $curve:
          if wordSize == 64:
            skip()
            # 64-bit integer fused-multiply-add with carry is buggy:
            # https://gist.github.com/mratsim/a34df1e091925df15c13208df7eda569#file-mul-py
            # https://forums.developer.nvidia.com/t/incorrect-result-of-ptx-code/221067
          else:
            t_field_mul(Fr[curve], wordSize)

main()
