# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  constantine/platforms/llvm/[llvm, super_instructions],
  ./ir

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

const SectionName = "ctt.fields"

proc finalSubMayOverflow*(asy: Assembler_LLVM, fd: FieldDescriptor, rr, a, M, carry: ValueRef) =
  ## If a >= Modulus: r <- a-M
  ## else:            r <- a
  ##
  ## This is constant-time straightline code.
  ## Due to warp divergence, the overhead of doing comparison with shortcutting might not be worth it on GPU.
  ##
  ## To be used when the final substraction can
  ## also overflow the limbs (a 2^256 order of magnitude modulus stored in n words of total max size 2^256)

  # Mask: contains 0xFFFF or 0x0000
  let (_, mask) = asy.br.subborrow(fd.zero, fd.zero, carry)

  # Now substract the modulus, and test a < M
  # (underflow) with the last borrow
  let (borrow, a_minus_M) = asy.br.llvm_sub_overflow(a, M)

  # If it underflows here, it means that it was
  # smaller than the modulus and we don't need `a-M`
  let (ctl, _) = asy.br.subborrow(mask, fd.zero, borrow)

  let t = asy.br.select(ctl, a, a_minus_M)
  asy.store(rr, t)

proc finalSubNoOverflow*(asy: Assembler_LLVM, fd: FieldDescriptor, rr, a, M: ValueRef) =
  ## If a >= Modulus: r <- a-M
  ## else:            r <- a
  ##
  ## This is constant-time straightline code.
  ## Due to warp divergence, the overhead of doing comparison with shortcutting might not be worth it on GPU.
  ##
  ## To be used when the modulus does not use the full bitwidth of the storing words
  ## (say using 255 bits for the modulus out of 256 available in words)

  # Now substract the modulus, and test a < M
  # (underflow) with the last borrow
  let (borrow, a_minus_M) = asy.br.llvm_sub_overflow(a, M)

  # If it underflows here, it means that it was
  # smaller than the modulus and we don't need `a-M`
  let t = asy.br.select(borrow, a, a_minus_M)
  asy.store(rr, t)

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
    let a = asy.load2(fd.intBufTy, aa, "a")
    let b = asy.load2(fd.intBufTy, bb, "b")
    let M = asy.load2(fd.intBufTy, MM, "M")

    let (carry, apb) = asy.br.llvm_add_overflow(a, b)
    if fd.spareBits >= 1:
      asy.finalSubNoOverflow(fd, rr, apb, M)
    else:
      asy.finalSubMayOverflow(fd, rr, apb, M, carry)

    asy.br.retVoid()

  asy.callFn(name, [r, a, b, M])
