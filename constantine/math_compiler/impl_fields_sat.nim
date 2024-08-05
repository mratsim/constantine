# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  constantine/platforms/llvm/[llvm, super_instructions],
  ./ir, ./codegen_nvidia

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
# It is suitable for:
# - ARM
# - AMD GPUs (for prototyping)
#
# The following backends have better optimizations through assembly:
# - x86: access to ADOX and ADCX interleaved double-carry chain
# - Nvidia: access to multiply accumulate instruction
#           and non-interleaved double-carry chain
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

proc finalSubMayOverflow*(asy: Assembler_LLVM, cm: CurveMetadata, field: Field, r, a: Array, carry: ValueRef) =
  ## If a >= Modulus: r <- a-M
  ## else:            r <- a
  ##
  ## This is constant-time straightline code.
  ## Due to warp divergence, the overhead of doing comparison with shortcutting might not be worth it on GPU.
  ##
  ## To be used when the final substraction can
  ## also overflow the limbs (a 2^256 order of magnitude modulus stored in n words of total max size 2^256)

  let bld = asy.builder
  let fieldTy = cm.getFieldType(field)
  let wordTy = cm.getWordType(field)
  let scratch = bld.makeArray(fieldTy)
  let M = cm.getModulus(field)
  let N = M.len

  let zero_i1 = constInt(asy.i1_t, 0)
  let zero = constInt(wordTy, 0)

  # Mask: contains 0xFFFF or 0x0000
  let (_, mask) = bld.subborrow(zero, zero, carry)

  # Now substract the modulus, and test a < M
  # (underflow) with the last borrow
  var b: ValueRef
  (b, scratch[0]) = bld.subborrow(a[0], M[0], zero_i1)
  for i in 1 ..< N:
    (b, scratch[i]) = bld.subborrow(a[i], M[i], b)

  # If it underflows here, it means that it was
  # smaller than the modulus and we don't need `scratch`
  (b, _) = bld.subborrow(mask, zero, b)

  for i in 0 ..< N:
    r[i] = bld.select(b, a[i], scratch[i])

proc finalSubNoOverflow*(asy: Assembler_LLVM, cm: CurveMetadata, field: Field, r, a: Array) =
  ## If a >= Modulus: r <- a-M
  ## else:            r <- a
  ##
  ## This is constant-time straightline code.
  ## Due to warp divergence, the overhead of doing comparison with shortcutting might not be worth it on GPU.
  ##
  ## To be used when the modulus does not use the full bitwidth of the storing words
  ## (say using 255 bits for the modulus out of 256 available in words)

  let bld = asy.builder
  let fieldTy = cm.getFieldType(field)
  let scratch = bld.makeArray(fieldTy)
  let M = cm.getModulus(field)
  let N = M.len

  # Now substract the modulus, and test a < M with the last borrow
  let zero_i1 = constInt(asy.i1_t, 0)
  var b: ValueRef
  (b, scratch[0]) = bld.subborrow(a[0], M[0], zero_i1)
  for i in 1 ..< N:
    (b, scratch[i]) = bld.subborrow(a[i], M[i], b)

  # If it underflows here a was smaller than the modulus, which is what we want
  for i in 0 ..< N:
    r[i] = bld.select(b, a[i], scratch[i])

proc field_add_gen_sat*(asy: Assembler_LLVM, cm: CurveMetadata, field: Field): FnDef =
  ## Generate an optimized modular addition kernel
  ## with parameters `a, b, modulus: Limbs -> Limbs`

  let procName = cm.genSymbol(block:
    case field
    of fp: opFpAdd
    of fr: opFrAdd)
  let fieldTy = cm.getFieldType(field)
  let pFieldTy = pointer_t(fieldTy)

  let addModTy = function_t(asy.void_t, [pFieldTy, pFieldTy, pFieldTy])
  let addModKernel = asy.module.addFunction(cstring procName, addModTy)
  let blck = asy.ctx.appendBasicBlock(addModKernel, "addModSatBody")
  asy.builder.positionAtEnd(blck)

  let bld = asy.builder

  let r = bld.asArray(addModKernel.getParam(0), fieldTy)
  let a = bld.asArray(addModKernel.getParam(1), fieldTy)
  let b = bld.asArray(addModKernel.getParam(2), fieldTy)

  let t = bld.makeArray(fieldTy)
  let N = cm.getNumWords(field)

  var c: ValueRef
  let zero = constInt(asy.i1_t, 0)

  (c, t[0]) = bld.addcarry(a[0], b[0], zero)
  for i in 1 ..< N:
    (c, t[i]) = bld.addcarry(a[i], b[i], c)

  if cm.getSpareBits(field) >= 1:
    asy.finalSubNoOverflow(cm, field, t, t)
  else:
    asy.finalSubMayOverflow(cm, field, t, t, c)

  bld.store(r, t)
  bld.retVoid()

  return (addModTy, addModKernel)
