# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import ./llvm

# ############################################################
#
#        LLVM IR super-instructions
#
# ############################################################

# This defines a collection of LLVM IR super-instructions
# Ideally those super-instructions compile-down
# to ISA optimized single instructions
#
# To ensure this, tests can be consulted at:
#   https://github.com/llvm/llvm-project/blob/llvmorg-18.1.8/llvm/test/CodeGen/

# Add-carry:
#  - https://github.com/llvm/llvm-project/blob/llvmorg-18.1.8/llvm/test/CodeGen/X86/add-of-carry.ll
#  - https://github.com/llvm/llvm-project/blob/llvmorg-18.1.8/llvm/test/CodeGen/X86/addcarry.ll
#  - https://github.com/llvm/llvm-project/blob/llvmorg-18.1.8/llvm/test/CodeGen/X86/addcarry2.ll
#  - https://github.com/llvm/llvm-project/blob/llvmorg-18.1.8/llvm/test/CodeGen/X86/adx-intrinsics.ll
#  - https://github.com/llvm/llvm-project/blob/llvmorg-18.1.8/llvm/test/CodeGen/X86/adx-intrinsics-upgrade.ll
#  - https://github.com/llvm/llvm-project/blob/llvmorg-18.1.8/llvm/test/CodeGen/X86/apx/adc.ll
#
# Sub-borrow
#  - https://github.com/llvm/llvm-project/blob/llvmorg-18.1.8/llvm/test/CodeGen/X86/sub-with-overflow.ll
#  - https://github.com/llvm/llvm-project/blob/llvmorg-18.1.8/llvm/test/CodeGen/AArch64/cgp-usubo.ll
#  - https://github.com/llvm/llvm-project/blob/llvmorg-18.1.8/llvm/test/CodeGen/X86/cgp-usubo.ll
#  - https://github.com/llvm/llvm-project/blob/llvmorg-18.1.8/llvm/test/CodeGen/X86/apx/sbb.ll
#
# Multiplication
#  - https://github.com/llvm/llvm-project/blob/llvmorg-18.1.8/llvm/test/CodeGen/X86/mulx32.ll
#  - https://github.com/llvm/llvm-project/blob/llvmorg-18.1.8/llvm/test/CodeGen/X86/mulx64.ll

# Warning 1:
#
#   There is no guarantee of constant-time with LLVM IR
#   It MAY introduce branches.
#   For workload that involves private keys or secrets
#   assembly MUST be used
#
#   Alternatively an assembly source file must be generated
#   and checked in the repo to avoid regressions should
#   the compiler "progress"
#
#   - https://github.com/mratsim/constantine/wiki/Constant-time-arithmetics#fighting-the-compiler
#   - https://blog.cr.yp.to/20240803-clang.html
#   - https://www.cl.cam.ac.uk/~rja14/Papers/whatyouc.pdf
#
# Warning 2:
#
#   Unfortunately implementing unrolled bigint arithmetic using word size
#   is fraught with perils for add-carry / sub-borrow
#   AMDGPU crash: https://github.com/llvm/llvm-project/issues/102058
#   ARM64 missed optim: https://github.com/llvm/llvm-project/issues/102062
#
#   and while using @llvm.usub.with.overflow.i64 allows ARM64 to solve the missing optimization
#   it is also missed on AMDGPU (or nvidia)

const SectionName = "ctt,superinstructions"

proc getInstrName(baseName: string, ty: TypeRef, builtin = false): string =
  var w, v: int # Wordsize and vector size
  if ty.getTypeKind() == tkInteger:
    w = int ty.getIntTypeWidth()
    v = 1
  elif ty.getTypeKind() == tkVector:
    v = int ty.getVectorSize()
    w = int ty.getElementType().getIntTypeWidth()
  else:
    doAssert false, "Invalid input type: " & $ty

  return baseName &
          (if v != 1: ".v" & $v else: ".") &
          (if builtin: "i" else: "u") & $w


proc def_llvm_add_overflow*(ctx: ContextRef, m: ModuleRef, wordTy: TypeRef) =
  let name = "llvm.uadd.with.overflow".getInstrName(wordTy, builtin = true)

  let br {.inject.} = ctx.createBuilder()
  defer: br.dispose()

  var fn = m.getFunction(cstring name)
  if fn.pointer.isNil():
    let retTy = ctx.struct_t([wordTy, ctx.int1_t()])
    let fnTy = function_t(retTy, [wordTy, wordTy])
    discard m.addFunction(cstring name, fnTy)

proc llvm_add_overflow_unsplit(br: BuilderRef, a, b: ValueRef, name = ""): ValueRef =
  ## (cOut, result) <- a+b+cIn
  let ty = a.getTypeOf()
  let intrin_name = "llvm.uadd.with.overflow".getInstrName(ty, builtin = true)

  let fn = br.getCurrentModule().getFunction(cstring intrin_name)
  doAssert not fn.pointer.isNil, "Function '" & intrin_name & "' does not exist in the module\n"

  let ctx = br.getContext()

  let retTy = ctx.struct_t([ty, ctx.int1_t()])
  let fnTy = function_t(retTy, [ty, ty])
  let addo = br.call2(fnTy, fn, [a, b], cstring name)
  return addo

proc llvm_add_overflow*(br: BuilderRef, a, b: ValueRef, name = ""): tuple[carryOut, r: ValueRef] =
  ## (cOut, result) <- a+b+cIn
  let addo = llvm_add_overflow_unsplit(br, a, b, name)
  let lo = br.extractValue(addo, 0)
  let cOut = br.extractValue(addo, 1)
  return (cOut, lo)

proc def_llvm_sub_overflow*(ctx: ContextRef, m: ModuleRef, wordTy: TypeRef) =
  let name = "llvm.usub.with.overflow".getInstrName(wordTy, builtin = true)

  let br {.inject.} = ctx.createBuilder()
  defer: br.dispose()

  var fn = m.getFunction(cstring name)
  if fn.pointer.isNil():
    let retTy = ctx.struct_t([wordTy, ctx.int1_t()])
    let fnTy = function_t(retTy, [wordTy, wordTy])
    discard m.addFunction(cstring name, fnTy)

proc llvm_sub_overflow*(br: BuilderRef, a, b: ValueRef, name = ""): tuple[borrowOut, r: ValueRef] =
  ## (cOut, result) <- a+b+cIn
  let ty = a.getTypeOf()
  let intrin_name = "llvm.usub.with.overflow".getInstrName(ty, builtin = true)

  let fn = br.getCurrentModule().getFunction(cstring intrin_name)
  doAssert not fn.pointer.isNil, "Function '" & intrin_name & "' does not exist in the module\n"

  let ctx = br.getContext()

  let retTy = ctx.struct_t([ty, ctx.int1_t()])
  let fnTy = function_t(retTy, [ty, ty])
  let subo = br.call2(fnTy, fn, [a, b], cstring name)
  let lo = br.extractValue(subo, 0)
  let bOut = br.extractValue(subo, 1)
  return (bOut, lo)

template defSuperInstruction[N: static int](
            module: ModuleRef, baseName: string,
            returnType: TypeRef,
            paramTypes: array[N, TypeRef],
            body: untyped) =
  ## Boilerplate for super instruction definition
  ## Creates a magic `llvmParams` variable to tuple-destructure
  ## to access the inputs
  ## and `br` for building the instructions
  let ty = paramTypes[0]
  let name = baseName.getInstrName(ty)

  let ctx = module.getContext()
  let br {.inject.} = ctx.createBuilder()
  defer: br.dispose()

  var fn = module.getFunction(cstring name)
  if fn.pointer.isNil():
    let fnTy = function_t(returnType, paramTypes)
    fn = module.addFunction(cstring name, fnTy)
    let blck = ctx.appendBasicBlock(fn)
    br.positionAtEnd(blck)

    let llvmParams {.inject.} = unpackParams(br, (paramTypes, paramTypes))
    template tagParameter(idx: int, attr: string) {.inject, used.} =
      let a = asy.ctx.createAttr(cstring attr)
      fn.addAttribute(cint idx, a)
    body

    fn.setFnCallConv(Fast)
    fn.setLinkage(linkInternal)
    fn.setSection(SectionName)
    fn.addAttribute(kAttrFnIndex, ctx.createAttr("alwaysinline"))

proc def_hi*(ctx: ContextRef, m: ModuleRef, toTy: TypeRef, fromTy: TypeRef) =
  ## Define result <- a >> oversize
  ## with oversize the number of bits of `a` shifted out
  ## and baseTy the type of `a` after shifting

  let retType = toTy
  let inType = [fromTy]
  let toBits = toTy.getIntTypeWidth()
  let fromBits = fromTy.getIntTypeWidth()
  let shift = fromBits - toBits

  m.defSuperInstruction("hi.u" & $toBits & ".from", retType, inType):
    let a = llvmParams

    let s = constInt(ctx.int8_t(), shift)
    let shift = br.zext(s, fromTy)
    let hiLarge = br.lshr(a, shift)
    let hi = br.trunc(hiLarge, toTy)
    br.ret(hi)

proc hi*(br: BuilderRef, a: ValueRef, toTy: TypeRef, name = "hi_"): ValueRef =
  ## Get the high part of the input
  ##   result <- a >> oversize
  let fromTy = a.getTypeOf()
  let toBits = toTy.getIntTypeWidth()
  let defName = ("hi.u" & $toBits & ".from").getInstrName(fromTy)

  let fn = br.getCurrentModule().getFunction(cstring defName)
  doAssert not fn.pointer.isNil, "Function '" & defName & "' does not exist in the module\n"

  let retTy = toTy
  let fnTy = function_t(retTy, [fromTy])
  let hi = br.call2(fnTy, fn, [a], cstring(name))
  hi.setInstrCallConv(Fast)
  return hi

proc def_addcarry*(ctx: ContextRef, m: ModuleRef, carryTy, wordTy: TypeRef) =
  ## Define (carryOut, result) <- a+b+carryIn

  let retType = ctx.struct_t([carryTy, wordTy])
  let inType = [wordTy, wordTy, carryTy]

  m.defSuperInstruction("addcarry", retType, inType):
    let (a, b, carryIn) = llvmParams

    let (carry0, add) = br.llvm_add_overflow(a, b)
    let cIn = br.zext(carryIn, wordTy)
    let (carry1, adc) = br.llvm_add_overflow(cIn, add)
    let carryOut = br.`or`(carry0, carry1)

    var ret = br.insertValue(poison(retType), adc, 1)
    ret = br.insertValue(ret, carryOut, 0)
    br.ret(ret)

proc addcarry_unsplit(br: BuilderRef, a, b, carryIn: ValueRef, name = "adc_"): ValueRef =
  ## (cOut, result) <- a+b+cIn
  let ty = a.getTypeOf()
  let tyC = carryIn.getTypeOf()
  let defName = "addcarry".getInstrName(ty)

  let fn = br.getCurrentModule().getFunction(cstring defName)
  doAssert not fn.pointer.isNil, "Function '" & defName & "' does not exist in the module\n"

  let retTy = br.getContext().struct_t([tyC, ty])
  let fnTy = function_t(retTy, [ty, ty, tyC])
  let adc = br.call2(fnTy, fn, [a, b, carryIn], cstring(name))
  adc.setInstrCallConv(Fast)
  return adc

proc addcarry*(br: BuilderRef, a, b, carryIn: ValueRef, name = "adc_"): tuple[carryOut, r: ValueRef] =
  ## (cOut, result) <- a+b+cIn
  let adc = br.addcarry_unsplit(a, b, carryIn, name)
  let lo = br.extractValue(adc, 1)
  let cOut = br.extractValue(adc, 0)
  return (cOut, lo)

proc def_subborrow*(ctx: ContextRef, m: ModuleRef, borrowTy, wordTy: TypeRef) =
  ## Define (borrowOut, result) <- a-b-borrowIn

  let retType = ctx.struct_t([borrowTy, wordTy])
  let inType = [wordTy, wordTy, borrowTy]

  m.defSuperInstruction("subborrow", retType, inType):
    let (a, b, borrowIn) = llvmParams

    let (borrow0, sub) = br.llvm_sub_overflow(a, b)
    let bIn = br.zext(borrowIn, wordTy)
    let (borrow1, sbb) = br.llvm_sub_overflow(sub, bIn)
    let borrowOut = br.`or`(borrow0, borrow1)

    var ret = br.insertValue(poison(retType), sbb, 1)
    ret = br.insertValue(ret, borrowOut, 0)
    br.ret(ret)

proc subborrow*(br: BuilderRef, a, b, borrowIn: ValueRef, name = "sbb_"): tuple[borrowOut, r: ValueRef] =
  ## (cOut, result) <- a+b+cIn
  let ty = a.getTypeOf()
  let tyC = borrowIn.getTypeOf()
  let defName = "subborrow".getInstrName(ty)

  let fn = br.getCurrentModule().getFunction(cstring defName)
  doAssert not fn.pointer.isNil, "Function '" & defName & "' does not exist in the module\n"

  let retTy = br.getContext().struct_t([tyC, ty])
  let fnTy = function_t(retTy, [ty, ty, tyC])
  let sbb = br.call2(fnTy, fn, [a, b, borrowIn], cstring(name))
  sbb.setInstrCallConv(Fast)
  let lo = br.extractValue(sbb, 1)
  let bOut = br.extractValue(sbb, 0)
  return (bOut, lo)

proc def_mullo_adc*(ctx: ContextRef, m: ModuleRef, carryTy, wordTy: TypeRef) =
  ## Define fused multiplication + add with carry
  ## On 64-bit
  ##   (cOut, result) <- (a*b) mod 64 + c + carry

  let retType = ctx.struct_t([carryTy, wordTy])
  let inType = [wordTy, wordTy, wordTy, carryTy]

  m.defSuperInstruction("mullo_adc", retType, inType):
    let (a, b, c, carryIn) = llvmParams
    
    let t = br.mul(a, b)
    br.ret(br.addcarry_unsplit(t, c, carryIn))

proc mullo_adc*(br: BuilderRef, a, b, c, carryIn: ValueRef, name = "mullo_adc_"): tuple[carryOut, r: ValueRef] =
  ## Fused multiplication + add with carry
  ## On 64-bit
  ##   (cOut, result) <- (a*b) mod 64 + c + carry
  let ty = a.getTypeOf()
  let tyC = carryIn.getTypeOf()
  let defName = "mullo_adc".getInstrName(ty)

  let fn = br.getCurrentModule().getFunction(cstring defName)
  doAssert not fn.pointer.isNil, "Function '" & defName & "' does not exist in the module\n"

  let retTy = br.getContext().struct_t([tyC, ty])
  let fnTy = function_t(retTy, [ty, ty, ty, tyC])
  let mullo_adc = br.call2(fnTy, fn, [a, b, c, carryIn], cstring(name))
  mullo_adc.setInstrCallConv(Fast)
  let lo = br.extractValue(mullo_adc, 1)
  let cOut = br.extractValue(mullo_adc, 0)
  return (cOut, lo)

proc def_mulhi*(ctx: ContextRef, m: ModuleRef, wordTy: TypeRef) =
  ## Define mulExt.hi
  ## On 64-bit
  ##   result <- (a*b) >> 64

  let retType = wordTy
  let inType = [wordTy, wordTy]

  let bits = wordTy.getIntTypeWidth()
  let dbl = bits shl 1
  let dblTy = ctx.int_t(dbl)

  m.defSuperInstruction("mulhi", retType, inType):
    let (a, b) = llvmParams
    let ax = br.zext(a, dblTy)
    let bx = br.zext(b, dblTy)
    let t = br.mulNUW(ax, bx)
    let hi = br.hi(t, wordTy)
    br.ret(hi)

proc mulhi*(br: BuilderRef, a, b: ValueRef, name = "mulhi_"): ValueRef =
  ## multiplication (high word)
  ## On 64-bit
  ##   result <- (a*b) >> 64
  let ty = a.getTypeOf()
  let defName = "mulhi".getInstrName(ty)

  let fn = br.getCurrentModule().getFunction(cstring defName)
  doAssert not fn.pointer.isNil, "Function '" & defName & "' does not exist in the module\n"

  let retTy = ty
  let fnTy = function_t(retTy, [ty, ty])
  let mulhi = br.call2(fnTy, fn, [a, b], cstring(name))
  mulhi.setInstrCallConv(Fast)
  return mulhi

proc def_mulhi_adc*(ctx: ContextRef, m: ModuleRef, carryTy, wordTy: TypeRef) =
  ## Define fused multiplication + add with carry
  ## On 64-bit
  ##   (cOut, result) <- (a*b) >> 64 + c + carry

  let retType = ctx.struct_t([carryTy, wordTy])
  let inType = [wordTy, wordTy, wordTy, carryTy]

  m.defSuperInstruction("mulhi_adc", retType, inType):
    let (a, b, c, carryIn) = llvmParams
    let mulhi = br.mulhi(a, b)
    br.ret(br.addcarry_unsplit(mulhi, c, carryIn))

proc mulhi_adc*(br: BuilderRef, a, b, c, carryIn: ValueRef, name = "mulhi_adc_"): tuple[carryOut, r: ValueRef] =
  ## Fused multiplication (high word) + add with carry
  ## On 64-bit
  ##   (cOut, result) <- (a*b) >> 64 + c + carry
  let ty = a.getTypeOf()
  let tyC = carryIn.getTypeOf()
  let defName = "mulhi_adc".getInstrName(ty)

  let fn = br.getCurrentModule().getFunction(cstring defName)
  doAssert not fn.pointer.isNil, "Function '" & defName & "' does not exist in the module\n"

  let retTy = br.getContext().struct_t([tyC, ty])
  let fnTy = function_t(retTy, [ty, ty, ty, tyC])
  let mulhi_adc = br.call2(fnTy, fn, [a, b, c, carryIn], cstring(name))
  mulhi_adc.setInstrCallConv(Fast)
  let hi = br.extractValue(mulhi_adc, 1)
  let cOut = br.extractValue(mulhi_adc, 0)
  return (cOut, hi)

# Placeholders
# ----------------------------------------------------------------------
# Currently unused instructions that need to be converted
# to defSuperInstruction

# proc mulExt*(bld: BuilderRef, a, b: ValueRef): tuple[hi, lo: ValueRef] =
#   ## Extended precision multiplication
#   ## (hi, lo) <- a*b
#   let ctx = bld.getContext()
#   let ty = a.getTypeOf()
#   let bits = ty.getIntTypeWidth()
#   let dbl = bits shl 1
#   let dblTy = ctx.int_t(dbl)

#   let a = bld.zext(a, dblTy, name = "mulx0_")
#   let b = bld.zext(b, dblTy, name = "mulx1_")
#   let r = bld.mulNUW(a, b, name = "mulx_")

#   let lo = bld.trunc(r, ty, name = "mullo_")
#   let hi = bld.hi(r, ty, oversize = bits, prefix = "mulhi_")
#   return (hi, lo)

# proc smulExt*(bld: BuilderRef, a, b: ValueRef): tuple[hi, lo: ValueRef] =
#   ## Signed extended precision multiplication
#   ## (hi, lo) <- a*b
#   let ctx = bld.getContext()
#   let ty = a.getTypeOf()
#   let bits = ty.getIntTypeWidth()
#   let dbl = bits shl 1
#   let dblTy = ctx.int_t(dbl)

#   let a = bld.sext(a, dblTy, name = "smulx0_")
#   let b = bld.sext(b, dblTy, name = "smulx1_")
#   let r = bld.mulNSW(a, b, name = "smulx0_")

#   let lo = bld.trunc(r, ty, name = "smullo_")
#   let hi = bld.hi(r, ty, oversize = bits, prefix = "smulhi_")
#   return (hi, lo)

# proc mulExtadd1*(bld: BuilderRef, a, b, c: ValueRef): tuple[hi, lo: ValueRef] =
#   ## Extended precision multiplication + addition
#   ## (hi, lo) <- a*b + c
#   ##
#   ## Note: 0xFFFFFFFF² -> (hi: 0xFFFFFFFE, lo: 0x00000001)
#   ##       so adding any c cannot overflow
#   let ctx = bld.getContext()
#   let ty = a.getTypeOf()
#   let bits = ty.getIntTypeWidth()
#   let dbl = bits shl 1
#   let dblTy = ctx.int_t(dbl)

#   let a = bld.zext(a, dblTy, name = "fmax0_")
#   let b = bld.zext(b, dblTy, name = "fmax1_")
#   let ab = bld.mulNUW(a, b, name = "fmax01_")

#   let c = bld.zext(c, dblTy, name = "fmax2_")
#   let r = bld.addNUW(ab, c, name = "fmax_")

#   let lo = bld.trunc(r, ty, name = "fmalo_")
#   let hi = bld.hi(r, ty, oversize = bits, prefix = "fmahi_")
#   return (hi, lo)

# proc mulExtadd2*(bld: BuilderRef, a, b, c1, c2: ValueRef): tuple[hi, lo: ValueRef] =
#   ## Extended precision multiplication + addition + addition
#   ## (hi, lo) <- a*b + c1 + c2
#   ##
#   ## Note: 0xFFFFFFFF² -> (hi: 0xFFFFFFFE, lo: 0x00000001)
#   ##       so adding 0xFFFFFFFF leads to (hi: 0xFFFFFFFF, lo: 0x00000000)
#   ##       and we have enough space to add again 0xFFFFFFFF without overflowing
#   let ctx = bld.getContext()
#   let ty = a.getTypeOf()
#   let bits = ty.getIntTypeWidth()
#   let dbl = bits shl 1
#   let dblTy = ctx.int_t(dbl)

#   let a = bld.zext(a, dblTy, name = "fmaa0_")
#   let b = bld.zext(b, dblTy, name = "fmaa1_")
#   let ab = bld.mulNUW(a, b, name = "fmaa01_")

#   let c1 = bld.zext(c1, dblTy, name = "fmaa2_")
#   let abc1 = bld.addNUW(ab, c1, name = "fmaa012_")
#   let c2 = bld.zext(c2, dblTy, name = "fmaa3_")
#   let r = bld.addNUW(abc1, c2, name = "fmaa_")

#   let lo = bld.trunc(r, ty, name = "fmaalo_")
#   let hi = bld.hi(r, ty, oversize = bits, prefix = "fmaahi_")
#   return (hi, lo)

# proc mulExtAcc*(bld: BuilderRef, tuv: var ValueRef, a, b: ValueRef) =
#   ## (t, u, v) <- (t, u, v) + a * b
#   let ctx = bld.getContext()

#   let ty = a.getTypeOf()
#   let bits = ty.getIntTypeWidth()

#   let x3ty = tuv.getTypeOf()
#   let x3bits = x3ty.getIntTypeWidth()

#   doAssert bits * 3 == x3bits

#   let dbl = bits shl 1
#   let dblTy = ctx.int_t(dbl)

#   let a = bld.zext(a, dblTy, name = "mac0_")
#   let b = bld.zext(b, dblTy, name = "mac1_")
#   let ab = bld.mulNUW(a, b, name = "mac01_")

#   let wide_ab = bld.zext(ab, x3ty, name = "mac01x_")
#   let r = bld.addNUW(tuv, wide_ab, "mac_")

#   tuv = r

# proc mulExtDoubleAcc*(bld: BuilderRef, tuv: var ValueRef, a, b: ValueRef) =
#   ## (t, u, v) <- (t, u, v) + 2 * a * b
#   let ctx = bld.getContext()

#   let ty = a.getTypeOf()
#   let bits = ty.getIntTypeWidth()

#   let x3ty = tuv.getTypeOf()
#   let x3bits = x3ty.getIntTypeWidth()

#   doAssert bits * 3 == x3bits

#   let dbl = bits shl 1
#   let dblTy = ctx.int_t(dbl)

#   let a = bld.zext(a, dblTy, name = "macd0_")
#   let b = bld.zext(b, dblTy, name = "macd1_")
#   let ab = bld.mulNUW(a, b, name = "macd01_")

#   let wide_ab = bld.zext(ab, x3ty, name = "macd01x_")
#   let r1 = bld.addNUW(tuv, wide_ab, "macdpart_")
#   let r2 = bld.addNUW(r1, wide_ab, "macd_")

#   tuv = r2
