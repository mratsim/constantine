# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  constantine/platforms/llvm/llvm,
  constantine/platforms/primitives,
  constantine/math_compiler/ir,
  ./x86_instr

echo "LLVM JIT compiler: Multiplication with MULX/ADOX/ADCX"

proc big_mul_gen(asy: Assembler_LLVM): FnDef =


  let procName = "big_mul_64x4"
  let N = 4
  let ty = array_t(asy.i64_t, N)
  let pty = pointer_t(ty)

  let bigMulTy = function_t(asy.void_t, [pty, pty, pty])
  let bigMulKernel = asy.module.addFunction(cstring procName, bigMulTy)
  let blck = asy.ctx.appendBasicBlock(bigMulKernel, "bigMulBody")
  asy.builder.positionAtEnd(blck)

  let bld = asy.builder

  let (hiTy, hiKernel) = asy.defHi(64)
  proc hi(builder: BuilderRef, a: ValueRef): ValueRef =
    return builder.call2(
      hiTy, hiKernel,
      [a], "hi64_"
    )

  let (loTy, loKernel) = asy.defLo(64)
  proc lo(builder: BuilderRef, a: ValueRef): ValueRef =
    return builder.call2(
      loTy, loKernel,
      [a], "lo64_"
    )

  let (mulExtTy, mulExtKernel) = asy.defMulExt(64)
  bld.positionAtEnd(blck)

  proc mulx(builder: BuilderRef, a, b: ValueRef): tuple[hi, lo: ValueRef] =
    # LLVM does not support multipel return value at the moment
    # https://nondot.org/sabre/LLVMNotes/MultipleReturnValues.txt
    # So we don't create an LLVM function
    let t = builder.call2(
      mulExtTy, mulExtKernel,
      [a, b], "mulx64_"
    )

    builder.positionAtEnd(blck)
    let lo = builder.lo(t)
    let hi = builder.hi(t)
    return (hi, lo)

  let r = bld.asArray(bigMulKernel.getParam(0), ty)
  let a = bld.asArray(bigMulKernel.getParam(1), ty)
  let b = bld.asArray(bigMulKernel.getParam(2), ty)

  let t = bld.makeArray(ty)

  block: # i = 0
    # TODO: properly implement add/adc in pure LLVM

    # TODO: ensure flags are cleared properly, compiler might optimize this away
    t[0] = bld.`xor`(t[0], t[0])
    let (hi, lo) = bld.mulx(a[0], b[0])
    r[0] = lo
    t[0] = hi

    for j in 1 ..< N:
      let (hi , lo) = bld.mulx(a[j], b[0])
      t[j] = hi
      # SHOWSTOPPER: LLVM ERROR: Inline asm not supported by this streamer because we don't have an asm parser for this target
      discard bld.adcx_rr(t[j-1], lo) # Replace by LLVM IR uadd_with_overflow

    # SHOWSTOPPER: LLVM ERROR: Inline asm not supported by this streamer because we don't have an asm parser for this target
    discard bld.adcx_rr(t[N-1], 0)

  # TODO: rotate t array

  # TODO: impl i in 1 ..< N

  bld.store(r, t)
  bld.retVoid()
  return (bigMulTy, bigMulKernel)

when isMainModule:
  # It's not the Nvidia PTX backend but it's fine
  let asy = Assembler_LLVM.new(bkX86_64_Linux, cstring("x86_poc"))
  let bigMul = asy.big_mul_gen()

  asy.module.verify(AbortProcessAction)

  echo "========================================="
  echo "LLVM IR\n"

  echo asy.module
  echo "========================================="


  var engine: ExecutionEngineRef
  initializeFullNativeTarget()
  createJITCompilerForModule(engine, asy.module, optLevel = 0)

  let jitMul = cast[proc(r: var array[4, uint64], a, b: array[4, uint64]){.noconv.}](
    engine.getFunctionAddress("big_mul_64x4")
  )

  var r: array[4, uint64]
  r.jitMul([uint64 1, 2, 3, 4], [uint64 1, 1, 1, 1])
  echo "jitMul = ", r

  # block:
  #   Cleanup - Assembler_LLVM is auto-managed
  #   engine.dispose()  # also destroys the module attached to it, which double_frees Assembler_LLVM asy.module
  echo "LLVM JIT - calling big_mul_64x4 SUCCESS"

  # --------------------------------------------
  # See the assembly- note it might be different from what the JIT compiler did

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

  # Output
  # ------------------------------------------------------------------

  #[
  LLVM JIT compiler: Multiplication with MULX/ADOX/ADCX
  =========================================
  LLVM IR

  ; ModuleID = 'x86_poc'
  source_filename = "x86_poc"
  target triple = "x86_64-pc-linux-gnu"

  define void @big_mul_64x4(ptr %0, ptr %1, ptr %2) {
  bigMulBody:
    %3 = alloca [4 x i64], align 8
    %4 = getelementptr inbounds [4 x i64], ptr %3, i32 0, i32 0
    %5 = load i64, ptr %4, align 4
    %6 = getelementptr inbounds [4 x i64], ptr %3, i32 0, i32 0
    %7 = load i64, ptr %6, align 4
    %8 = xor i64 %5, %7
    %9 = getelementptr inbounds [4 x i64], ptr %3, i32 0, i32 0
    store i64 %8, ptr %9, align 4
    %10 = getelementptr inbounds [4 x i64], ptr %1, i32 0, i32 0
    %11 = load i64, ptr %10, align 4
    %12 = getelementptr inbounds [4 x i64], ptr %2, i32 0, i32 0
    %13 = load i64, ptr %12, align 4
    %mulx64_ = call i128 @hw_mulExt64(i64 %11, i64 %13)
    %lo64_ = call i64 @hw_lo64(i128 %mulx64_)
    %hi64_ = call i64 @hw_hi64(i128 %mulx64_)
    %14 = getelementptr inbounds [4 x i64], ptr %0, i32 0, i32 0
    store i64 %lo64_, ptr %14, align 4
    %15 = getelementptr inbounds [4 x i64], ptr %3, i32 0, i32 0
    store i64 %hi64_, ptr %15, align 4
    %16 = getelementptr inbounds [4 x i64], ptr %1, i32 0, i32 1
    %17 = load i64, ptr %16, align 4
    %18 = getelementptr inbounds [4 x i64], ptr %2, i32 0, i32 0
    %19 = load i64, ptr %18, align 4
    %mulx64_1 = call i128 @hw_mulExt64(i64 %17, i64 %19)
    %lo64_2 = call i64 @hw_lo64(i128 %mulx64_1)
    %hi64_3 = call i64 @hw_hi64(i128 %mulx64_1)
    %20 = getelementptr inbounds [4 x i64], ptr %3, i32 0, i32 1
    store i64 %hi64_3, ptr %20, align 4
    %21 = getelementptr inbounds [4 x i64], ptr %3, i32 0, i32 0
    %22 = load i64, ptr %21, align 4
    %23 = call i64 asm "adcxq %2, %0;", "=r,%0,r"(i64 %22, i64 %lo64_2)
    %24 = getelementptr inbounds [4 x i64], ptr %1, i32 0, i32 2
    %25 = load i64, ptr %24, align 4
    %26 = getelementptr inbounds [4 x i64], ptr %2, i32 0, i32 0
    %27 = load i64, ptr %26, align 4
    %mulx64_4 = call i128 @hw_mulExt64(i64 %25, i64 %27)
    %lo64_5 = call i64 @hw_lo64(i128 %mulx64_4)
    %hi64_6 = call i64 @hw_hi64(i128 %mulx64_4)
    %28 = getelementptr inbounds [4 x i64], ptr %3, i32 0, i32 2
    store i64 %hi64_6, ptr %28, align 4
    %29 = getelementptr inbounds [4 x i64], ptr %3, i32 0, i32 1
    %30 = load i64, ptr %29, align 4
    %31 = call i64 asm "adcxq %2, %0;", "=r,%0,r"(i64 %30, i64 %lo64_5)
    %32 = getelementptr inbounds [4 x i64], ptr %1, i32 0, i32 3
    %33 = load i64, ptr %32, align 4
    %34 = getelementptr inbounds [4 x i64], ptr %2, i32 0, i32 0
    %35 = load i64, ptr %34, align 4
    %mulx64_7 = call i128 @hw_mulExt64(i64 %33, i64 %35)
    %lo64_8 = call i64 @hw_lo64(i128 %mulx64_7)
    %hi64_9 = call i64 @hw_hi64(i128 %mulx64_7)
    %36 = getelementptr inbounds [4 x i64], ptr %3, i32 0, i32 3
    store i64 %hi64_9, ptr %36, align 4
    %37 = getelementptr inbounds [4 x i64], ptr %3, i32 0, i32 2
    %38 = load i64, ptr %37, align 4
    %39 = call i64 asm "adcxq %2, %0;", "=r,%0,r"(i64 %38, i64 %lo64_8)
    %40 = getelementptr inbounds [4 x i64], ptr %3, i32 0, i32 3
    %41 = load i64, ptr %40, align 4
    %42 = call i64 asm "adcxq %2, %0;", "=r,%0,r"(i64 %41, i64 0)
    %43 = load [4 x i64], ptr %3, align 4
    store [4 x i64] %43, ptr %0, align 4
    ret void
  }

  define i64 @hw_hi64(i128 %0) {
  hiBody:
    %1 = lshr i128 %0, 64
    %2 = trunc i128 %1 to i64
    ret i64 %2
  }

  define i64 @hw_lo64(i128 %0) {
  loBody:
    %1 = trunc i128 %0 to i64
    ret i64 %1
  }

  define i128 @hw_mulExt64(i64 %0, i64 %1) {
  mulExtBody:
    %2 = zext i64 %0 to i128
    %3 = zext i64 %1 to i128
    %4 = mul i128 %2, %3
    ret i128 %4
  }

  =========================================
  jitMul = [0, 0, 0, 0]
  LLVM JIT - calling big_mul_64x4 SUCCESS
  =========================================
  Assembly

          .text
          .file   "x86_poc"
          .globl  big_mul_64x4
          .p2align        4, 0x90
          .type   big_mul_64x4,@function
  big_mul_64x4:
          .cfi_startproc
          movq    %rdx, %rcx
          movq    (%rdx), %rax
          mulq    (%rsi)
          movq    %rdx, %r8
          movq    %rax, (%rdi)
          movq    (%rcx), %rcx
          movq    %rcx, %rax
          mulq    8(%rsi)
          movq    %rdx, %r9
          movq    %rcx, %rax
          mulq    16(%rsi)
          movq    %rdx, %r10
          movq    %rcx, %rax
          mulq    24(%rsi)
          movq    %r8, (%rdi)
          movq    %r9, 8(%rdi)
          movq    %r10, 16(%rdi)
          movq    %rdx, 24(%rdi)
          retq
  .Lfunc_end0:
          .size   big_mul_64x4, .Lfunc_end0-big_mul_64x4
          .cfi_endproc

          .globl  hw_hi64
          .p2align        4, 0x90
          .type   hw_hi64,@function
  hw_hi64:
          movq    %rsi, %rax
          retq
  .Lfunc_end1:
          .size   hw_hi64, .Lfunc_end1-hw_hi64

          .globl  hw_lo64
          .p2align        4, 0x90
          .type   hw_lo64,@function
  hw_lo64:
          movq    %rdi, %rax
          retq
  .Lfunc_end2:
          .size   hw_lo64, .Lfunc_end2-hw_lo64

          .globl  hw_mulExt64
          .p2align        4, 0x90
          .type   hw_mulExt64,@function
  hw_mulExt64:
          movq    %rsi, %rax
          mulq    %rdi
          retq
  .Lfunc_end3:
          .size   hw_mulExt64, .Lfunc_end3-hw_mulExt64

          .section        ".note.GNU-stack","",@progbits

  =========================================
  ]#
