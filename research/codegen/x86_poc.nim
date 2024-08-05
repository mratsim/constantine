# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  constantine/named/algebras,
  constantine/math/io/io_bigints,

  constantine/platforms/llvm/llvm,
  constantine/platforms/primitives,
  constantine/math_compiler/[ir, impl_fields_sat]

proc init(T: type CurveMetadata, asy: Assembler_LLVM, curve: static Algebra, wordSize: WordSize): T =
  CurveMetadata.init(
      asy.ctx,
      $curve & "_", wordSize,
      fpBits = uint32 Fp[curve].bits(),
      fpMod = Fp[curve].getModulus().toHex(),
      frBits = uint32 Fr[curve].bits(),
      frMod = Fr[curve].getModulus().toHex())

proc genFieldAddSat(asy: Assembler_LLVM, cm: CurveMetadata) =
  let fpAdd = asy.field_add_gen_sat(cm, fp)
  let frAdd = asy.field_add_gen_sat(cm, fr)


proc t_field_add(curve: static Algebra) =
  let asy = Assembler_LLVM.new(bkX86_64_Linux, cstring("x86_poc"))
  let cm32 = CurveMetadata.init(asy, curve, size32)
  asy.genFieldAddSat(cm32)
  let cm64 = CurveMetadata.init(asy, curve, size64)
  asy.genFieldAddSat(cm64)

  asy.module.verify(AbortProcessAction)

  echo "========================================="
  echo "LLVM IR\n"

  echo asy.module
  echo "========================================="

  var engine: ExecutionEngineRef
  initializeFullNativeTarget()
  createJITCompilerForModule(engine, asy.module, optLevel = 3)

  let fn32 = cm32.genSymbol(opFpAdd)
  let fn64 = cm64.genSymbol(opFpAdd)

  let jitFpAdd64 = cast[proc(r: var array[4, uint64], a, b: array[4, uint64]){.noconv.}](
    engine.getFunctionAddress(cstring fn64)
  )

  var r: array[4, uint64]
  r.jitFpAdd64([uint64 1, 2, 3, 4], [uint64 1, 1, 1, 1])
  echo "jitFpAdd64 = ", r

  # block:
  #   Cleanup - Assembler_LLVM is auto-managed
  #   engine.dispose()  # also destroys the module attached to it, which double_frees Assembler_LLVM asy.module
  echo "LLVM JIT - calling FpAdd64 SUCCESS"

  # --------------------------------------------
  # See the assembly - note it might be different from what the JIT compiler did

  const triple = "x86_64-pc-linux-gnu"

  let machine = createTargetMachine(
    target = toTarget(triple),
    triple = triple,
    cpu = "",
    features = "adx,bmi2", # TODO check the proper way to pass options
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
    stderr.write("\"codegenX86_64\" for module '" & astToStr(module) & "' " & $instantiationInfo() &
                 " exited with error: " & $cstring(errMsg) & '\n')
    errMsg.dispose()
    quit 1

  echo "========================================="
  echo "Assembly\n"

  echo machine.emitTo[:string](asy.module, AssemblyFile)
  echo "========================================="

t_field_add(Secp256k1)
