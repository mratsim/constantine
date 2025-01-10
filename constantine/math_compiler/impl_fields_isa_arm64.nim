# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  constantine/platforms/llvm/llvm,
  ./ir

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

proc finalSubMayOverflow_arm64(asy: Assembler_LLVM, fd: FieldDescriptor, r, a, M: Array) =
  ## If a >= Modulus: r <- a-M
  ## else:            r <- a

  doAssert asy.backend in {bkArm64_MacOS}
  # We specialize this procedure
  # due to LLVM adding extra instructions (from 1, 2 to 33% or 66% more): https://github.com/mratsim/constantine/issues/357

  let N = fd.numWords
  let t = asy.makeArray(fd.fieldTy)

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
    let r = asy.asArray(rr, fd.fieldTy)
    let a = asy.asArray(aa, fd.fieldTy)
    let b = asy.asArray(bb, fd.fieldTy)
    let M = asy.asArray(MM, fd.fieldTy)
    let apb = asy.makeArray(fd.fieldTy)

    apb[0] = asy.br.arm64_add_co(a[0], b[0])
    for i in 1 ..< fd.numWords:
      apb[i] = asy.br.arm64_add_cio(a[i], b[i])

    asy.finalSubMayOverflow_arm64(fd, r, apb, M)

    asy.br.retVoid()

  asy.callFn(name, [r, a, b, M])

proc mtymul_sat_CIOS_sparebit_mulhi_arm64(asy: Assembler_LLVM, fd: FieldDescriptor, r, a, b, M: ValueRef, finalReduce: bool) =
  ## Generate an optimized modular multiplication kernel
  ## with parameters `a, b, modulus: Limbs -> Limbs`
  ##
  ## Specialization for ARM64
  ## While the computing instruction count is the same between generic and optimized assembly
  ## There are significantly more loads/stores and stack usage:
  ## On 6 limbs (CodeGenLevelDefault):
  ## -  64 bytes stack vs 368
  ## -   4 stp         vs  23
  ## -  10 ldp         vs  35
  ## -   6 ldr         vs  61
  ## -   6 str         vs  43
  ## -   6 mov         vs  24
  ## -  78 mul         vs  78
  ## -  72 umulh       vs  72
  ## -  17 adds        vs  17
  ## - 103 adcs        vs 103
  ## -  23 adc         vs  12
  ## -   6 cmn         vs   6
  ## -   0 cset        vs  11