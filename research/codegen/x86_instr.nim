# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  constantine/platforms/llvm/bindings/c_abi,
  constantine/platforms/llvm/llvm,
  constantine/platforms/primitives,
  constantine/math_compiler/ir,
  ./x86_inlineasm

export x86_inlineasm

# ############################################################
#
#                     x86 API
#
# ############################################################

proc defMulExt*(asy: Assembler_LLVM, wordSize: int): FnDef =

  let procName = if wordSize == 64: cstring"hw_mulExt64"
                 else: cstring"hw_mulExt32"

  let doublePrec_t = if wordSize == 64: asy.i128_t
                     else: asy.i64_t

  let mulExtTy = if wordSize == 64: function_t(doublePrec_t, [asy.i64_t, asy.i64_t])
                 else: function_t(doublePrec_t, [asy.i32_t, asy.i32_t])
  let mulExtKernel = asy.module.addFunction(procName, mulExtTy)
  let blck = asy.ctx.appendBasicBlock(mulExtKernel, "mulExtBody")
  asy.builder.positionAtEnd(blck)

  let bld = asy.builder

  let a = bld.zext(mulExtKernel.getParam(0), doublePrec_t)
  let b = bld.zext(mulExtKernel.getParam(1), doublePrec_t)
  let r = bld.mul(a, b)

  bld.ret r

  return (mulExtTy, mulExtKernel)

proc defHi*(asy: Assembler_LLVM, wordSize: int): FnDef =

  let procName = if wordSize == 64: cstring"hw_hi64"
                 else: cstring"hw_hi32"
  let doublePrec_t = if wordSize == 64: asy.i128_t
                     else: asy.i64_t
  let singlePrec_t = if wordSize == 64: asy.i64_t
                     else: asy.i32_t

  let hiTy = function_t(singlePrec_t, [doublePrec_t])

  let hiKernel = asy.module.addFunction(procName, hiTy)
  let blck = asy.ctx.appendBasicBlock(hiKernel, "hiBody")
  asy.builder.positionAtEnd(blck)

  let bld = asy.builder

  # %1 = zext i32 64 to i128
  let shift = bld.zext(constInt(asy.i32_t, culonglong wordSize, signExtend = LlvmBool(0)), doublePrec_t)
  # %hiLarge = lshr i128 %input, %1
  let hiLarge = bld.lshr(hiKernel.getParam(0), shift)
  # %hi = trunc i128 %hiLarge to i64
  let hi = bld.trunc(hiLarge, singlePrec_t)

  bld.ret hi

  return (hiTy, hiKernel)

proc defLo*(asy: Assembler_LLVM, wordSize: int): FnDef =

  let procName = if wordSize == 64: cstring"hw_lo64"
                 else: cstring"hw_lo32"
  let doublePrec_t = if wordSize == 64: asy.i128_t
                     else: asy.i64_t
  let singlePrec_t = if wordSize == 64: asy.i64_t
                     else: asy.i32_t

  let loTy = function_t(singlePrec_t, [doublePrec_t])

  let loKernel = asy.module.addFunction(procName, loTy)
  let blck = asy.ctx.appendBasicBlock(loKernel, "loBody")
  asy.builder.positionAtEnd(blck)

  let bld = asy.builder

  # %lo = trunc i128 %input to i64
  let lo = bld.trunc(loKernel.getParam(0), singlePrec_t)
  bld.ret lo
  return (loTy, loKernel)
