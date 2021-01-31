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

macro sub2x_gen[N: static int](a: var Limbs[N], b: Limbs[N], m: Limbs[N div 2]): untyped =
  ## Generate an optimized out-of-place double-width substraction kernel

  result = newStmtList()

  var ctx = init(Assembler_x86, BaseType)
  let
    H = N div 2

    A = init(OperandArray, nimSymbol = a, N, PointerInReg, InputOutput)
    # We reuse the reg used for B for overflow detection
    B = init(OperandArray, nimSymbol = b, N, PointerInReg, InputOutput)
    # We could force m as immediate by specializing per moduli
    M = init(OperandArray, nimSymbol = m, N, PointerInReg, Input)
    # If N is too big, we need to spill registers. TODO.
    X = init(OperandArray, nimSymbol = ident"x", H, ElemsInReg, Output_EarlyClobber)
    Y = init(OperandArray, nimSymbol = ident"y", H, ElemsInReg, Output_EarlyClobber)

  # Fill the temporary workspace
  for i in 0 ..< H:
    ctx.mov X[i], A[i]

  # Substraction
  # X = A[0..<H] - B[0..<H], Y = A[H..<N]
  for i in 0 ..< H:
    if i == 0:
      ctx.sub X[0], B[0]
    else:
      ctx.sbb X[i], B[i]
    # Interleaved copies to hide SBB latencies
    ctx.mov Y[i], A[i+H]

  # Everything should be hot in cache now so movs are cheaper
  # we can try using 2 per SBB
  # Y = A[H..<N] - B[H..<N], A[0..<H] = X, X = M
  for i in H ..< N:
    ctx.mov A[i-H], X[i-H]
    ctx.sbb Y[i-H], B[i]
    ctx.mov X[i-H], M[i-H] # TODO, bottleneck 17% perf: prefetch or inline modulus?

  # Mask: underflowed contains 0xFFFF or 0x0000
  let underflowed = B.reuseRegister()
  ctx.sbb underflowed, underflowed

  # Now mask the adder, with 0 or the modulus limbs
  for i in 0 ..< H:
    ctx.`and` X[i], underflowed

  # Add the masked modulus
  for i in 0 ..< H:
    if i == 0:
      ctx.add X[0], Y[0]
    else:
      ctx.adc X[i], Y[i]
    ctx.mov A[i+H], X[i]

  let x = X.nimSymbol
  let y = Y.nimSymbol
  result.add quote do:
    var `x`{.noinit.}, `y` {.noInit.}: typeof(`a`)
  result.add ctx.generate

func sub2x_asm*[N: static int](a: var Limbs[N], b: Limbs[N], M: Limbs[N div 2]) =
  ## Constant-time double-width substraction
  sub2x_gen(a, b, M)
