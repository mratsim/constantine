# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  ../platforms/code_generator/[llvm, nvidia, ir]

# ############################################################
#
#               Field arithmetic on Nvidia GPU
#
# ############################################################

# Loads from global (kernel params) take over 100 cycles
# https://docs.nvidia.com/cuda/parallel-thread-execution/index.html#operand-costs

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
