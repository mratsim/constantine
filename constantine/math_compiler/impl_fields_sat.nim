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

# ############################################################
#
#             Field arithmetic with saturated limbs
#
# ############################################################
#
# This implements field operations in pure LLVM
# using saturated limbs, i.e. 64-bit words on 64-bit platforms.
#
# This relies on hardware addition-with-carry and substraction-with-borrow
# for efficiency.
#
# As such it is not suitable for platforms with no carry flags such as:
# - WASM
# - MIPS
# - RISC-V
# - Metal
#
# It may be suitable for Intel GPUs as the virtual ISA does support add-carry
#
# It is (theoretically) suitable for:
# - ARM
# - AMD GPUs
#
# The following backends have better optimizations through assembly:
# - x86: access to ADOX and ADCX interleaved double-carry chain
# - Nvidia: access to multiply accumulate instruction
#           and non-interleaved double-carry chain
#
# Hardware limitations
# --------------------
#
# AMD GPUs may benefits from using 24-bit limbs
# - https://www.amd.com/content/dam/amd/en/documents/radeon-tech-docs/programmer-references/AMD_OpenCL_Programming_Optimization_Guide2.pdf
#   p2-23:
#  Generally, the throughput and latency for 32-bit integer operations is the same
#  as for single-precision floating point operations.
#  24-bit integer MULs and MADs have four times the throughput of 32-bit integer
#  multiplies. 24-bit signed and unsigned integers are natively supported on the
#  GCN family of devices. The use of OpenCL built-in functions for mul24 and mad24
#  is encouraged. Note that mul24 can be useful for array indexing operations
#  Doc from 2015, it might not apply to RDNA family
# - https://free.eol.cn/edu_net/edudown/AMDppt/OpenCL%20Programming%20and%20Optimization%20-%20Part%20I.pdf
#   slide 24
#
# - https://chipsandcheese.com/2023/01/07/microbenchmarking-amds-rdna-3-graphics-architecture/
#   "Since Turing, Nvidia also achieves very good integer multiplication performance.
#    Integer multiplication appears to be extremely rare in shader code,
#    and AMD doesn’t seem to have optimized for it.
#    32-bit integer multiplication executes at around a quarter of FP32 rate,
#    and latency is pretty high too."
#
# Software limitations
# --------------------
#
# Unfortunately implementing unrolled using word size is fraught with perils
# for add-carry / sub-borrow
# AMDGPU crash: https://github.com/llvm/llvm-project/issues/102058
# ARM64 missed optim: https://github.com/llvm/llvm-project/issues/102062
#
# and while using @llvm.usub.with.overflow.i64 allows ARM64 to solve the missing optimization
# it is also missed on AMDGPU (or nvidia)
#
# And implementing them with i256 / i384 is similarly tricky
# https://github.com/llvm/llvm-project/issues/102868

const SectionName = "ctt,fields"

proc finalSubMayOverflow*(asy: Assembler_LLVM, fd: FieldDescriptor, r, a, M: Array, carry: ValueRef) =
  ## If a >= Modulus: r <- a-M
  ## else:            r <- a
  ##
  ## This is constant-time straightline code.
  ## Due to warp divergence, the overhead of doing comparison with shortcutting might not be worth it on GPU.
  ##
  ## To be used when the final substraction can
  ## also overflow the limbs (a 2^256 order of magnitude modulus stored in n words of total max size 2^256)

  # We use word-level arithmetic instead of llvm_sub_overflow.u256 or llvm_sub_overflow.u384
  # due to LLVM adding extra instructions (from 1, 2 to 33% or 66% more): https://github.com/mratsim/constantine/issues/357

  let t = asy.makeArray(fd.fieldTy)

  # Contains 0x0001 (if overflowed limbs) or 0x0000
  let (_, overflowedLimbs) = asy.br.addcarry(fd.zero, fd.zero, carry)

  # Now substract the modulus, and test a < M
  # (underflow) with the last borrow
  var B = fd.zero_i1
  for i in 0 ..< fd.numWords:
    (B, t[i]) = asy.br.subborrow(a[i], M[i], B)

  # 1. if `overflowedLimbs`, underflowedModulus >= 0
  # 2. if a >= M, underflowedModulus >= 0
  # if underflowedModulus >= 0: a-M else: a
  # This generates extra instructions whether the arch uses sub-with-borrow (x86-64) or sub-with-carry (ARM64)
  # and there doesn't seem to be a way around it
  let (underflowed, _) = asy.br.subborrow(overflowedLimbs, fd.zero, B)

  for i in 0 ..< fd.numWords:
     t[i] = asy.br.select(underflowed, t[i], a[i])

  asy.store(r, t)

proc finalSubNoOverflow*(asy: Assembler_LLVM, fd: FieldDescriptor, r, a, M: Array) =
  ## If a >= Modulus: r <- a-M
  ## else:            r <- a
  ##
  ## This is constant-time straightline code.
  ## Due to warp divergence, the overhead of doing comparison with shortcutting might not be worth it on GPU.
  ##
  ## To be used when the modulus does not use the full bitwidth of the storing words
  ## (say using 255 bits for the modulus out of 256 available in words)
  let t = asy.makeArray(fd.fieldTy)

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

proc modadd_sat(asy: Assembler_LLVM, fd: FieldDescriptor, r, a, b, M: ValueRef) {.used.} =
  ## Generate an optimized modular addition kernel
  ## with parameters `a, b, modulus: Limbs -> Limbs`

  let red = if fd.spareBits >= 1: "noo"
            else: "mayo"
  let name = "_modadd_" & red & ".u" & $fd.w & "x" & $fd.numWords
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

    var C = fd.zero_i1
    for i in 1 ..< fd.numWords:
      (C, apb[i]) = asy.br.addcarry(a[i], b[i], C)

    if fd.spareBits >= 1:
      asy.finalSubNoOverflow(fd, r, apb, M)
    else:
      asy.finalSubMayOverflow(fd, r, apb, M, C)

    asy.br.retVoid()

  asy.callFn(name, [r, a, b, M])

proc modsub_sat(asy: Assembler_LLVM, fd: FieldDescriptor, r, a, b, M: ValueRef) {.used.} =
  ## Generate an optimized modular subtraction kernel
  ## with parameters `a, b, modulus: Limbs -> Limbs`

  let red = if fd.spareBits >= 1: "noo"
            else: "mayo"
  let name = "_modadd_" & red & ".u" & $fd.w & "x" & $fd.numWords
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

    var B = fd.zero_i1
    for i in 0 ..< fd.numWords:
      (B, apb[i]) = asy.br.subborrow(a[i], b[i], B)

    let (_, underflowMask) = asy.br.subborrow(fd.zero, fd.zero, B)

    # Now mask the adder, with 0 or the modulus limbs
    let t = asy.makeArray(fd.fieldTy)
    for i in 0 ..< fd.numWords:
      let maskedMi = asy.br.`and`(M[i], underflowMask)
      t[i] = asy.br.add(apb[i], maskedMi)

    asy.store(r, t)
    asy.br.retVoid()

  asy.callFn(name, [r, a, b, M])

proc mtymul_sat_CIOS_sparebit_mulhi(asy: Assembler_LLVM, fd: FieldDescriptor, r, a, b, M: ValueRef, finalReduce: bool) =
  ## Generate an optimized modular multiplication kernel
  ## with parameters `a, b, modulus: Limbs -> Limbs`
  ## on architectures:
  ## - that support "mul" and "mulhi" separate instructions
  ## - for which multiplication doesn't interfere with the addition carry flag
  ##
  ## This is the case for:
  ## - ARM64
  ## - Nvidia
  ## - x86 SIMD
  ##
  ## ARM32 and x86_64 supports extended multiplication instead

  let name =
    if not finalReduce and fd.spareBits >= 2:
      "_mty_mulur.u" & $fd.w & "x" & $fd.numWords & "b2"
    else:
      doAssert fd.spareBits >= 1
      "_mty_mul.u" & $fd.w & "x" & $fd.numWords & "b1"

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

    let t = asy.makeArray(fd.fieldTy)
    let N = fd.numWords
    let m0ninv = asy.getM0ninv(fd)

    doAssert N >= 2
    for i in 0 ..< N:
      # Multiplication
      # -------------------------------
      #   for j=0 to N-1
      # 		(A,t[j])  := t[j] + a[j]*b[i] + A
      let bi = b[i]
      var A = fd.zero
      if i == 0:
        for j in 0 ..< N:
          t[j] = asy.br.mul(a[j], bi)
      else:
        var C = fd.zero_i1
        for j in 0 ..< N:
          (C, t[j]) = asy.br.mullo_adc(a[j], bi, t[j], C)
        (_, A) = asy.br.addcarry(fd.zero, fd.zero, C)

      block:
        var C = fd.zero_i1
        for j in 1 ..< N:
          (C, t[j]) = asy.br.mulhi_adc(a[j-1], bi, t[j], C)
        (_, A) = asy.br.mulhi_adc(a[N-1], bi, A, C)

      # Reduction
      # -------------------------------
      #   m := t[0]*m0ninv mod W
      #
      # 	C,_ := t[0] + m*M[0]
      # 	for j=1 to N-1
      # 		(C,t[j-1]) := t[j] + m*M[j] + C
      #   t[N-1] = C + A
      let m = asy.br.mul(t[0], m0ninv)
      var (C, _) = asy.br.mullo_adc(m, M[0], t[0], fd.zero_i1)
      for j in 1 ..< N:
        (C, t[j-1]) = asy.br.mullo_adc(m, M[j], t[j], C)
      (_, t[N-1]) = asy.br.addcarry(A, fd.zero, C)

      C = fd.zero_i1
      for j in 0 ..< N:
        (C, t[j]) = asy.br.mulhi_adc(m, M[j], t[j], C)

    if finalReduce:
      asy.finalSubNoOverflow(fd, t, t, M)

    asy.store(r, t)
    asy.br.retVoid()

  asy.callFn(name, [r, a, b, M])

proc mtymul_sat_mulhi(asy: Assembler_LLVM, fd: FieldDescriptor, r, a, b, M: ValueRef, finalReduce = true) {.used.} =
  ## Generate an optimized modular multiplication kernel
  ## with parameters `a, b, modulus: Limbs -> Limbs`

  # TODO: spareBits == 0
  asy.mtymul_sat_CIOS_sparebit_mulhi(fd, r, a, b, M, finalReduce)
