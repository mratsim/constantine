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

proc hi(bld: BuilderRef, val: ValueRef, baseTy: TypeRef, oversize: uint32, prefix: string): ValueRef =
  let ctx = bld.getContext()
  let bits = baseTy.getIntTypeWidth()
  let overTy = ctx.int_t(bits + oversize)

  # %hi_shift_1 = zext i8 64 to i128
  let s = constInt(ctx.int8_t(), oversize)
  let shift = bld.zext(s, overTy, name = cstring(prefix & "S_"))
  # %hiLarge_1 = lshr i128 %input, %hi_shift_1
  let hiLarge = bld.lshr(val, shift, name = cstring(prefix & "L_"))
  # %hi_1 = trunc i128 %hiLarge_1 to i64
  let hi = bld.trunc(hiLarge, baseTy, name = cstring(prefix & "_"))

  return hi

proc addcarry*(bld: BuilderRef, a, b, carryIn: ValueRef): tuple[carryOut, r: ValueRef] =
  ## (cOut, result) <- a+b+cIn
  let ty = a.getTypeOf()

  let add = bld.add(a, b, name = "adc01_")
  let carry0 = bld.icmp(kULT, add, b, name = "adc01c_")
  let cIn = bld.zext(carryIn, ty, name = "adc2_")
  let adc = bld.add(cIn, add, name = "adc_")
  let carry1 = bld.icmp(kULT, adc, add, name = "adc012c_")
  let carryOut = bld.`or`(carry0, carry1, name = "cOut_")

  return (carryOut, adc)

proc subborrow*(bld: BuilderRef, a, b, borrowIn: ValueRef): tuple[borrowOut, r: ValueRef] =
  ## (bOut, result) <- a-b-bIn
  let ty = a.getTypeOf()

  let sub = bld.sub(a, b, name = "sbb01_")
  let borrow0 = bld.icmp(kULT, a, b, name = "sbb01b_")
  let bIn = bld.zext(borrowIn, ty, name = "sbb2_")
  let sbb = bld.sub(sub, bIn, name = "sbb_")
  let borrow1 = bld.icmp(kULT, sub, bIn, name = "sbb012b_")
  let borrowOut = bld.`or`(borrow0, borrow1, name = "bOut_")

  return (borrowOut, sbb)

proc mulExt*(bld: BuilderRef, a, b: ValueRef): tuple[hi, lo: ValueRef] =
  ## Extended precision multiplication
  ## (hi, lo) <- a*b
  let ctx = bld.getContext()
  let ty = a.getTypeOf()
  let bits = ty.getIntTypeWidth()
  let dbl = bits shl 1
  let dblTy = ctx.int_t(dbl)

  let a = bld.zext(a, dblTy, name = "mulx0_")
  let b = bld.zext(b, dblTy, name = "mulx1_")
  let r = bld.mulNUW(a, b, name = "mulx_")

  let lo = bld.trunc(r, ty, name = "mullo_")
  let hi = bld.hi(r, ty, oversize = bits, prefix = "mulhi_")
  return (hi, lo)

proc smulExt*(bld: BuilderRef, a, b: ValueRef): tuple[hi, lo: ValueRef] =
  ## Signed extended precision multiplication
  ## (hi, lo) <- a*b
  let ctx = bld.getContext()
  let ty = a.getTypeOf()
  let bits = ty.getIntTypeWidth()
  let dbl = bits shl 1
  let dblTy = ctx.int_t(dbl)

  let a = bld.sext(a, dblTy, name = "smulx0_")
  let b = bld.sext(b, dblTy, name = "smulx1_")
  let r = bld.mulNSW(a, b, name = "smulx0_")

  let lo = bld.trunc(r, ty, name = "smullo_")
  let hi = bld.hi(r, ty, oversize = bits, prefix = "smulhi_")
  return (hi, lo)

proc muladd1*(bld: BuilderRef, a, b, c: ValueRef): tuple[hi, lo: ValueRef] =
  ## Extended precision multiplication + addition
  ## (hi, lo) <- a*b + c
  ##
  ## Note: 0xFFFFFFFF² -> (hi: 0xFFFFFFFE, lo: 0x00000001)
  ##       so adding any c cannot overflow
  let ctx = bld.getContext()
  let ty = a.getTypeOf()
  let bits = ty.getIntTypeWidth()
  let dbl = bits shl 1
  let dblTy = ctx.int_t(dbl)

  let a = bld.zext(a, dblTy, name = "fmax0_")
  let b = bld.zext(b, dblTy, name = "fmax1_")
  let ab = bld.mulNUW(a, b, name = "fmax01_")

  let c = bld.zext(c, dblTy, name = "fmax2_")
  let r = bld.addNUW(ab, c, name = "fmax_")

  let lo = bld.trunc(r, ty, name = "fmalo_")
  let hi = bld.hi(r, ty, oversize = bits, prefix = "fmahi_")
  return (hi, lo)

proc muladd2*(bld: BuilderRef, a, b, c1, c2: ValueRef): tuple[hi, lo: ValueRef] =
  ## Extended precision multiplication + addition + addition
  ## (hi, lo) <- a*b + c1 + c2
  ##
  ## Note: 0xFFFFFFFF² -> (hi: 0xFFFFFFFE, lo: 0x00000001)
  ##       so adding 0xFFFFFFFF leads to (hi: 0xFFFFFFFF, lo: 0x00000000)
  ##       and we have enough space to add again 0xFFFFFFFF without overflowing
  let ctx = bld.getContext()
  let ty = a.getTypeOf()
  let bits = ty.getIntTypeWidth()
  let dbl = bits shl 1
  let dblTy = ctx.int_t(dbl)

  let a = bld.zext(a, dblTy, name = "fmaa0_")
  let b = bld.zext(b, dblTy, name = "fmaa1_")
  let ab = bld.mulNUW(a, b, name = "fmaa01_")

  let c1 = bld.zext(c1, dblTy, name = "fmaa2_")
  let abc1 = bld.addNUW(ab, c1, name = "fmaa012_")
  let c2 = bld.zext(c2, dblTy, name = "fmaa3_")
  let r = bld.addNUW(abc1, c2, name = "fmaa_")

  let lo = bld.trunc(r, ty, name = "fmaalo_")
  let hi = bld.hi(r, ty, oversize = bits, prefix = "fmaahi_")
  return (hi, lo)

proc mulAcc*(bld: BuilderRef, tuv: var ValueRef, a, b: ValueRef) =
  ## (t, u, v) <- (t, u, v) + a * b
  let ctx = bld.getContext()

  let ty = a.getTypeOf()
  let bits = ty.getIntTypeWidth()

  let x3ty = tuv.getTypeOf()
  let x3bits = x3ty.getIntTypeWidth()

  doAssert bits * 3 == x3bits

  let dbl = bits shl 1
  let dblTy = ctx.int_t(dbl)

  let a = bld.zext(a, dblTy, name = "mac0_")
  let b = bld.zext(b, dblTy, name = "mac1_")
  let ab = bld.mulNUW(a, b, name = "mac01_")

  let wide_ab = bld.zext(ab, x3ty, name = "mac01x_")
  let r = bld.addNUW(tuv, wide_ab, "mac_")

  tuv = r

proc mulDoubleAcc*(bld: BuilderRef, tuv: var ValueRef, a, b: ValueRef) =
  ## (t, u, v) <- (t, u, v) + 2 * a * b
  let ctx = bld.getContext()

  let ty = a.getTypeOf()
  let bits = ty.getIntTypeWidth()

  let x3ty = tuv.getTypeOf()
  let x3bits = x3ty.getIntTypeWidth()

  doAssert bits * 3 == x3bits

  let dbl = bits shl 1
  let dblTy = ctx.int_t(dbl)

  let a = bld.zext(a, dblTy, name = "macd0_")
  let b = bld.zext(b, dblTy, name = "macd1_")
  let ab = bld.mulNUW(a, b, name = "macd01_")

  let wide_ab = bld.zext(ab, x3ty, name = "macd01x_")
  let r1 = bld.addNUW(tuv, wide_ab, "macdpart_")
  let r2 = bld.addNUW(r1, wide_ab, "macd_")

  tuv = r2
