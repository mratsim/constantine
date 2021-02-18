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
#        Assembly implementation of finite fields
#
# ############################################################


static: doAssert UseASM_X86_32

# Necessary for the compiler to find enough registers (enabled at -O1)
{.localPassC:"-fomit-frame-pointer".}

proc finalSubNoCarry*(
       ctx: var Assembler_x86,
       r: Operand or OperandArray,
       a, M, scratch: OperandArray
     ) =
  ## Reduce `a` into `r` modulo `M`
  let N = M.len
  ctx.comment "Final substraction (no carry)"
  for i in 0 ..< N:
    ctx.mov scratch[i], a[i]
    if i == 0:
      ctx.sub scratch[i], M[i]
    else:
      ctx.sbb scratch[i], M[i]

  # If we borrowed it means that we were smaller than
  # the modulus and we don't need "scratch"
  for i in 0 ..< N:
    ctx.cmovnc a[i], scratch[i]
    ctx.mov r[i], a[i]

proc finalSubCanOverflow*(
       ctx: var Assembler_x86,
       r: Operand or OperandArray,
       a, M, scratch: OperandArray,
       overflowReg: Operand or Register
     ) =
  ## Reduce `a` into `r` modulo `M`
  ## To be used when the final substraction can
  ## also depend on the carry flag
  ## This is in particular possible when the MSB
  ## is set for the prime modulus
  ## `overflowReg` should be a register that will be used
  ## to store the carry flag

  ctx.sbb overflowReg, overflowReg

  let N = M.len
  ctx.comment "Final substraction (may carry)"
  for i in 0 ..< N:
    ctx.mov scratch[i], a[i]
    if i == 0:
      ctx.sub scratch[i], M[i]
    else:
      ctx.sbb scratch[i], M[i]

  ctx.sbb overflowReg, 0

  # If we borrowed it means that we were smaller than
  # the modulus and we don't need "scratch"
  for i in 0 ..< N:
    ctx.cmovnc a[i], scratch[i]
    ctx.mov r[i], a[i]


# Montgomery reduction
# ------------------------------------------------------------

macro montyRedc2x_gen*[N: static int](
       r_MR: var array[N, SecretWord],
       a_MR: array[N*2, SecretWord],
       M_MR: array[N, SecretWord],
       m0ninv_MR: BaseType,
       hasSpareBit: static bool
      ) =
  result = newStmtList()

  var ctx = init(Assembler_x86, BaseType)
  # On x86, compilers only let us use 15 out of 16 registers
  # RAX and RDX are defacto used due to the MUL instructions
  # so we store everything in scratchspaces restoring as needed
  let
    # We could force M as immediate by specializing per moduli
    M = init(OperandArray, nimSymbol = M_MR, N, PointerInReg, Input)
    # MUL requires RAX and RDX

  let uSlots = N+2
  let vSlots = max(N-2, 3)

  var # Scratchspaces
    u = init(OperandArray, nimSymbol = ident"U", uSlots, ElemsInReg, InputOutput_EnsureClobber)
    v = init(OperandArray, nimSymbol = ident"V", vSlots, ElemsInReg, InputOutput_EnsureClobber)

  # Prologue
  let usym = u.nimSymbol
  let vsym = v.nimSymbol
  result.add quote do:
    var `usym`{.noinit.}: Limbs[`uSlots`]
    var `vsym` {.noInit.}: Limbs[`vSlots`]
    `vsym`[0] = cast[SecretWord](`r_MR`[0].unsafeAddr)
    `vsym`[1] = cast[SecretWord](`a_MR`[0].unsafeAddr)
    `vsym`[2] = SecretWord(`m0ninv_MR`)

  let r_temp = v[0].asArrayAddr(len = N)
  let a = v[1].asArrayAddr(len = 2*N)
  let m0ninv = v[2]

  # Algorithm
  # ---------------------------------------------------------
  # for i in 0 .. n-1:
  #   hi <- 0
  #   m <- a[i] * m0ninv mod 2^w (i.e. simple multiplication)
  #   for j in 0 .. n-1:
  #     (hi, lo) <- a[i+j] + m * M[j] + hi
  #     a[i+j] <- lo
  #   a[i+n] += hi
  # for i in 0 .. n-1:
  #   r[i] = a[i+n]
  # if r >= M:
  #   r -= M

  # No register spilling handling
  doAssert N <= 6, "The Assembly-optimized montgomery multiplication requires at most 6 limbs."

  for i in 0 ..< N:
    ctx.mov u[i], a[i]

  ctx.mov u[N], u[0]
  ctx.imul u[0], m0ninv    # m <- a[i] * m0ninv mod 2^w
  ctx.mov rax, u[0]

  # scratch: [a[0] * m0, a[1], a[2], a[3], a[0]] for 4 limbs

  for i in 0 ..< N:
    ctx.comment ""
    let hi = u[N]
    let next = u[N+1]

    ctx.mul rdx, rax, M[0], rax
    ctx.add hi, rax # Guaranteed to be zero
    ctx.mov rax, u[0]
    ctx.adc hi, rdx

    for j in 1 ..< N-1:
      ctx.comment ""
      ctx.mul rdx, rax, M[j], rax
      ctx.add u[j], rax
      ctx.mov rax, u[0]
      ctx.adc rdx, 0
      ctx.add u[j], hi
      ctx.adc rdx, 0
      ctx.mov hi, rdx

    # Next load
    if i < N-1:
      ctx.comment ""
      ctx.mov next, u[1]
      ctx.imul u[1], m0ninv
      ctx.comment ""

    # Last limb
    ctx.comment ""
    ctx.mul rdx, rax, M[N-1], rax
    ctx.add u[N-1], rax
    ctx.mov rax, u[1] # Contains next * m0
    ctx.adc rdx, 0
    ctx.add u[N-1], hi
    ctx.adc rdx, 0
    ctx.mov hi, rdx

    u.rotateLeft()

  # Second part - Final substraction
  # ---------------------------------------------

  ctx.mov rdx, r_temp
  let r = rdx.asArrayAddr(len = N)

  # This does a[i+n] += hi
  # but in a separate carry chain, fused with the
  # copy "r[i] = a[i+n]"
  for i in 0 ..< N:
    if i == 0:
      ctx.add u[i], a[i+N]
    else:
      ctx.adc u[i], a[i+N]

  let t = repackRegisters(v, u[N], u[N+1])

  # v is invalidated
  if hasSpareBit:
    ctx.finalSubNoCarry(r, u, M, t)
  else:
    ctx.finalSubCanOverflow(r, u, M, t, rax)

  # Code generation
  result.add ctx.generate()

func montRed_asm*[N: static int](
       r: var array[N, SecretWord],
       a: array[N*2, SecretWord],
       M: array[N, SecretWord],
       m0ninv: BaseType,
       hasSpareBit: static bool
      ) =
  ## Constant-time Montgomery reduction
  static: doAssert UseASM_X86_64, "This requires x86-64."
  montyRedc2x_gen(r, a, M, m0ninv, hasSpareBit)
