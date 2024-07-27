# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  ../platforms/llvm/llvm,
  ./ir, ./codegen_nvidia

# ############################################################
#
#               Field arithmetic on Nvidia GPUs
#
# ############################################################

# Loads from global (kernel params) take over 100 cycles
# https://docs.nvidia.com/cuda/parallel-thread-execution/index.html#operand-costs

# Instructions cycle count:
# - Dissecting the NVIDIA Volta GPU Architecture via Microbenchmarking
#   Zhe Jia, Marco Maggioni, Benjamin Staiger, Daniele P. Scarpazza
#   https://arxiv.org/pdf/1804.06826.pdf
# - Demystifying the Nvidia Ampere Architecture through Microbenchmarking
#   and Instruction-level Analysis
#   https://arxiv.org/pdf/2208.11174.pdf
#
# Relevant discussion on mul.wide:
# https://forums.developer.nvidia.com/t/long-integer-multiplication-mul-wide-u64-and-mul-wide-u128
#
# Addition uses the integer ALU
# Fused multiply-add uses the float FMA unit
# hence by interleaving them we can benefit from Instruction Level Parallelism
#
# Also the float unit is likely more optimized, hence we want to maximize FMAs.
#
# Note: 64-bit FMA (IMAD) is as fast as 32-bit (FFMA) on A100
# but the carry codegen of madc.hi.cc.u64 has off-by-one
# - https://forums.developer.nvidia.com/t/incorrect-result-of-ptx-code/221067
# - old 32-bit bug: https://forums.developer.nvidia.com/t/wrong-result-returned-by-madc-hi-u64-ptx-instruction-for-specific-operands/196094

proc finalSubMayOverflow*(asy: Assembler_LLVM, cm: CurveMetadata, field: Field, r, a: Array) =
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
  let scratch = bld.makeArray(fieldTy)
  let M = cm.getModulus(field)
  let N = M.len

  # Contains 0x0001 (if overflowed limbs) or 0x0000
  let overflowedLimbs = bld.add_ci(0'u32, 0'u32)

  # Now substract the modulus, and test a < M with the last borrow
  scratch[0] = bld.sub_bo(a[0], M[0])
  for i in 1 ..< N:
    scratch[i] = bld.sub_bio(a[i], M[i])

  # 1. if `overflowedLimbs`, underflowedModulus >= 0
  # 2. if a >= M, underflowedModulus >= 0
  # if underflowedModulus >= 0: a-M else: a
  # TODO: predicated mov instead?
  let underflowedModulus = bld.sub_bi(overflowedLimbs, 0'u32)

  for i in 0 ..< N:
    r[i] = bld.slct(scratch[i], a[i], underflowedModulus)

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
  scratch[0] = bld.sub_bo(a[0], M[0])
  for i in 1 ..< N:
    scratch[i] = bld.sub_bio(a[i], M[i])

  # If it underflows here a was smaller than the modulus, which is what we want
  let underflowedModulus = bld.sub_bi(0'u32, 0'u32)

  for i in 0 ..< N:
    r[i] = bld.slct(scratch[i], a[i], underflowedModulus)

proc field_add_gen*(asy: Assembler_LLVM, cm: CurveMetadata, field: Field): FnDef =
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
  let blck = asy.ctx.appendBasicBlock(addModKernel, "addModBody")
  asy.builder.positionAtEnd(blck)

  let bld = asy.builder

  let r = bld.asArray(addModKernel.getParam(0), fieldTy)
  let a = bld.asArray(addModKernel.getParam(1), fieldTy)
  let b = bld.asArray(addModKernel.getParam(2), fieldTy)

  let t = bld.makeArray(fieldTy)
  let N = cm.getNumWords(field)

  t[0] = bld.add_co(a[0], b[0])
  for i in 1 ..< N:
    t[i] = bld.add_cio(a[i], b[i])

  if cm.getSpareBits(field) >= 1:
    asy.finalSubNoOverflow(cm, field, t, t)
  else:
    asy.finalSubMayOverflow(cm, field, t, t)

  bld.store(r, t)
  bld.retVoid()

  return (addModTy, addModKernel)

proc field_sub_gen*(asy: Assembler_LLVM, cm: CurveMetadata, field: Field): FnDef =
  ## Generate an optimized modular substraction kernel
  ## with parameters `a, b, modulus: Limbs -> Limbs`

  let procName = cm.genSymbol(block:
    case field
    of fp: opFpSub
    of fr: opFrSub)
  let fieldTy = cm.getFieldType(field)
  let pFieldTy = pointer_t(fieldTy)

  let subModTy = function_t(asy.void_t, [pFieldTy, pFieldTy, pFieldTy])
  let subModKernel = asy.module.addFunction(cstring procName, subModTy)
  let blck = asy.ctx.appendBasicBlock(subModKernel, "subModBody")
  asy.builder.positionAtEnd(blck)

  let bld = asy.builder

  let r = bld.asArray(subModKernel.getParam(0), fieldTy)
  let a = bld.asArray(subModKernel.getParam(1), fieldTy)
  let b = bld.asArray(subModKernel.getParam(2), fieldTy)

  let t = bld.makeArray(fieldTy)
  let N = cm.getNumWords(field)
  let zero = case cm.wordSize
             of size32: constInt(asy.i32_t, 0)
             of size64: constInt(asy.i64_t, 0)

  t[0] = bld.sub_bo(a[0], b[0])
  for i in 1 ..< N:
    t[i] = bld.sub_bio(a[i], b[i])

  let underflowMask = bld.sub_bi(zero, zero)

  # If underflow
  # TODO: predicated mov instead?
  let M = (seq[ValueRef])(cm.getModulus(field))
  let maskedM = bld.makeArray(fieldTy)
  for i in 0 ..< N:
    maskedM[i] = bld.`and`(M[i], underflowMask)

  block:
    t[0] = bld.add_co(t[0], maskedM[0])
  for i in 1 ..< N-1:
    t[i] = bld.add_cio(t[i], maskedM[i])
  if N > 1:
    t[N-1] = bld.add_ci(t[N-1], maskedM[N-1])

  bld.store(r, t)
  bld.retVoid()

  return (subModTy, subModKernel)

proc field_mul_CIOS_sparebit_gen(asy: Assembler_LLVM, cm: CurveMetadata, field: Field, lazyReduce: bool): FnDef =
  ## Generate an optimized modular multiplication kernel
  ## with parameters `a, b, modulus: Limbs -> Limbs`

  let procName = cm.genSymbol(block:
    if lazyReduce:
      case field
      of fp: opFpMulSkipFinalSub
      of fr: opFrMulSkipFinalSub
    else:
      case field
      of fp: opFpMul
      of fr: opFrMul)
  let fieldTy = cm.getFieldType(field)
  let pFieldTy = pointer_t(fieldTy)

  let mulModTy = function_t(asy.void_t, [pFieldTy, pFieldTy, pFieldTy])
  let mulModKernel = asy.module.addFunction(cstring procName, mulModTy)
  let blck = asy.ctx.appendBasicBlock(mulModKernel, "mulModBody")
  asy.builder.positionAtEnd(blck)

  let bld = asy.builder

  let r = bld.asArray(mulModKernel.getParam(0), fieldTy)
  let a = bld.asArray(mulModKernel.getParam(1), fieldTy)
  let b = bld.asArray(mulModKernel.getParam(2), fieldTy)

  # Algorithm
  # -----------------------------------------
  #
  # On x86, with a single carry chain and a spare bit:
  #
  # for i=0 to N-1
  #   (A, t[0]) <- a[0] * b[i] + t[0]
  #    m        <- (t[0] * m0ninv) mod 2ʷ
  #   (C, _)    <- m * M[0] + t[0]
  #   for j=1 to N-1
  #     (A, t[j])   <- a[j] * b[i] + A + t[j]
  #     (C, t[j-1]) <- m * M[j] + C + t[j]
  #
  #   t[N-1] = C + A
  #
  # with MULX, ADCX, ADOX dual carry chains
  #
  # for i=0 to N-1
  #   for j=0 to N-1
  # 		(A,t[j])  := t[j] + a[j]*b[i] + A
  #   m := t[0]*m0ninv mod W
  # 	C,_ := t[0] + m*M[0]
  # 	for j=1 to N-1
  # 		(C,t[j-1]) := t[j] + m*M[j] + C
  #   t[N-1] = C + A
  #
  # In our case, we only have a single carry flag
  # but we have a lot of registers
  # and a multiply-accumulate instruction
  #
  # Hence we can use the dual carry chain approach
  # one chain after the other instead of interleaved like on x86.

  let t = bld.makeArray(fieldTy)
  let N = cm.getNumWords(field)
  let m0ninv = ValueRef cm.getMontgomeryNegInverse0(field)
  let M = (seq[ValueRef])(cm.getModulus(field))
  let zero = case cm.wordSize
             of size32: constInt(asy.i32_t, 0)
             of size64: constInt(asy.i64_t, 0)

  for i in 0 ..< N:
    # Multiplication
    # -------------------------------
    #   for j=0 to N-1
    # 		(A,t[j])  := t[j] + a[j]*b[i] + A
    #
    # for 4 limbs, implicit column-wise carries
    #
    # t[0]     = t[0] + (a[0]*b[i]).lo
    # t[1]     = t[1] + (a[1]*b[i]).lo + (a[0]*b[i]).hi
    # t[2]     = t[2] + (a[2]*b[i]).lo + (a[1]*b[i]).hi
    # t[3]     = t[3] + (a[3]*b[i]).lo + (a[2]*b[i]).hi
    # overflow =                         (a[3]*b[i]).hi
    #
    # or
    #
    # t[0]     = t[0] + (a[0]*b[i]).lo
    # t[1]     = t[1] + (a[0]*b[i]).hi + (a[1]*b[i]).lo
    # t[2]     = t[2] + (a[2]*b[i]).lo + (a[1]*b[i]).hi
    # t[3]     = t[3] + (a[2]*b[i]).hi + (a[3]*b[i]).lo
    # overflow =    carry              + (a[3]*b[i]).hi
    #
    # Depending if we chain lo/hi or even/odd
    # The even/odd carry chain is more likely to be optimized via μops-fusion
    # as it's common to compute the full product. That said:
    # - it's annoying if the number of limbs is odd with edge conditions.
    # - GPUs are RISC architectures and unlikely to have clever instruction rescheduling logic
    let bi = b[i]
    var A = ValueRef zero

    if i == 0:
      for j in 0 ..< N:
        t[j] = bld.mul(a[j], bi)
    else:
      t[0] = bld.mulloadd_co(a[0], bi, t[0])
      for j in 1 ..< N:
        t[j] = bld.mulloadd_cio(a[j], bi, t[j])
      if N > 1:
        A = bld.add_ci(zero, zero)
    if N > 1:
      t[1] = bld.mulhiadd_co(a[0], bi, t[1])
    for j in 2 ..< N:
      t[j] = bld.mulhiadd_cio(a[j-1], bi, t[j])
    A = bld.mulhiadd_ci(a[N-1], bi, A)

    # Reduction
    # -------------------------------
    #   m := t[0]*m0ninv mod W
    #
    # 	C,_ := t[0] + m*M[0]
    # 	for j=1 to N-1
    # 		(C,t[j-1]) := t[j] + m*M[j] + C
    #   t[N-1] = C + A
    #
    # for 4 limbs, implicit column-wise carries
    #    _  = t[0] + (m*M[0]).lo
    #  t[0] = t[1] + (m*M[1]).lo + (m*M[0]).hi
    #  t[1] = t[2] + (m*M[2]).lo + (m*M[1]).hi
    #  t[2] = t[3] + (m*M[3]).lo + (m*M[2]).hi
    #  t[3] = A + carry          + (m*M[3]).hi
    #
    # or
    #
    #    _  = t[0] + (m*M[0]).lo
    #  t[0] = t[1] + (m*M[0]).hi + (m*M[1]).lo
    #  t[1] = t[2] + (m*M[2]).lo + (m*M[1]).hi
    #  t[2] = t[3] + (m*M[2]).hi + (m*M[3]).lo
    #  t[3] = A + carry          + (m*M[3]).hi

    let m = bld.mul(t[0], m0ninv)
    let _ = bld.mulloadd_co(m, M[0], t[0])
    for j in 1 ..< N:
      t[j-1] = bld.mulloadd_cio(m, M[j], t[j])
    t[N-1] = bld.add_ci(A, 0)
    if N > 1:
      t[0] = bld.mulhiadd_co(m, M[0], t[0])
      for j in 1 ..< N-1:
        t[j] = bld.mulhiadd_cio(m, M[j], t[j])
      t[N-1] = bld.mulhiadd_ci(m, M[N-1], t[N-1])
    else:
      t[0] = bld.mulhiadd(m, M[0], t[0])

  if not lazyReduce:
    asy.finalSubNoOverflow(cm, field, t, t)

  bld.store(r, t)
  bld.retVoid()

  return (mulModTy, mulModKernel)

proc field_mul_gen*(asy: Assembler_LLVM, cm: CurveMetadata, field: Field, lazyReduce = false): FnDef =
  ## Generate an optimized modular addition kernel
  ## with parameters `a, b, modulus: Limbs -> Limbs`
  return asy.field_mul_CIOS_sparebit_gen(cm, field, lazyReduce)
