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
       t, M, scratch: OperandArray
     ) =
  ## Reduce `t` into `r` modulo `M`
  let N = M.len
  ctx.comment "Final substraction (no carry)"
  for i in 0 ..< N:
    ctx.mov scratch[i], t[i]
    if i == 0:
      ctx.sub scratch[i], M[i]
    else:
      ctx.sbb scratch[i], M[i]

  # If we borrowed it means that we were smaller than
  # the modulus and we don't need "scratch"
  for i in 0 ..< N:
    ctx.cmovnc t[i], scratch[i]
    ctx.mov r[i], t[i]

proc finalSubCanOverflow*(
       ctx: var Assembler_x86,
       r: Operand or OperandArray,
       t, M, scratch: OperandArray,
       overflowReg: Operand
     ) =
  ## Reduce `t` into `r` modulo `M`
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
    ctx.mov scratch[i], t[i]
    if i == 0:
      ctx.sub scratch[i], M[i]
    else:
      ctx.sbb scratch[i], M[i]

  ctx.sbb overflowReg, 0

  # If we borrowed it means that we were smaller than
  # the modulus and we don't need "scratch"
  for i in 0 ..< N:
    ctx.cmovnc t[i], scratch[i]
    ctx.mov r[i], t[i]


# Montgomery reduction
# ------------------------------------------------------------

macro montyRed_gen[N: static int](
       r_MR: var array[N, SecretWord],
       t_MR: array[N*2, SecretWord],
       M_MR: array[N, SecretWord],
       m0ninv_MR: BaseType,
       canUseNoCarryMontyMul: static bool
      ) =
  # TODO, slower than Clang, in particular due to the shadowing

  result = newStmtList()

  var ctx = init(Assembler_x86, BaseType)
  let
    # We could force M as immediate by specializing per moduli
    M = init(OperandArray, nimSymbol = M_MR, N, PointerInReg, Input)

    # MUL requires RAX and RDX
    rRAX = Operand(
      desc: OperandDesc(
        asmId: "[rax]",
        nimSymbol: ident"rax",
        rm: RAX,
        constraint: InputOutput_EnsureClobber,
        cEmit: "rax"
      )
    )

    rRDX = Operand(
      desc: OperandDesc(
        asmId: "[rdx]",
        nimSymbol: ident"rdx",
        rm: RDX,
        constraint: Output_EarlyClobber,
        cEmit: "rdx"
      )
    )

    m0ninv = Operand(
      desc: OperandDesc(
        asmId: "[m0ninv]",
        nimSymbol: m0ninv_MR,
        rm: Reg,
        constraint: Input,
        cEmit: "m0ninv"
      )
    )


  let scratchSlots = N+2
  var scratch = init(OperandArray, nimSymbol = ident"scratch", scratchSlots, ElemsInReg, InputOutput_EnsureClobber)

  # Prologue
  let eax = rRAX.desc.nimSymbol
  let edx = rRDX.desc.nimSymbol
  let scratchSym = scratch.nimSymbol
  result.add quote do:
    static: doAssert: sizeof(SecretWord) == sizeof(ByteAddress)

    var `eax`{.noInit.}, `edx`{.noInit.}: BaseType
    var `scratchSym` {.noInit.}: Limbs[`scratchSlots`]

  # Algorithm
  # ---------------------------------------------------------
  # for i in 0 .. n-1:
  #   hi <- 0
  #   m <- t[i] * m0ninv mod 2^w (i.e. simple multiplication)
  #   for j in 0 .. n-1:
  #     (hi, lo) <- t[i+j] + m * M[j] + hi
  #     t[i+j] <- lo
  #   t[i+n] += hi
  # for i in 0 .. n-1:
  #   r[i] = t[i+n]
  # if r >= M:
  #   r -= M

  # No register spilling handling
  doAssert N <= 6, "The Assembly-optimized montgomery multiplication requires at most 6 limbs."

  result.add quote do:
    `eax` = BaseType `t_MR`[0]
    `scratchSym`[1 .. `N`-1] = `t_MR`.toOpenArray(1, `N`-1)

  ctx.mov scratch[N], rRAX
  ctx.imul rRAX, m0ninv    # m <- t[i] * m0ninv mod 2^w
  ctx.mov scratch[0], rRAX

  # scratch: [t[0] * m0, t[1], t[2], t[3], t[0]] for 4 limbs

  for i in 0 ..< N:
    ctx.comment ""
    let hi = scratch[N]
    let next = scratch[N+1]

    ctx.mul rdx, rax, M[0], rax
    ctx.add hi, rRAX # Guaranteed to be zero
    ctx.mov rRAX, scratch[0]
    ctx.adc hi, rRDX

    for j in 1 ..< N-1:
      ctx.comment ""
      ctx.mul rdx, rax, M[j], rax
      ctx.add scratch[j], rRAX
      ctx.mov rRAX, scratch[0]
      ctx.adc rRDX, 0
      ctx.add scratch[j], hi
      ctx.adc rRDX, 0
      ctx.mov hi, rRDX

    # Next load
    if i < N-1:
      ctx.comment ""
      ctx.mov next, scratch[1]
      ctx.imul scratch[1], m0ninv
      ctx.comment ""

    # Last limb
    ctx.comment ""
    ctx.mul rdx, rax, M[N-1], rax
    ctx.add scratch[N-1], rRAX
    ctx.mov rRAX, scratch[1] # Contains next * m0
    ctx.adc rRDX, 0
    ctx.add scratch[N-1], hi
    ctx.adc rRDX, 0
    ctx.mov hi, rRDX

    scratch.rotateLeft()

  # Code generation
  result.add ctx.generate()

  # New codegen
  ctx = init(Assembler_x86, BaseType)

  let r = init(OperandArray, nimSymbol = r_MR, N, PointerInReg, InputOutput_EnsureClobber)
  let t = init(OperandArray, nimSymbol = t_MR, N*2, PointerInReg, Input)
  let extraRegNeeded = N-2
  let tsub = init(OperandArray, nimSymbol = ident"tsub", extraRegNeeded, ElemsInReg, InputOutput_EnsureClobber)
  let tsubsym = tsub.nimSymbol
  result.add quote do:
    var `tsubsym` {.noInit.}: Limbs[`extraRegNeeded`]

  # This does t[i+n] += hi
  # but in a separate carry chain, fused with the
  # copy "r[i] = t[i+n]"
  for i in 0 ..< N:
    if i == 0:
      ctx.add scratch[i], t[i+N]
    else:
      ctx.adc scratch[i], t[i+N]

  let reuse = repackRegisters(tsub, scratch[N], scratch[N+1])

  if canUseNoCarryMontyMul:
    ctx.finalSubNoCarry(r, scratch, M, reuse)
  else:
    ctx.finalSubCanOverflow(r, scratch, M, reuse, rRAX)

  # Code generation
  result.add ctx.generate()

func montRed_asm*[N: static int](
       r: var array[N, SecretWord],
       t: array[N*2, SecretWord],
       M: array[N, SecretWord],
       m0ninv: BaseType,
       canUseNoCarryMontyMul: static bool
      ) =
  ## Constant-time Montgomery reduction
  montyRed_gen(r, t, M, m0ninv, canUseNoCarryMontyMul)
