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

# Note: We can refer to at most 30 registers in inline assembly
#       and "InputOutput" registers count double
#       They are nice to let the compiler deals with mov
#       but too constraining so we move things ourselves.

static: doAssert UseASM_X86_64

# MULX/ADCX/ADOX
{.localPassC:"-madx -mbmi2".}
# Necessary for the compiler to find enough registers (enabled at -O1)
# {.localPassC:"-fomit-frame-pointer".}

# Multiplication
# ------------------------------------------------------------
proc mulx_by_word(
       ctx: var Assembler_x86,
       r0: Operand,
       a, t: OperandArray,
       word0: Operand
     ) =
  ## Multiply the `a[0..<N]` by `word`
  ## and store in `[t:r0]`
  ## with [t:r0] = tn, tn-1, ... t1, r0
  doAssert a.len + 1 == t.len
  let N = a.len

  ctx.comment "  Outer loop i = 0, j=0 to " & $N

  # for j=0 to N-1
  #  (C,t[j])  := t[j] + a[j]*b[i] + C

  # First limb
  ctx.mov rdx, word0
  ctx.`xor` rax, rax # Clear flags (important if steady state is skipped)
  ctx.mulx t[0], rax, a[0], rdx
  ctx.mov r0, rax

  # Steady state
  for j in 1 ..< N:
    ctx.mulx t[j], rax, a[j], rdx
    if j == 1:
      ctx.add t[j-1], rax
    else:
      ctx.adc t[j-1], rax

  # Final carries
  ctx.comment "  Accumulate last carries in hi word"
  ctx.adc t[N-1], 0

proc mulaccx_by_word(
       ctx: var Assembler_x86,
       r: OperandArray,
       i: int,
       a, t: OperandArray,
       word: Operand
     ) =
  ## Multiply the `a[0..<N]` by `word`
  ## and store in `[t:r0]`
  ## with [t:r0] = tn, tn-1, ... t1, r0
  doAssert a.len + 1 == t.len
  let N = min(a.len, r.len)
  let hi = t[a.len]

  doAssert i != 0

  ctx.comment "  Outer loop i = " & $i & ", j in [0, " & $N & ")"
  ctx.mov rdx, word
  ctx.`xor` rax, rax # Clear flags

  # for j=0 to N-1
  #  (C,t[j])  := t[j] + a[j]*b[i] + C

  # Steady state
  for j in 0 ..< N:
    ctx.mulx hi, rax, a[j], rdx
    ctx.adox t[j], rax
    if j == 0:
      ctx.mov r[i], t[j]
    if j == N-1:
      break
    ctx.adcx t[j+1], hi

  # Final carries
  ctx.comment "  Accumulate last carries in hi word"
  ctx.mov  rdx, 0 # Set to 0 without clearing flags
  ctx.adcx hi, rdx
  ctx.adox hi, rdx

macro mulx_gen[rLen, aLen, bLen: static int](rx: var Limbs[rLen], ax: Limbs[aLen], bx: Limbs[bLen]) =
  ## `a`, `b`, `r` can have a different number of limbs
  ## if `r`.limbs.len < a.limbs.len + b.limbs.len
  ## The result will be truncated, i.e. it will be
  ## a * b (mod (2^WordBitwidth)^r.limbs.len)
  ##
  ## Assumes r doesn't aliases a or b

  result = newStmtList()

  var ctx = init(Assembler_x86, BaseType)
  let
    r = init(OperandArray, nimSymbol = rx, rLen, PointerInReg, InputOutput_EnsureClobber)
    a = init(OperandArray, nimSymbol = ax, aLen, PointerInReg, Input)
    b = init(OperandArray, nimSymbol = bx, bLen, PointerInReg, Input)

    # MULX requires RDX

    tSlots = aLen+1 # Extra for high word

  var # If aLen is too big, we need to spill registers. TODO.
    t = init(OperandArray, nimSymbol = ident"t", tSlots, ElemsInReg, Output_EarlyClobber)


  # Prologue
  let tsym = t.nimSymbol
  result.add quote do:
    var `tsym`{.noInit.}: array[`tSlots`, BaseType]

  for i in 0 ..< min(rLen, bLen):
    if i == 0:
      ctx.mulx_by_word(
        r[0],
        a, t,
        b[0]
      )
    else:
      ctx.mulaccx_by_word(
        r, i,
        a, t,
        b[i]
      )

      t.rotateLeft()

  # Copy upper-limbs to result
  for i in b.len ..< min(a.len+b.len, rLen):
    ctx.mov r[i], t[i-b.len]

  # Zero the extra
  if aLen+bLen < rLen:
    ctx.`xor` rax, rax
    for i in aLen+bLen ..< rLen:
      ctx.mov r[i], rax

  # Codegen
  result.add ctx.generate

func mul_asm_adx_bmi2*[rLen, aLen, bLen: static int](r: var Limbs[rLen], a: Limbs[aLen], b: Limbs[bLen]) =
  ## Multi-precision Multiplication
  ## Assumes r doesn't alias a or b
  mulx_gen(r, a, b)


# Squaring
# -----------------------------------------------------------------------------------------------
# TODO: We use 16 registers but GCC/Clang still complain :/

# macro sqrx_gen[rLen, aLen: static int](rx: var Limbs[rLen], ax: Limbs[aLen]) =
#   ## Squaring
#   ## `a` and `r` can have a different number of limbs
#   ## if `r`.limbs.len < a.limbs.len * 2
#   ## The result will be truncated, i.e. it will be
#   ## a² (mod (2^WordBitwidth)^r.limbs.len)
#   ##
#   ## Assumes r doesn't aliases a
#   result = newStmtList()
#
#   var ctx = init(Assembler_x86, BaseType)
#   let
#     # Register count with 6 limbs:
#     # r + a + rax + rdx = 4
#     # t = 2 * a.len = 12
#     # We use the full x86 register set.
#
#     r = init(OperandArray, nimSymbol = rx, rLen, PointerInReg, InputOutput)
#     a = init(OperandArray, nimSymbol = ax, aLen, PointerInReg, Input)
#
#     N = a.len
#     tSlots = a.len * 2
#     # If aLen is too big, we need to spill registers. TODO.
#     t = init(OperandArray, nimSymbol = ident"t", tSlots, ElemsInReg, Output_EarlyClobber)
#
#     # MULX requires RDX
#     rRDX = Operand(
#       desc: OperandDesc(
#         asmId: "[rdx]",
#         nimSymbol: ident"rdx",
#         rm: RDX,
#         constraint: Output_EarlyClobber,
#         cEmit: "rdx"
#       )
#     )
#
#     # Scratch spaces for carries
#     rRAX = Operand(
#       desc: OperandDesc(
#         asmId: "[rax]",
#         nimSymbol: ident"rax",
#         rm: RAX,
#         constraint: Output_EarlyClobber,
#         cEmit: "rax"
#       )
#     )
#
#   # Prologue
#   # -------------------------------
#   let tsym = t.nimSymbol
#   let eax = rRAX.desc.nimSymbol
#   let edx = rRDX.desc.nimSymbol
#   result.add quote do:
#     var `tsym`{.noInit.}: array[`N`, BaseType]
#     var `eax`{.noInit.}, `edx`{.noInit.}: BaseType
#
#   # Algorithm
#   # -------------------------------
#
#   block: # Triangle
#     # i = 0
#     # ----------------
#     ctx.mov rRDX, a[0]
#     # Put a[1..<N] in unused registers, 4 mov per cycle on x86
#     for i in 1 ..< N:
#       ctx.mov t[i+N], a[i]
#
#     let # Carry handlers
#       hi = r.reuseRegister()
#       lo = rRAX
#
#     for j in 1 ..< N:
#       # (carry, t[j]) <- a[j] * a[0] with a[j] in t[j+N]
#       ctx.mulx t[j], rRAX, t[j+N], rdx
#       if j == 1:
#         ctx.add t[j-1], rRAX
#       else:
#         ctx.adc t[j-1], rRAX
#     ctx.adc t[N-1], 0
#
#     for i in 1 ..< N-1:
#       ctx.comment "  Process squaring triangle " & $i
#       ctx.mov rRDX, a[i]
#       ctx.`xor` t[i+N], t[i+N]    # Clear flags
#       for j in i+1 ..< N:
#         ctx.mulx hi, lo, t[j+N], rdx
#         ctx.adox t[i+j], lo
#         if j == N-1:
#           break
#         ctx.adcx t[i+j+1], hi
#
#       ctx.comment "  Accumulate last carries in i+N word"
#       # t[i+N] is already 0
#       ctx.adcx hi, t[i+N]
#       ctx.adox t[i+N], hi
#
#   block:
#     ctx.comment "Finish: (t[2*i+1], t[2*i]) <- 2*t[2*i] + a[i]*a[i]"
#
#     # Restore result
#     ctx.mov r.reuseRegister(), xmm0
#
#     ctx.mov rRDX, a[0]
#
#     # (t[2*i+1], t[2*i]) <- 2*t[2*i] + a[i]*a[i]
#     for i in 0 ..< N:
#       ctx.mulx rRAX, rRDX, a[i], rdx
#       ctx.add t[2*i], t[2*i]
#       ctx.adc t[2*i+1], 0
#       ctx.add t[2*i], rRDX
#       if i != N - 1:
#         ctx.mov rRDX, a[i+1]
#       ctx.adc t[2*i+1], rRAX
#       ctx.mov r[i], t[i]
#
#     # Move the rest
#     for i in N ..< min(rLen, 2*N):
#       ctx.mov r[i], t[i]
#
#   # Codegen
#   result.add ctx.generate
#
# func square_asm_adx_bmi2*[rLen, aLen: static int](r: var Limbs[rLen], a: Limbs[aLen]) =
#   ## Multi-precision Squaring
#   ## Assumes r doesn't alias a
#   sqrx_gen(r, a)
