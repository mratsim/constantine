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
  ./limbs_asm_modular_x86,
  ../../../platforms/abstractions

# ############################################################
#                                                            #
#        Assembly implementation of FpDbl                    #
#                                                            #
# ############################################################

# A FpDbl is a partially-reduced double-precision element of Fp
# The allowed range is [0, 2ⁿp)
# with n = w*WordBitWidth
# and w the number of words necessary to represent p on the machine.
# Concretely a 381-bit p needs 6*64 bits limbs (hence 384 bits total)
# and so FpDbl would 768 bits.

static: doAssert UseASM_X86_64
# Necessary for the compiler to find enough registers
{.localPassC:"-fomit-frame-pointer".}  # (enabled at -O1)

# Double-precision field addition
# ------------------------------------------------------------

macro addmod2x_gen[N: static int](r_PIR: var Limbs[N], a_MEM, b_MEM: Limbs[N], M_MEM: Limbs[N div 2], spareBits: static int): untyped =
  ## Generate an optimized out-of-place double-precision addition kernel

  result = newStmtList()

  var ctx = init(Assembler_x86, BaseType)
  let
    H = N div 2

    r = asmArray(r_PIR, N, PointerInReg, asmInputOutputEarlyClobber, memIndirect = memWrite) # MemOffsettable is the better constraint but compilers say it is impossible. Use early clobber to ensure it is not affected by constant propagation at slight pessimization (reloading it).
    b = asmArray(b_MEM, N, MemOffsettable, asmInput)
    # We could force m as immediate by specializing per moduli
    M = asmArray(M_MEM, H, MemOffsettable, asmInput)
    # If N is too big, we need to spill registers. TODO.
    uSym = ident"u"
    vSym = ident"v"
    u = asmArray(uSym, H, ElemsInReg, asmInputOutput)
    v = asmArray(vSym, H, ElemsInReg, asmInputOutput)

    overflowRegSym = ident"overflowReg"
    overflowReg = asmValue(overflowRegSym, Reg, asmOutputOverwrite)

  result.add quote do:
    var `uSym`{.noinit.}, `vSym` {.noInit.}: typeof(`a_MEM`)
    staticFor i, 0, `H`:
      `uSym`[i] = `a_MEM`[i]
    staticFor i, `H`, `N`:
      `vSym`[i-`H`] = `a_MEM`[i]

    when `sparebits` == 0:
      var `overflowRegSym`{.noInit.}: BaseType

  # Addition
  # u = a[0..<H] + b[0..<H], v = a[H..<N]
  ctx.add u[0], b[0]
  ctx.mov r[0], u[0]
  for i in 1 ..< H:
    ctx.adc u[i], b[i]
    ctx.mov r[i], u[i]

  # v = a[H..<N] + b[H..<N], a[0..<H] = u, u = v
  for i in H ..< N:
    ctx.adc v[i-H], b[i]
    ctx.mov u[i-H], v[i-H]

  let rUpperHalf = r.subset(H, N)

  if spareBits >= 1:
    # Now substract the modulus to test a < 2ⁿp
    ctx.finalSubNoOverflowImpl(rUpperHalf, v, M, u)
  else:
    ctx.finalSubMayOverflowImpl(rUpperHalf, v, M, u, scratchReg = overflowReg)

  result.add ctx.generate()

func addmod2x_asm*[N: static int](r: var Limbs[N], a, b: Limbs[N], M: Limbs[N div 2], spareBits: static int) =
  ## Constant-time double-precision addition
  ## Output is conditionally reduced by 2ⁿp
  ## to stay in the [0, 2ⁿp) range
  addmod2x_gen(r, a, b, M, spareBits)

# Double-precision field substraction
# ------------------------------------------------------------

macro submod2x_gen[N: static int](r_PIR: var Limbs[N], a_MEM, b_PIR: Limbs[N], M_MEM: Limbs[N div 2]): untyped =
  ## Generate an optimized out-of-place double-precision substraction kernel

  result = newStmtList()

  var ctx = init(Assembler_x86, BaseType)
  let
    H = N div 2

    r = asmArray(r_PIR, N, PointerInReg, asmInputOutputEarlyClobber, memIndirect = memWrite) # MemOffsettable is the better constraint but compilers say it is impossible. Use early clobber to ensure it is not affected by constant propagation at slight pessimization (reloading it).
    b = asmArray(b_PIR, N, PointerInReg, asmInputOutputEarlyClobber, memIndirect = memRead)  # We reuse the reg used for b for overflow detection
    # We could force m as immediate by specializing per moduli
    M = asmArray(M_MEM, H, MemOffsettable, asmInput)
    # If N is too big, we need to spill registers. TODO.
    uSym = ident"u"
    vSym = ident"v"
    u = asmArray(uSym, H, ElemsInReg, asmInputOutput)
    v = asmArray(vSym, H, ElemsInReg, asmInputOutput)

  result.add quote do:
    var `uSym`{.noinit.}, `vSym` {.noInit.}: typeof(`a_MEM`)
    staticFor i, 0, `H`:
      `uSym`[i] = `a_MEM`[i]
    staticFor i, `H`, `N`:
      `vSym`[i-`H`] = `a_MEM`[i]

  # Substraction
  # u = a[0..<H] - b[0..<H], v = a[H..<N]
  ctx.sub u[0], b[0]
  ctx.mov r[0], u[0]
  for i in 1 ..< H:
    ctx.sbb u[i], b[i]
    ctx.mov r[i], u[i]

  # v = a[H..<N] - b[H..<N], a[0..<H] = u, u = M
  for i in H ..< N:
    ctx.sbb v[i-H], b[i]
    ctx.mov u[i-H], M[i-H] # TODO, bottleneck 17% perf: prefetch or inline modulus?

  # Mask: underflowed contains 0xFFFF or 0x0000
  let underflowed = b.reuseRegister()
  ctx.sbb underflowed, underflowed

  # Now mask the adder, with 0 or the modulus limbs
  for i in 0 ..< H:
    ctx.`and` u[i], underflowed

  # Add the masked modulus
  ctx.add u[0], v[0]
  ctx.mov r[H], u[0]
  for i in 1 ..< H:
    ctx.adc u[i], v[i]
    ctx.mov r[i+H], u[i]

  result.add ctx.generate()

func submod2x_asm*[N: static int](r: var Limbs[N], a, b: Limbs[N], M: Limbs[N div 2]) =
  ## Constant-time double-precision substraction
  ## Output is conditionally reduced by 2ⁿp
  ## to stay in the [0, 2ⁿp) range
  submod2x_gen(r, a, b, M)

# Double-precision field negation
# ------------------------------------------------------------

macro negmod2x_gen[N: static int](r_PIR: var Limbs[N], a_MEM: Limbs[N], M_MEM: Limbs[N div 2]): untyped =
  ## Generate an optimized modular negation kernel

  result = newStmtList()

  var ctx = init(Assembler_x86, BaseType)
  let
    H = N div 2

    a = asmArray(a_MEM, N, MemOffsettable, asmInput)
    r = asmArray(r_PIR, N, PointerInReg, asmInputOutputEarlyClobber, memIndirect = memWrite) # MemOffsettable is the better constraint but compilers say it is impossible. Use early clobber to ensure it is not affected by constant propagation at slight pessimization (reloading it).
    uSym = ident"u"
    u = asmArray(uSym, N, ElemsInReg, asmOutputEarlyClobber)
    # We could force m as immediate by specializing per moduli
    # We reuse the reg used for m for overflow detection
    M = asmArray(M_MEM, N, MemOffsettable, asmInput)

    isZeroSym = ident"isZero"
    isZero = asmValue(isZeroSym, Reg, asmOutputEarlyClobber)

  result.add quote do:
    var `isZerosym`{.noInit.}: BaseType
    var `usym`{.noinit, used.}: typeof(`a_MEM`)

  # Substraction 2ⁿp - a
  # The lower half of 2ⁿp is filled with zero
  ctx.`xor` isZero, isZero
  for i in 0 ..< H:
    ctx.`xor` u[i], u[i]
    ctx.`or` isZero, a[i]

  for i in 0 ..< H:
    # 0 - a[i]
    if i == 0:
      ctx.sub u[0], a[0]
    else:
      ctx.sbb u[i], a[i]
    # store result, overwrite a[i] lower-half if aliasing.
    ctx.mov r[i], u[i]
    # Prepare second-half, u <- M
    ctx.mov u[i], M[i]

  for i in H ..< N:
    # u = 2ⁿp higher half
    ctx.sbb u[i-H], a[i]

  # Deal with a == 0,
  # we already accumulated 0 in the first half (which was destroyed if aliasing)
  for i in H ..< N:
    ctx.`or` isZero, a[i]

  # Zero result if a == 0, only the upper half needs to be zero-ed here
  for i in H ..< N:
    ctx.cmovz u[i-H], isZero
    ctx.mov r[i], u[i-H]

  result.add ctx.generate()

func negmod2x_asm*[N: static int](r: var Limbs[N], a: Limbs[N], M: Limbs[N div 2]) =
  ## Constant-time double-precision negation
  negmod2x_gen(r, a, M)
