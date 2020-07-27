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
  ../config/common,
  ../primitives,
  ./limbs

# ############################################################
#
#        Assembly implementation of finite fields
#
# ############################################################


static: doAssert UseASM_X86_32

# Necessary for the compiler to find enough registers (enabled at -O1)
{.localPassC:"-fomit-frame-pointer".}

proc finalSub*(
       ctx: var Assembler_x86,
       r: Operand or OperandArray,
       t, M, scratch: OperandArray
     ) =
  ## Reduce `t` into `r` modulo `M`
  let N = M.len
  ctx.comment "Final substraction"
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

# Montgomery reduction
# ------------------------------------------------------------

macro montyRed_gen[N: static int](
       r_MR: var array[N, SecretWord],
       t_MR: array[N*2, SecretWord],
       M_MR: array[N, SecretWord],
       m0ninv_MR: BaseType) =
  # TODO, slower than Clang, in particular due to the shadowing

  result = newStmtList()

  var ctx = init(Assembler_x86, BaseType)
  let
    r = init(OperandArray, nimSymbol = r_MR, N, PointerInReg, InputOutput_EnsureClobber)
    # We could force M as immediate by specializing per moduli
    M = init(OperandArray, nimSymbol = M_MR, N, PointerInReg, Input)
    # If N is too big, we need to spill registers. TODO.
    t = init(OperandArray, nimSymbol = t_MR, N*2, PointerInReg, InputOutput_EnsureClobber)
    acc = init(OperandArray, nimSymbol = ident"acc", N, ElemsInReg, Output_EarlyClobber)

    scratchSlots = 4
    scratch = init(OperandArray, nimSymbol = ident"scratch", scratchSlots, ElemsInReg, InputOutput_EnsureClobber)

    # MUL requires RAX and RDX
    rRAX = Operand(
      desc: OperandDesc(
        asmId: "[rax]",
        nimSymbol: ident"rax",
        rm: RAX,
        constraint: Output_EarlyClobber,
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

    hi = scratch[0]
    lo = scratch[1]
    m = scratch[2]
    m0ninv = scratch[3]

  # Prologue
  let accSym = acc.nimSymbol
  let eax = rRAX.desc.nimSymbol
  let edx = rRDX.desc.nimSymbol
  let scratchSym = scratch.nimSymbol
  let tShadow = ident($t_MR)
  result.add quote do:
    static: doAssert: sizeof(SecretWord) == sizeof(ByteAddress)

    var `eax`{.noInit.}, `edx`{.noInit.}: BaseType
    var `scratchSym` {.noInit.}: Limbs[`scratchSlots`]
    `scratchSym`[3] = SecretWord `m0ninv_MR`

    var `accSym`{.noInit.}: Limbs[`N`]

    # Mutable shadowing
    var ts = `t_MR`
    let `tShadow` = ts.addr

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

  for i in 0 ..< N:
    ctx.`xor` acc[i], acc[i]
    ctx.`xor` hi, hi
    # m <- t[i] * m0ninv mod 2^w (i.e. simple multiplication)
    ctx.mov m, m0ninv
    ctx.imul m, t[i]

    # (hi, t[i]) <- m * M[0] + t[i]
    ctx.mov rRAX, M[0]
    ctx.mul rdx, rax, m, rax
    ctx.add rRAX, t[i]
    ctx.adc hi, rRDX
    ctx.mov t[i], rRAX

    for j in 1 ..< N:
      ctx.mov lo, t[i+j]
      ctx.mov rRAX, M[j]
      ctx.mul rdx, rax, m, rax
      ctx.add lo, hi # t[i+j] + hi
      ctx.adc rRDX, 0
      ctx.`xor` hi, hi
      ctx.add lo, rRAX
      ctx.adc hi, rRDX
      ctx.mov t[i+j], lo

    ctx.mov acc[i], hi

  # This does t[i+n] += hi
  # but in a separate carry chain, fused with the
  # copy "r[i] = t[i+n]"
  for i in 0 ..< N:
    if i == 0:
      ctx.add acc[i], t[i+N]
    else:
      ctx.adc acc[i], t[i+N]

  let reuse = repackRegisters(scratch, rRAX, rRDX)
  ctx.finalSub(r, acc, M, reuse)

  # Code generation
  result.add ctx.generate()

func montRed_asm*[N: static int](
       r: var array[N, SecretWord],
       t: array[N*2, SecretWord],
       M: array[N, SecretWord],
       m0ninv: BaseType) {.inline.} =
  ## Constant-time Montegomery reduction
  montyRed_gen(r, t, M, m0ninv)
