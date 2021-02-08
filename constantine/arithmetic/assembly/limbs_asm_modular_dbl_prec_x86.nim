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
#                                                            #
#        Assembly implementation of FpDbl                    #
#                                                            #
# ############################################################

# A FpDbl is a partially-reduced double-precision element of Fp
# The allowed range is [0, 2ⁿp)
# with n = w*WordBitSize
# and w the number of words necessary to represent p on the machine.
# Concretely a 381-bit p needs 6*64 bits limbs (hence 384 bits total)
# and so FpDbl would 768 bits.

static: doAssert UseASM_X86_64
{.localPassC:"-fomit-frame-pointer".} # Needed so that the compiler finds enough registers

# Field addition
# ------------------------------------------------------------


macro addmod2x_gen[N: static int](R: var Limbs[N], A, B: Limbs[N], m: Limbs[N div 2]): untyped =
  ## Generate an optimized out-of-place double-precision addition kernel

  result = newStmtList()

  var ctx = init(Assembler_x86, BaseType)
  let
    H = N div 2

    r = init(OperandArray, nimSymbol = R, N, PointerInReg, InputOutput)
    # We reuse the reg used for b for overflow detection
    b = init(OperandArray, nimSymbol = B, N, PointerInReg, InputOutput)
    # We could force m as immediate by specializing per moduli
    M = init(OperandArray, nimSymbol = m, N, PointerInReg, Input)
    # If N is too big, we need to spill registers. TODO.
    u = init(OperandArray, nimSymbol = ident"U", H, ElemsInReg, InputOutput)
    v = init(OperandArray, nimSymbol = ident"V", H, ElemsInReg, InputOutput)

  let usym = u.nimSymbol
  let vsym = v.nimSymbol
  result.add quote do:
    var `usym`{.noinit.}, `vsym` {.noInit.}: typeof(`A`)
    staticFor i, 0, `H`:
      `usym`[i] = `A`[i]
    staticFor i, `H`, `N`:
      `vsym`[i-`H`] = `A`[i]

  # Addition
  # u = a[0..<H] + b[0..<H], v = a[H..<N]
  for i in 0 ..< H:
    if i == 0:
      ctx.add u[0], b[0]
    else:
      ctx.adc u[i], b[i]

  # Everything should be hot in cache now so movs are cheaper
  # we can try using 2 per ADC
  # v = a[H..<N] + b[H..<N], a[0..<H] = u, u = v
  for i in H ..< N:
    ctx.mov r[i-H], u[i-H]
    ctx.adc v[i-H], b[i]
    ctx.mov u[i-H], v[i-H]

  # Mask: overflowed contains 0xFFFF or 0x0000
  # TODO: unnecessary if MSB never set, i.e. "Field.getSpareBits >= 1"
  let overflowed = b.reuseRegister()
  ctx.sbb overflowed, overflowed

  # Now substract the modulus
  for i in 0 ..< H:
    if i == 0:
      ctx.sub v[0], M[0]
    else:
      ctx.sbb v[i], M[i]

  # If it overflows here, it means that it was
  # smaller than the modulus and we don't need v
  ctx.sbb overflowed, 0

  # Conditional Mov and
  # and store result
  for i in 0 ..< H:
    ctx.cmovnc u[i],  v[i]
    ctx.mov r[i], u[i]

  result.add ctx.generate

func addmod2x_asm*[N: static int](r: var Limbs[N], a, b: Limbs[N], M: Limbs[N div 2]) =
  ## Constant-time double-precision addition
  ## Output is conditionally reduced by 2ⁿp
  ## to stay in the [0, 2ⁿp) range
  addmod2x_gen(r, a, b, M)

# Field Substraction
# ------------------------------------------------------------

macro submod2x_gen[N: static int](R: var Limbs[N], A, B: Limbs[N], m: Limbs[N div 2]): untyped =
  ## Generate an optimized out-of-place double-precision substraction kernel

  result = newStmtList()

  var ctx = init(Assembler_x86, BaseType)
  let
    H = N div 2

    r = init(OperandArray, nimSymbol = R, N, PointerInReg, InputOutput)
    # We reuse the reg used for b for overflow detection
    b = init(OperandArray, nimSymbol = B, N, PointerInReg, InputOutput)
    # We could force m as immediate by specializing per moduli
    M = init(OperandArray, nimSymbol = m, N, PointerInReg, Input)
    # If N is too big, we need to spill registers. TODO.
    u = init(OperandArray, nimSymbol = ident"U", H, ElemsInReg, InputOutput)
    v = init(OperandArray, nimSymbol = ident"V", H, ElemsInReg, InputOutput)

  let usym = u.nimSymbol
  let vsym = v.nimSymbol
  result.add quote do:
    var `usym`{.noinit.}, `vsym` {.noInit.}: typeof(`A`)
    staticFor i, 0, `H`:
      `usym`[i] = `A`[i]
    staticFor i, `H`, `N`:
      `vsym`[i-`H`] = `A`[i]

  # Substraction
  # u = a[0..<H] - b[0..<H], v = a[H..<N]
  for i in 0 ..< H:
    if i == 0:
      ctx.sub u[0], b[0]
    else:
      ctx.sbb u[i], b[i]

  # Everything should be hot in cache now so movs are cheaper
  # we can try using 2 per SBB
  # v = a[H..<N] - b[H..<N], a[0..<H] = u, u = M
  for i in H ..< N:
    ctx.mov r[i-H], u[i-H]
    ctx.sbb v[i-H], b[i]
    ctx.mov u[i-H], M[i-H] # TODO, bottleneck 17% perf: prefetch or inline modulus?

  # Mask: underflowed contains 0xFFFF or 0x0000
  let underflowed = b.reuseRegister()
  ctx.sbb underflowed, underflowed

  # Now mask the adder, with 0 or the modulus limbs
  for i in 0 ..< H:
    ctx.`and` u[i], underflowed

  # Add the masked modulus
  for i in 0 ..< H:
    if i == 0:
      ctx.add u[0], v[0]
    else:
      ctx.adc u[i], v[i]
    ctx.mov r[i+H], u[i]

  result.add ctx.generate

func submod2x_asm*[N: static int](r: var Limbs[N], a, b: Limbs[N], M: Limbs[N div 2]) =
  ## Constant-time double-precision substraction
  ## Output is conditionally reduced by 2ⁿp
  ## to stay in the [0, 2ⁿp) range
  submod2x_gen(r, a, b, M)
