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
  ../../../platforms/abstractions

# ############################################################
#
#        Assembly implementation of finite fields
#
# ############################################################

# Note: We can refer to at most 30 registers in inline assembly
#       and "InputOutput" registers count double
#       They are nice to let the compiler deals with mov
#       but too constraining so we move things ourselves.

static: doAssert UseASM_X86_32

# Necessary for the compiler to find enough registers
{.localPassC:"-fomit-frame-pointer".}  # (enabled at -O1)

proc finalSubNoOverflowImpl*(
       ctx: var Assembler_x86,
       r: Operand or OperandArray,
       a, M, scratch: OperandArray) =
  ## Reduce `a` into `r` modulo `M`
  ## To be used when the modulus does not use the full bitwidth of the storing words
  ## for example a 255-bit modulus in n words of total max size 2^256
  ##
  ## r, a, scratch, scratchReg are mutated
  ## M is read-only
  let N = M.len
  ctx.comment "Final substraction (cannot overflow its limbs)"

  # Substract the modulus, and test a < p with the last borrow
  ctx.mov scratch[0], a[0]
  ctx.sub scratch[0], M[0]
  for i in 1 ..< N:
    ctx.mov scratch[i], a[i]
    ctx.sbb scratch[i], M[i]

  # If we borrowed it means that we were smaller than
  # the modulus and we don't need "scratch"
  for i in 0 ..< N:
    ctx.cmovnc a[i], scratch[i]
    ctx.mov r[i], a[i]

proc finalSubMayOverflowImpl*(
       ctx: var Assembler_x86,
       r: Operand or OperandArray,
       a, M, scratch: OperandArray) =
  ## Reduce `a` into `r` modulo `M`
  ## To be used when the final substraction can
  ## also overflow the limbs (a 2^256 order of magnitude modulus stored in n words of total max size 2^256)
  ##
  ## r, a, scratch are mutated
  ## M is read-only
  ## This clobbers RAX
  let N = M.len
  ctx.comment "Final substraction (may carry)"

  # Mask: rax contains 0xFFFF or 0x0000
  ctx.sbb rax, rax

  # Now substract the modulus, and test a < p with the last borrow
  ctx.mov scratch[0], a[0]
  ctx.sub scratch[0], M[0]
  for i in 1 ..< N:
    ctx.mov scratch[i], a[i]
    ctx.sbb scratch[i], M[i]

  # If it overflows here, it means that it was
  # smaller than the modulus and we don't need `scratch`
  ctx.sbb rax, 0

  # If we borrowed it means that we were smaller than
  # the modulus and we don't need "scratch"
  for i in 0 ..< N:
    ctx.cmovnc a[i], scratch[i]
    ctx.mov r[i], a[i]

macro finalSub_gen*[N: static int](
       r_PIR: var Limbs[N],
       a_EIR: Limbs[N],
       M_PIR: Limbs[N],
       scratch_EIR: var Limbs[N],
       mayOverflow: static bool): untyped =
  ## Returns:
  ##   a-M if a > M
  ##   a otherwise
  ##
  ## - r_PIR is a pointer to the result array, mutated,
  ## - a_EIR is an array of registers, mutated,
  ## - M_PIR is a pointer to an array, read-only,
  ## - scratch_EIR is an array of registers, mutated
  ## - mayOverflow is set to true when the carry flag also needs to be read
  result = newStmtList()

  var ctx = init(Assembler_x86, BaseType)
  let
    r = asmArray(r_PIR, N, PointerInReg, UnmutatedPointerToWriteMem)
    # We reuse the reg used for b for overflow detection
    a = asmArray(a_EIR, N, ElemsInReg, InputOutput)
    # We could force m as immediate by specializing per moduli
    M = asmArray(M_PIR, N, PointerInReg, Input)
    t = asmArray(scratch_EIR, N, ElemsInReg, Output_EarlyClobber)

  if mayOverflow:
    ctx.finalSubMayOverflowImpl(r, a, M, t)
  else:
    ctx.finalSubNoOverflowImpl(r, a, M, t)

  result.add ctx.generate()

# Field addition
# ------------------------------------------------------------

macro addmod_gen[N: static int](r_PIR: var Limbs[N], a_PIR, b_PIR, M_PIR: Limbs[N], spareBits: static int): untyped =
  ## Generate an optimized modular addition kernel
  # Register pressure note:
  #   We could generate a kernel per modulus m by hardcoding it as immediate
  #   however this requires
  #     - duplicating the kernel and also
  #     - 64-bit immediate encoding is quite large

  result = newStmtList()

  var ctx = init(Assembler_x86, BaseType)
  let
    r = asmArray(r_PIR, N, PointerInReg, UnmutatedPointerToWriteMem)
    b = asmArray(b_PIR, N, PointerInReg, Input)
    # We could force m as immediate by specializing per moduli
    M = asmArray(M_PIR, N, PointerInReg, Input)
    # If N is too big, we need to spill registers. TODO.
    uSym = ident"u"
    vSym = ident"v"
    u = asmArray(uSym, N, ElemsInReg, InputOutput)
    v = asmArray(vSym, N, ElemsInReg, Output_EarlyClobber)

  result.add quote do:
    var `usym`{.noinit.}, `vsym` {.noInit, used.}: typeof(`a_PIR`)
    staticFor i, 0, `N`:
      `usym`[i] = `a_PIR`[i]

  # Addition
  ctx.add u[0], b[0]
  ctx.mov v[0], u[0]
  for i in 1 ..< N:
    ctx.adc u[i], b[i]
    # Interleaved copy in a second buffer as well
    ctx.mov v[i], u[i]

  if spareBits >= 1:
    ctx.finalSubNoOverflowImpl(r, u, M, v)
  else:
    ctx.finalSubMayOverflowImpl(r, u, M, v)

  result.add ctx.generate()

func addmod_asm*(r: var Limbs, a, b, m: Limbs, spareBits: static int) {.noInline.} =
  ## Constant-time modular addition
  # This MUST be noInline or Clang will run out of registers with LTO
  addmod_gen(r, a, b, m, spareBits)

# Field substraction
# ------------------------------------------------------------

macro submod_gen[N: static int](r_PIR: var Limbs[N], a_PIR, b_PIR, M_PIR: Limbs[N]): untyped =
  ## Generate an optimized modular addition kernel
  # Register pressure note:
  #   We could generate a kernel per modulus m by hardocing it as immediate
  #   however this requires
  #     - duplicating the kernel and also
  #     - 64-bit immediate encoding is quite large

  result = newStmtList()

  var ctx = init(Assembler_x86, BaseType)
  let
    r = asmArray(r_PIR, N, PointerInReg, UnmutatedPointerToWriteMem)
    b = asmArray(b_PIR, N, PointerInReg, InputOutput) # register reused for underflow detection
    # We could force m as immediate by specializing per moduli
    M = asmArray(M_PIR, N, PointerInReg, Input)
    # If N is too big, we need to spill registers. TODO.
    uSym = ident"u"
    vSym = ident"v"
    u = asmArray(uSym, N, ElemsInReg, InputOutput)
    v = asmArray(vSym, N, ElemsInReg, Output_EarlyClobber)

  result.add quote do:
    var `usym`{.noinit.}, `vsym` {.noInit, used.}: typeof(`a_PIR`)
    staticFor i, 0, `N`:
      `usym`[i] = `a_PIR`[i]

  # Substraction
  ctx.sub u[0], b[0]
  ctx.mov v[0], M[0]
  for i in 1 ..< N:
    ctx.sbb u[i], b[i]
    # Interleaved copy the modulus to hide SBB latencies
    ctx.mov v[i], M[i]

  # Mask: underflowed contains 0xFFFF or 0x0000
  let underflowed = b.reuseRegister()
  ctx.sbb underflowed, underflowed

  # Now mask the adder, with 0 or the modulus limbs
  for i in 0 ..< N:
    ctx.`and` v[i], underflowed

  # Add the masked modulus
  ctx.add u[0], v[0]
  ctx.mov r[0], u[0]
  for i in 1 ..< N:
    ctx.adc u[i], v[i]
    ctx.mov r[i], u[i]

  result.add ctx.generate()

func submod_asm*(r: var Limbs, a, b, M: Limbs) {.noInline.} =
  ## Constant-time modular substraction
  ## Warning, does not handle aliasing of a and b
  # This MUST be noInline or Clang will run out of registers with LTO
  submod_gen(r, a, b, M)

# Field negation
# ------------------------------------------------------------

macro negmod_gen[N: static int](r_PIR: var Limbs[N], a_PIR, M_PIR: Limbs[N]): untyped =
  ## Generate an optimized modular negation kernel

  result = newStmtList()

  var ctx = init(Assembler_x86, BaseType)
  let
    a = asmArray(a_PIR, N, PointerInReg, Input)
    r = asmArray(r_PIR, N, PointerInReg, UnmutatedPointerToWriteMem)
    uSym = ident"u"
    u = asmArray(uSym, N, ElemsInReg, Output_EarlyClobber)
    # We could force m as immediate by specializing per moduli
    # We reuse the reg used for m for overflow detection
    M = asmArray(M_PIR, N, PointerInReg, InputOutput)

  result.add quote do:
    var `usym`{.noinit, used.}: typeof(`a_PIR`)

  # Substraction m - a
  ctx.mov u[0], M[0]
  ctx.sub u[0], a[0]
  for i in 1 ..< N:
    ctx.mov u[i], M[i]
    ctx.sbb u[i], a[i]

  # Deal with a == 0
  let isZero = M.reuseRegister()
  ctx.mov isZero, a[0]
  for i in 1 ..< N:
    ctx.`or` isZero, a[i]

  # Zero result if a == 0
  for i in 0 ..< N:
    ctx.cmovz u[i], isZero
    ctx.mov r[i], u[i]

  result.add ctx.generate()

func negmod_asm*(r: var Limbs, a, m: Limbs) =
  ## Constant-time modular negation
  negmod_gen(r, a, m)
