# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  # Standard library
  std/macros,
  # Internal
  ../../config/common,
  ../../primitives

# ############################################################
#
#        Assembly implementation of FpDbl
#
# ############################################################

static: doAssert UseASM_X86_64
{.localPassC:"-fomit-frame-pointer".} # Needed so that the compiler finds enough registers

# TODO slower than intrinsics

# Substraction
# ------------------------------------------------------------

macro sub2x_gen[N: static int](a: var Limbs[N], b: Limbs[N], M: Limbs[N div 2]): untyped =
  ## Generate an optimized out-of-place double-width substraction kernel

  result = newStmtList()

  var ctx = init(Assembler_x86, BaseType)
  let
    N2 = N div 2

    arrA = init(OperandArray, nimSymbol = a, N, PointerInReg, InputOutput)
    # We reuse the reg used for B for overflow detection
    arrB = init(OperandArray, nimSymbol = b, N, PointerInReg, InputOutput)
    # We could force M as immediate by specializing per moduli
    arrM = init(OperandArray, nimSymbol = M, N, PointerInReg, Input)
    # If N is too big, we need to spill registers. TODO.
    arrT = init(OperandArray, nimSymbol = ident"t", N2, ElemsInReg, Output_EarlyClobber)
    arrTadd = init(OperandArray, nimSymbol = ident"tadd", N2, ElemsInReg, Output_EarlyClobber)

  # Fill the temporary workspace
  for i in 0 ..< N2:
    ctx.mov arrT[i], arrA[i]

  # Substraction
  ctx.sub arrT[0], arrB[0]
  ctx.mov arrA[0], arrT[0]

  for i in 1 ..< N2:
    ctx.sbb arrT[i], arrB[i]
    # Interleaved copies to hide SBB latencies
    ctx.mov arrT[i-1], arrA[i+N2-1]
    ctx.mov arrA[i], arrT[i]

  for i in N2 ..< N:
    ctx.sbb arrT[i-N2], arrB[i]
    # Copy the modulus
    ctx.mov arrTadd[i-N2], arrM[i-N2]
    if i == N2:
      # Leftover from previous loop
      ctx.mov arrT[N2-1], arrA[N-1]

  # Mask: underflowed contains 0xFFFF or 0x0000
  let underflowed = arrB.reuseRegister()
  ctx.sbb underflowed, underflowed

  # Now mask the adder, with 0 or the modulus limbs
  for i in 0 ..< N2:
    ctx.`and` arrTadd[i], underflowed

  # Add the masked modulus
  for i in 0 ..< N2:
    if i == 0:
      ctx.add arrT[0], arrTadd[0]
    else:
      ctx.adc arrT[i], arrTadd[i]
    ctx.mov arrA[i+N2], arrT[i]

  let t = arrT.nimSymbol
  let tadd = arrTadd.nimSymbol
  result.add quote do:
    var `t`{.noinit.}, `tadd` {.noInit.}: typeof(`a`)
  result.add ctx.generate

func sub2x_asm*[N: static int](a: var Limbs[N], b: Limbs[N], M: Limbs[N div 2]) =
  ## Constant-time double-width substraction
  sub2x_gen(a, b, M)
