# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  constantine/platforms/llvm/llvm,
  constantine/math_compiler/[ir, pub_fields]

const Fields = [
  (
    "bn254_snarks_fp", 254,
    "30644e72e131a029b85045b68181585d97816a916871ca8d3c208c16d87cfd47"
  ),
  (
    "bn254_snarks_fr", 254,
    "30644e72e131a029b85045b68181585d2833e84879b9709143e1f593f0000001"
  ),

  (
    "secp256k1_fp", 256,
    "fffffffffffffffffffffffffffffffffffffffffffffffffffffffefffffc2f"
  ),
  (
    "secp256k1_fr", 256,
    "fffffffffffffffffffffffffffffffebaaedce6af48a03bbfd25e8cd0364141"
  ),
  (
    "bls12_381_fp", 381,
    "1a0111ea397fe69a4b1ba7b6434bacd764774b84f38512bf6730d2a0f6b0f6241eabfffeb153ffffb9feffffffffaaab"
  ),
  (
    "bls12_381_fr", 255,
    "73eda753299d7d483339d80809a1d80553bda402fffe5bfeffffffff00000001"
  ),
  (
    "bls12_377_fp", 377,
    "01ae3a4617c510eac63b05c06ca1493b1a22d9f300f5138f1ef3622fba094800170b5d44300000008508c00000000001"
  ),
  (
    "bls12_377_fr", 253,
    "12ab655e9a2ca55660b44d1e5c37b00159aa76fed00000010a11800000000001"
  ),
  (
    "bls24_315_fp", 315,
    "4c23a02b586d650d3f7498be97c5eafdec1d01aa27a1ae0421ee5da52bde5026fe802ff40300001"
  ),
  (
    "bls12_315_fr", 253,
    "196deac24a9da12b25fc7ec9cf927a98c8c480ece644e36419d0c5fd00c00001"
  ),
  (
    "bls24_317_fp", 317,
    "1058CA226F60892CF28FC5A0B7F9D039169A61E684C73446D6F339E43424BF7E8D512E565DAB2AAB"
  ),
  (
    "bls12_317_fr", 255,
    "443F917EA68DAFC2D0B097F28D83CD491CD1E79196BF0E7AF000000000000001"
  ),
]

proc t_field_add() =
  let asy = Assembler_LLVM.new(bkX86_64_Linux, cstring("x86_poc"))
  for F in Fields:
    let fd = asy.ctx.configureField(
      F[0], F[1], F[2],
      v = 1, w = 64)

    asy.definePrimitives(fd)

    discard asy.genFpAdd(fd)

  echo "========================================="
  echo "LLVM IR unoptimized\n"

  echo asy.module
  echo "========================================="

  asy.module.verify(AbortProcessAction)

  # --------------------------------------------
  # See the assembly - note it might be different from what the JIT compiler did
  initializeFullNativeTarget()
  const triple = "x86_64-pc-linux-gnu"

  let machine = createTargetMachine(
    target = toTarget(triple),
    triple = triple,
    cpu = "",
    features = "", # "adx,bmi2", # TODO check the proper way to pass options
    level = CodeGenLevelDefault,
    reloc = RelocDefault,
    codeModel = CodeModelDefault
  )

  # Due to https://github.com/llvm/llvm-project/issues/102868
  # We want to reproduce the codegen from llc.cpp
  # However we can't reproduce the code from either
  # - LLVM16 https://github.com/llvm/llvm-project/blob/llvmorg-16.0.6/llvm/tools/llc/llc.cpp
  #   need legacy PassManagerRef and the PassManagerBuilder that interfaces between the
  #   legacy PssManagerRef and new PassBuilder has been deleted in LLVM17
  #
  # - and contrary to what is claimed in https://llvm.org/docs/NewPassManager.html#id2
  #   the C API of PassBuilderRef is ghost town.
  #
  # So we somewhat reproduce the optimization passes from
  # https://reviews.llvm.org/D145835

  let pbo = createPassBuilderOptions()
  pbo.setMergeFunctions()
  let err = asy.module.runPasses(
    # "default<O2>,memcpyopt,sroa,mem2reg,function-attrs,inline,gvn,dse,aggressive-instcombine,adce",
    "function(require<targetir>,require<targetlibinfo>,require<inliner-size-estimator>,require<memdep>,require<da>)" &
    ",function(aa-eval)" &
    ",always-inline,hotcoldsplit,inferattrs,instrprof,recompute-globalsaa" &
    ",cgscc(argpromotion,function-attrs)" &
    ",require<inline-advisor>,partial-inliner,called-value-propagation" &
    ",scc-oz-module-inliner,module-inline" & # Buggy optimization
    ",function(verify,loop-mssa(loop-reduce),mergeicmps,expand-memcmp,instsimplify)" &
    ",function(lower-constant-intrinsics,consthoist,partially-inline-libcalls,ee-instrument<post-inline>,scalarize-masked-mem-intrin,verify)" &
    ",memcpyopt,sroa,dse,aggressive-instcombine,gvn,ipsccp,deadargelim,adce" &
    "",
    machine,
    pbo
  )
  if not err.pointer().isNil():
    writeStackTrace()
    let errMsg = err.getErrorMessage()
    stderr.write("\"codegenX86_64\" for module '" & astToStr(module) & "' " & $instantiationInfo() &
                 " exited with error: " & $cstring(errMsg) & '\n')
    errMsg.dispose()
    quit 1

  echo "========================================="
  echo "LLVM IR optimized\n"

  echo asy.module
  echo "========================================="

  echo "========================================="
  echo "Assembly\n"

  echo machine.emitTo[:string](asy.module, AssemblyFile)
  echo "========================================="

  # var engine: ExecutionEngineRef
  # initializeFullNativeTarget()
  # createJITCompilerForModule(engine, asy.module, optLevel = 3)

  # let fn32 = cm32.genSymbol(opFpAdd)
  # let fn64 = cm64.genSymbol(opFpAdd)

  # let jitFpAdd64 = cast[proc(r: var array[4, uint64], a, b: array[4, uint64]){.noconv.}](
  #   engine.getFunctionAddress(cstring fn64)
  # )

  # var r: array[4, uint64]
  # r.jitFpAdd64([uint64 1, 2, 3, 4], [uint64 1, 1, 1, 1])
  # echo "jitFpAdd64 = ", r

  # # block:
  # #   Cleanup - Assembler_LLVM is auto-managed
  # #   engine.dispose()  # also destroys the module attached to it, which double_frees Assembler_LLVM asy.module
  # echo "LLVM JIT - calling FpAdd64 SUCCESS"

t_field_add()
