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
  ../../../platforms/abstractions,
  ./limbs_asm_modular_x86

# ############################################################
#
#        Assembly implementation of finite fields
#
# ############################################################


static: doAssert UseASM_X86_32

# Necessary for the compiler to find enough registers
{.localPassC:"-fomit-frame-pointer".}  # (enabled at -O1)

# Montgomery reduction
# ------------------------------------------------------------

macro redc2xMont_gen*[N: static int](
       r_PIR: var array[N, SecretWord],
       a_PIR: array[N*2, SecretWord],
       M_MEM: array[N, SecretWord],
       m0ninv_REG: BaseType,
       spareBits: static int, skipFinalSub: static bool) =
  # No register spilling handling
  doAssert N > 2, "The Assembly-optimized montgomery reduction requires a minimum of 2 limbs."
  doAssert N <= 6, "The Assembly-optimized montgomery reduction requires at most 6 limbs."

  result = newStmtList()

  var ctx = init(Assembler_x86, BaseType)
  # On x86, compilers only let us use 15 out of 16 registers
  # RAX and RDX are defacto used due to the MUL instructions
  # so we store everything in scratchspaces restoring as needed
  let
    # We could force M as immediate by specializing per moduli
    M = asmArray(M_MEM, N, MemOffsettable, asmInput)
    # MUL requires RAX and RDX

  let uSlots = N+2
  let vSlots = max(N-2, 3)
  let uSym = ident"u"
  let vSym = ident"v"
  var # Scratchspaces
    u = asmArray(uSym, uSlots, ElemsInReg, asmInputOutputEarlyClobber)
    v = asmArray(vSym, vSlots, ElemsInReg, asmInputOutputEarlyClobber)

  # Prologue
  result.add quote do:
    var `uSym`{.noinit, used.}: Limbs[`uSlots`]
    var `vSym` {.noInit.}: Limbs[`vSlots`]
    `vSym`[0] = cast[SecretWord](`r_PIR`[0].unsafeAddr)
    `vSym`[1] = cast[SecretWord](`a_PIR`[0].unsafeAddr)
    `vSym`[2] = SecretWord(`m0ninv_REG`)

  let r_temp = v[0].asArrayAddr(r_PIR, len = N, memIndirect = memWrite)
  let a = v[1].asArrayAddr(a_PIR, len = 2*N, memIndirect = memRead)
  let m0ninv = v[2]

  # Algorithm
  # ---------------------------------------------------------
  # for i in 0 .. n-1:
  #   hi <- 0
  #   m <- a[i] * m0ninv mod 2ʷ (i.e. simple multiplication)
  #   for j in 0 .. n-1:
  #     (hi, lo) <- a[i+j] + m * M[j] + hi
  #     a[i+j] <- lo
  #   a[i+n] += hi
  # for i in 0 .. n-1:
  #   r[i] = a[i+n]
  # if r >= M:
  #   r -= M

  for i in 0 ..< N:
    ctx.mov u[i], a[i]

  ctx.mov u[N], u[0]
  ctx.imul u[0], m0ninv    # m <- a[i] * m0ninv mod 2ʷ
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

  if not(spareBits >= 2 and skipFinalSub):
    ctx.mov rdx, r_temp
  let r = rdx.asArrayAddr(r_PIR, len = N, memIndirect = memWrite)

  # This does a[i+n] += hi
  # but in a separate carry chain, fused with the
  # copy "r[i] = a[i+n]"
  for i in 0 ..< N:
    if i == 0:
      ctx.add u[i], a[i+N]
    else:
      ctx.adc u[i], a[i+N]

  # v is invalidated from now on
  let t = repackRegisters(v, u[N], u[N+1])

  if spareBits >= 2 and skipFinalSub:
    for i in 0 ..< N:
      ctx.mov r_temp[i], u[i]
  elif spareBits >= 1:
    ctx.finalSubNoOverflowImpl(r, u, M, t)
  else:
    ctx.finalSubMayOverflowImpl(r, u, M, t)

  # Code generation
  result.add ctx.generate()

func redcMont_asm*[N: static int](
       r: var array[N, SecretWord],
       a: array[N*2, SecretWord],
       M: array[N, SecretWord],
       m0ninv: BaseType,
       spareBits: static int,
       skipFinalSub: static bool) =
  ## Constant-time Montgomery reduction
  static: doAssert UseASM_X86_64, "This requires x86-64."
  redc2xMont_gen(r, a, M, m0ninv, spareBits, skipFinalSub)

# Montgomery conversion
# ----------------------------------------------------------

macro mulMont_by_1_gen[N: static int](
       t_EIR: var array[N, SecretWord],
       M_MEM: array[N, SecretWord],
       m0ninv_REG: BaseType) =

  # No register spilling handling
  doAssert N <= 6, "The Assembly-optimized montgomery reduction requires at most 6 limbs."

  result = newStmtList()

  var ctx = init(Assembler_x86, BaseType)
  # On x86, compilers only let us use 15 out of 16 registers
  # RAX and RDX are defacto used due to the MUL instructions
  # so we store everything in scratchspaces restoring as needed
  let
    t = asmArray(t_EIR, N, ElemsInReg, asmInputOutputEarlyClobber)
    # We could force M as immediate by specializing per moduli
    M = asmArray(M_MEM, N, MemOffsettable, asmInput)

    # MUL requires RAX and RDX

    m0ninv = asmValue(m0ninv_REG, Mem, asmInput)
    Csym = ident"C"
    C = asmValue(Csym, Reg, asmOutputEarlyClobber) # Stores the high-part of muliplication
    mSym = ident"m"
    m = asmValue(msym, Reg, asmOutputEarlyClobber) # Stores (t[0] * m0ninv) mod 2ʷ

  # Copy a in t
  result.add quote do:
    var `Csym` {.noInit, used.}: BaseType
    var `mSym` {.noInit, used.}: BaseType

  # Algorithm
  # ---------------------------------------------------------
  # for i in 0 .. n-1:
  #   m <- t[0] * m0ninv mod 2ʷ (i.e. simple multiplication)
  #   C, _ = t[0] + m * M[0]
  #   for j in 1 .. n-1:
  #     (C, t[j-1]) <- r[j] + m*M[j] + C
  #   t[n-1] = C

  ctx.comment "for i in 0 ..< N:"
  for i in 0 ..< N:
    ctx.comment "  m <- t[0] * m0ninv mod 2ʷ"
    ctx.mov m, m0ninv
    ctx.imul m, t[0]

    ctx.comment "  C, _ = t[0] + m * M[0]"
    ctx.`xor` C, C
    ctx.mov rax, M[0]
    ctx.mul rdx, rax, m, rax
    ctx.add rax, t[0]
    ctx.adc C, rdx

    ctx.comment "  for j in 1 .. n-1:"
    for j in 1 ..< N:
      ctx.comment "    (C, t[j-1]) <- r[j] + m*M[j] + C"
      ctx.mov rax, M[j]
      ctx.mul rdx, rax, m, rax
      ctx.add C, t[j]
      ctx.adc rdx, 0
      ctx.add C, rax
      ctx.adc rdx, 0
      ctx.mov t[j-1], C
      ctx.mov C, rdx

    ctx.comment "  final carry"
    ctx.mov t[N-1], C

  result.add ctx.generate()

func fromMont_asm*(r: var Limbs, a, M: Limbs, m0ninv: BaseType) =
  ## Constant-time Montgomery residue form to BigInt conversion
  var t{.noInit.} = a
  block:
    t.mulMont_by_1_gen(M, m0ninv)

  block: # Map from [0, 2p) to [0, p)
    var workspace{.noInit.}: typeof(r)
    r.finalSub_gen(t, M, workspace, mayOverflow = false)
