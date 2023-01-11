# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  ../platforms/gpu/[llvm, nvidia, ir]

# ############################################################
#
#               Field arithmetic on Nvidia GPU
#
# ############################################################

# Loads from global (kernel params) take over 100 cycles
# https://docs.nvidia.com/cuda/parallel-thread-execution/index.html#operand-costs

proc finalSubMayOverflow*(asy: Assembler_LLVM, cm: CurveMetadata, field: Field, r, a: Array, N: uint32) =
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
  let scratch = bld.makeArray(fieldTy.ty)
  let M = cm.getModulus(field)

  # Contains 0x0001 (if overflowed limbs) or 0x0000
  let overflowedLimbs = bld.add_ci(0'u32, 0'u32)

  # Now substract the modulus, and test a < p with the last borrow
  for i in 0 ..< N:
    if i == 0:
      scratch[0] = bld.sub_co(a[0], M[0])
    else:
      scratch[i] = bld.sub_cio(a[i], M[i])

  # - If it underflows here a was smaller than the modulus
  #   Note: if limbs were overflowed, a is always smaller than the modulus
  # - If it overflowed the limbs or didn't underflow when modulus was substracted,
  #   we need to substract modulus
  let underflowedModulus = bld.sub_ci(overflowedLimbs, 0'u32)

  for i in 0 ..< N:
    r[i] = bld.slct(scratch[i], a[i], underflowedModulus) 

proc finalSubNoOverflow*(asy: Assembler_LLVM, cm: CurveMetadata, field: Field, r, a: Array, N: uint32) =
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
  let scratch = bld.makeArray(fieldTy.ty)
  let M = cm.getModulus(field)

  for i in 0 ..< N:
    if i == 0:
      scratch[0] = bld.sub_co(a[0], M[0])
    else:
      scratch[i] = bld.sub_cio(a[i], M[i])

  # If it underflows here a was smaller than the modulus
  let underflowedModulus = bld.sub_ci(0'u32, 0'u32)

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
  let pFieldTy = pointer_t(fieldTy.ty)

  let addModTy = function_t(asy.void_t, [pFieldTy, pFieldTy, pFieldTy])
  let addModKernel = asy.module.addFunction(cstring procName, addModTy)
  let blck = asy.ctx.appendBasicBlock(addModKernel, "addModBody")
  asy.builder.positionAtEnd(blck)

  let bld = asy.builder
  
  let r = bld.asArray(addModKernel.getParam(0), fieldTy.ty)
  let a = bld.asArray(addModKernel.getParam(1), fieldTy.ty)
  let b = bld.asArray(addModKernel.getParam(2), fieldTy.ty)

  let t = bld.makeArray(fieldTy.ty)
  let N = fieldTy.len
  for i in 0 ..< N:
    if i == 0:
      t[0] = bld.add_co(a[0], b[0]) 
    else:
      t[i] = bld.add_cio(a[i], b[i])

  if cm.getSpareBits(field) >= 1:
    asy.finalSubNoOverflow(cm, field, t, t, N)
  else:
    asy.finalSubMayOverflow(cm, field, t, t, N)

  bld.store(r, t)
  bld.retVoid()

  return (addModTy, addModKernel)
