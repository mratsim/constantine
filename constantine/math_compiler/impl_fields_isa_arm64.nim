# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  constantine/platforms/llvm/[llvm, super_instructions],
  ./ir,
  ./impl_fields_globals

import
  constantine/platforms/llvm/asm_arm64

# ############################################################
#
#             Field arithmetic with saturated limbs
#                  Specialization for ARM64
#
# ############################################################
#
# The codegen has extra useless instructions for FpAdd of P256, secp256k1, ...
# when the bit length is a multiple of the word size.
# Unfortunately that requires rewriting the full code in inline assembly
# as there is no way to specify a dependency on a "carry"
# without the compiler emitting a useless instruction to store it in register.
# And without that dependency, the compiler will optimize the code away.
#
# The tradeoff is that compiler might not inline constants.

const SectionName = "ctt,fields"

proc finalSubMayOverflow_arm64(asy: Assembler_LLVM, fd: FieldDescriptor, r: var Array, a, M: Array) =
  ## If a >= Modulus: r <- a-M
  ## else:            r <- a

  doAssert asy.backend in {bkArm64_MacOS}
  # We specialize this procedure
  # due to LLVM adding extra instructions (from 1, 2 to 33% or 66% more): https://github.com/mratsim/constantine/issues/357

  let N = fd.numWords
  var t = asy.makeArray(fd.fieldTy)

  # Contains 0x0001 (if overflowed limbs) or 0x0000
  let overflowedLimbs = asy.br.arm64_add_ci(0'u32, 0'u32)

  # Now substract the modulus, and test a < M with the last borrow
  t[0] = asy.br.arm64_sub_bo(a[0], M[0])
  for i in 1 ..< N:
    t[i] = asy.br.arm64_sub_bio(a[i], M[i])

  # 1. if `overflowedLimbs`, underflowedModulus >= 0
  # 2. if a >= M, underflowedModulus >= 0
  # if underflowedModulus >= 0: a-M else: a
  let underflowedModulus {.used.} = asy.br.arm64_sub_bi(overflowedLimbs, 0'u32)

  for i in 0 ..< N:
    r[i] = asy.br.arm64_csel_cc(a[i], t[i])

proc finalSubNoOverflow(asy: Assembler_LLVM, fd: FieldDescriptor, r: var Array, a, M: Array) =
  ## If a >= Modulus: r <- a-M
  ## else:            r <- a
  ##
  ## This is constant-time straightline code.
  ## Due to warp divergence, the overhead of doing comparison with shortcutting might not be worth it on GPU.
  ##
  ## To be used when the modulus does not use the full bitwidth of the storing words
  ## (say using 255 bits for the modulus out of 256 available in words)

  # We use word-level arithmetic instead of llvm_sub_overflow.u256 or llvm_sub_overflow.u384
  # due to LLVM adding extra instructions (from 1, 2 to 33% or 66% more): https://github.com/mratsim/constantine/issues/357

  var t = asy.makeArray(fd.fieldTy)

  # Now substract the modulus, and test a < M
  # (underflow) with the last borrow
  var B = fd.zero_i1
  for i in 0 ..< fd.numWords:
    (B, t[i]) = asy.br.subborrow(a[i], M[i], B)

  # If it underflows here, it means that it was
  # smaller than the modulus and we don't need `a-M`
  for i in 0 ..< fd.numWords:
    t[i] = asy.br.select(B, a[i], t[i])
  asy.store(r, t)

proc modadd_sat_fullbits_arm64*(asy: Assembler_LLVM, fd: FieldDescriptor, r, a, b, M: ValueRef) =
  ## Generate an optimized modular addition kernel
  ## with parameters `a, b, modulus: Limbs -> Limbs`
  ## Specialization for ARM64 in full assembly (may prevent inlining of modulus)
  doAssert asy.backend in {bkArm64_MacOS} and fd.spareBits == 0

  let name = "_modadd_mayo" & ".u" & $fd.w & "x" & $fd.numWords
  asy.llvmInternalFnDef(
          name, SectionName,
          asy.void_t, toTypes([r, a, b, M]),
          {kHot}):

    tagParameter(1, "sret")

    let (rr, aa, bb, MM) = llvmParams

    # Pointers are opaque in LLVM now
    var r = asy.asArray(rr, fd.fieldTy)
    let a = asy.asArray(aa, fd.fieldTy)
    let b = asy.asArray(bb, fd.fieldTy)
    let M = asy.asArray(MM, fd.fieldTy)
    var apb = asy.makeArray(fd.fieldTy)

    apb[0] = asy.br.arm64_add_co(a[0], b[0])
    for i in 1 ..< fd.numWords:
      apb[i] = asy.br.arm64_add_cio(a[i], b[i])

    asy.finalSubMayOverflow_arm64(fd, r, apb, M)

    asy.br.retVoid()

  asy.callFn(name, [r, a, b, M])

# template mulloadd_co(ctx, lhs, rhs, addend): ValueRef =
#   let t = ctx.mul(lhs, rhs)
#   ctx.arm64_add_co(addend, t)
# template mulloadd_cio(ctx, lhs, rhs, addend): ValueRef =
#   let t = ctx.mul(lhs, rhs)
#   ctx.arm64_add_cio(addend, t)

# template mulhiadd_co(ctx, lhs, rhs, addend): ValueRef =
#   let t = ctx.mulhi(lhs, rhs)
#   ctx.arm64_add_co(addend, t)
# template mulhiadd_cio(ctx, lhs, rhs, addend): ValueRef =
#   let t = ctx.mulhi(lhs, rhs)
#   ctx.arm64_add_cio(addend, t)
# template mulhiadd_ci(ctx, lhs, rhs, addend): ValueRef =
#   let t = ctx.mulhi(lhs, rhs)
#   ctx.arm64_add_ci(addend, t)

# proc mtymul_sat_CIOS_sparebit_arm64*(asy: Assembler_LLVM, fd: FieldDescriptor, r, a, b, M: ValueRef, finalReduce: bool) =
#   ## Generate an optimized modular multiplication kernel
#   ## with parameters `a, b, modulus: Limbs -> Limbs`
#   ##
#   ## Specialization for ARM64
#   ## While the computing instruction count is the same between generic and optimized assembly
#   ## There are significantly more loads/stores and stack usage:
#   ## On 6 limbs (CodeGenLevelDefault):
#   ## -  64 bytes stack vs 368
#   ## -   4 stp         vs  23
#   ## -  10 ldp         vs  35
#   ## -   6 ldr         vs  61
#   ## -   6 str         vs  43
#   ## -   6 mov         vs  24
#   ## -  78 mul         vs  78
#   ## -  72 umulh       vs  72
#   ## -  17 adds        vs  17
#   ## - 103 adcs        vs 103
#   ## -  23 adc         vs  12
#   ## -   6 cmn         vs   6
#   ## -   0 cset        vs  11

#   let name =
#     if not finalReduce and fd.spareBits >= 2:
#       "_mty_mulur.u" & $fd.w & "x" & $fd.numWords & "b2"
#     else:
#       doAssert fd.spareBits >= 1
#       "_mty_mul.u" & $fd.w & "x" & $fd.numWords & "b1"

#   asy.llvmInternalFnDef(
#           name, SectionName,
#           asy.void_t, toTypes([r, a, b, M]) & fd.wordTy,
#           {kHot}):

#     tagParameter(1, "sret")

#     let (rr, aa, bb, MM, m0ninv) = llvmParams

#     # Pointers are opaque in LLVM now
#     let r = asy.asArray(rr, fd.fieldTy)
#     let b = asy.asArray(bb, fd.fieldTy)

#     # Explicitly allocate on the stack
#     # the local variable.
#     # Unfortunately despite optimization passes
#     # stack usage is 5.75 than manual register allocation otherwise
#     # so we help the compiler with register lifetimes
#     # and imitate C local variable declaration/allocation
#     let a = asy.toLocalArray(aa, fd.fieldTy, "a")
#     let M = asy.toLocalArray(MM, fd.fieldTy, "M")
#     let t = asy.makeArray(fd.fieldTy, "t")
#     let N = fd.numWords

#     let A = asy.localVar(fd.wordTy, "A")
#     let bi = asy.localVar(fd.wordTy, "bi")

#     doAssert N >= 2
#     for i in 0 ..< N:
#       # Multiplication
#       # -------------------------------
#       #   for j=0 to N-1
#       # 		(A,t[j])  := t[j] + a[j]*b[i] + A
#       bi[] = b[i]
#       A[] = fd.zero
#       if i == 0:
#         for j in 0 ..< N:
#           t[j] = asy.br.mul(a[j], bi[])
#       else:
#         t[0] = asy.br.mulloadd_co(a[0], bi[], t[0])
#         for j in 1 ..< N:
#           t[j] = asy.br.mulloadd_cio(a[j], bi[], t[j])
#         A[] = asy.br.arm64_cset_cs()

#       t[1] = asy.br.mulhiadd_co(a[0], bi[], t[1])
#       for j in 2 ..< N:
#         t[j] = asy.br.mulhiadd_cio(a[j-1], bi[], t[j])
#       A[] = asy.br.mulhiadd_ci(a[N-1], bi[], A[])

#       # Reduction
#       # -------------------------------
#       #   m := t[0]*m0ninv mod W
#       #
#       # 	C,_ := t[0] + m*M[0]
#       # 	for j=1 to N-1
#       # 		(C,t[j-1]) := t[j] + m*M[j] + C
#       #   t[N-1] = C + A
#       let m = asy.br.mul(t[0], m0ninv)
#       let u = asy.br.mul(m, M[0])
#       discard asy.br.arm64_cmn(t[0], u)
#       for j in 1 ..< N:
#         t[j-1] = asy.br.mulloadd_cio(m, M[j], t[j])
#       t[N-1] = asy.br.arm64_add_ci(A[], fd.zero)

#       t[0] = asy.br.mulhiadd_co(m, M[0], t[0])
#       for j in 1 ..< N-1:
#         t[j] = asy.br.mulhiadd_cio(m, M[j], t[j])
#       t[N-1] = asy.br.mulhiadd_ci(m, M[N-1], t[N-1])

#       if finalReduce:
#         asy.finalSubNoOverflow(fd, t, t, M)

#     asy.store(r, t)
#     asy.br.retVoid()

#   let m0ninv = asy.getM0ninv(fd)
#   asy.callFn(name, [r, a, b, M, m0ninv])