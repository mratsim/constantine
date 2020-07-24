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
  ./limbs_generic,
  ./limbs_asm_montmul_x86

# ############################################################
#
#        Assembly implementation of finite fields
#
# ############################################################

# Note: We can refer to at most 30 registers in inline assembly
#       and "InputOutput" registers count double
#       They are nice to let the compiler deals with mov
#       but too constraining so we move things ourselves.

static: doAssert UseX86ASM

# MULX/ADCX/ADOX
{.localPassC:"-madx -mbmi2".}
# Necessary for the compiler to find enough registers (enabled at -O1)
{.localPassC:"-fomit-frame-pointer".}

# Montgomery Multiplication
# ------------------------------------------------------------
proc mulx_by_word(
       ctx: var Assembler_x86,
       C: Operand,
       t: OperandArray,
       a: Operand, # Pointer in scratchspace
       word: Operand,
       S, rRDX: Operand
     ) =
  ## Multiply the `a[0..<N]` by `word` and store in `t[0..<N]`
  ## and carry register `C` (t[N])
  ## `t` and `C` overwritten
  ## `S` is a scratchspace carry register
  ## `rRDX` is the RDX register descriptor
  let N = t.len

  doAssert N >= 2, "The Assembly-optimized montgomery multiplication requires at least 2 limbs."
  ctx.comment "  Outer loop i = 0"
  ctx.`xor` rRDX, rRDX # Clear flags - TODO: necessary?
  ctx.mov rRDX, word

  # for j=0 to N-1
  #  (C,t[j])  := t[j] + a[j]*b[i] + C

  # First limb
  ctx.mulx t[1], t[0], a[0], rdx

  # Steady state
  for j in 1 ..< N-1:
    ctx.mulx t[j+1], S, a[j], rdx
    ctx.adox t[j], S   # TODO, we probably can use ADC here

  # Last limb
  ctx.mulx C, S, a[N-1], rdx
  ctx.adox t[N-1], S

  # Final carries
  ctx.comment "  Mul carries i = 0"
  ctx.mov  rRDX, 0 # Set to 0 without clearing flags
  ctx.adcx C, rRDX
  ctx.adox C, rRDX

proc mulaccx_by_word(
       ctx: var Assembler_x86,
       C: Operand,
       t: OperandArray,
       a: Operand, # Pointer in scratchspace
       i: int,
       word: Operand,
       S, rRDX: Operand
     ) =
  ## Multiply the `a[0..<N]` by `word`
  ## and accumulate in `t[0..<N]`
  ## and carry register `C` (t[N])
  ## `t` and `C` are multiply-accumulated
  ## `S` is a scratchspace register
  ## `rRDX` is the RDX register descriptor
  let N = t.len

  doAssert N >= 2, "The Assembly-optimized montgomery multiplication requires at least 2 limbs."
  doAssert i != 0

  ctx.comment "  Outer loop i = " & $i
  ctx.`xor` rRDX, rRDX # Clear flags - TODO: necessary?
  ctx.mov rRDX, word

  # for j=0 to N-1
  #  (C,t[j])  := t[j] + a[j]*b[i] + C

  # Steady state
  for j in 0 ..< N-1:
    ctx.mulx C, S, a[j], rdx
    ctx.adox t[j], S
    ctx.adcx t[j+1], C

  # Last limb
  ctx.mulx C, S, a[N-1], rdx
  ctx.adox t[N-1], S

  # Final carries
  ctx.comment "  Mul carries i = " & $i
  ctx.mov  rRDX, 0 # Set to 0 without clearing flags
  ctx.adcx C, rRDX
  ctx.adox C, rRDX

proc partialRedx(
       ctx: var Assembler_x86,
       C: Operand,
       t: OperandArray,
       M: OperandArray,
       m0ninv: Operand,
       lo, S, rRDX: Operand
     ) =
    ## Partial Montgomery reduction
    ## For CIOS method
    ## `C` the update carry flag (represents t[N])
    ## `t[0..<N]` the array to reduce
    ## `M[0..<N] the prime modulus
    ## `m0ninv` The montgomery magic number -1/M[0]
    ## `lo` and `S` are scratchspace registers
    ## `rRDX` is the RDX register descriptor

    let N = M.len

    # m = t[0] * m0ninv mod 2^w
    ctx.comment "  Reduction"
    ctx.comment "  m = t[0] * m0ninv mod 2^w"
    ctx.mov  rRDX, t[0]
    ctx.mulx S, rRDX, m0ninv, rdx # (S, RDX) <- m0ninv * RDX

    # Clear carry flags - TODO: necessary?
    ctx.`xor` S, S

    # S,_ := t[0] + m*M[0]
    ctx.comment "  S,_ := t[0] + m*M[0]"
    ctx.mulx S, lo, M[0], rdx
    ctx.adcx lo, t[0] # set the carry flag for the future ADCX
    ctx.mov  t[0], S

    # for j=1 to N-1
    #   (S,t[j-1]) := t[j] + m*M[j] + S
    ctx.comment "  for j=1 to N-1"
    ctx.comment "    (S,t[j-1]) := t[j] + m*M[j] + S"
    for j in 1 ..< N:
      ctx.adcx t[j-1], t[j]
      ctx.mulx t[j], S, M[j], rdx
      ctx.adox t[j-1], S

    # Last carries
    # t[N-1} = S + C
    ctx.comment "  Reduction carry "
    ctx.mov S, 0
    ctx.adcx t[N-1], S
    ctx.adox t[N-1], C

macro montMul_CIOS_nocarry_adx_bmi2_gen[N: static int](r_MM: var Limbs[N], a_MM, b_MM, M_MM: Limbs[N], m0ninv_MM: BaseType): untyped =
  ## Generate an optimized Montgomery Multiplication kernel
  ## using the CIOS method
  ## This requires the most significant word of the Modulus
  ##   M[^1] < high(SecretWord) shr 2 (i.e. less than 0b00111...1111)
  ## https://hackmd.io/@zkteam/modular_multiplication

  result = newStmtList()

  var ctx = init(Assembler_x86, BaseType)
  let
    scratchSlots = max(N, 6)

    r = init(OperandArray, nimSymbol = r_MM, N, PointerInReg, InputOutput)
    # We could force M as immediate by specializing per moduli
    M = init(OperandArray, nimSymbol = M_MM, N, PointerInReg, Input)
    # If N is too big, we need to spill registers. TODO.
    t = init(OperandArray, nimSymbol = ident"t", N, ElemsInReg, Output_EarlyClobber)
    # MultiPurpose Register slots
    scratch = init(OperandArray, nimSymbol = ident"scratch", scratchSlots, ElemsInReg, InputOutput)

    # MULX requires RDX
    rRDX = Operand(
      desc: OperandDesc(
        asmId: "[rdx]",
        nimSymbol: ident"rdx",
        rm: RDX,
        constraint: Output_EarlyClobber,
        cEmit: "rdx"
      )
    )

    a = scratch[0].asArrayAddr(len = N) # Store the `a` operand
    b = scratch[1].asArrayAddr(len = N) # Store the `b` operand
    A = scratch[2]                      # High part of extended precision multiplication
    C = scratch[3]
    m0ninv = scratch[4]                 # Modular inverse of M[0]
    lo = scratch[5]                     # Discard "lo" part of partial Montgomery Reduction

  # Registers used:
  # - 1 for `r`
  # - 1 for `M`
  # - 6 for `t`     (at most)
  # - 6 for `scratch`
  # - 1 for RDX
  # Total 15 out of 16
  # We can save 1 by hardcoding M as immediate (and m0ninv)
  # but this prevent reusing the same code for multiple curves like BLS12-377 and BLS12-381
  # We might be able to save registers by having `r` and `M` be memory operand as well

  let tsym = t.nimSymbol
  let scratchSym = scratch.nimSymbol
  let edx = rRDX.desc.nimSymbol
  result.add quote do:
    static: doAssert: sizeof(SecretWord) == sizeof(ByteAddress)

    var `tsym`: typeof(`r_MM`) # zero init
    # Assumes 64-bit limbs on 64-bit arch (or you can't store an address)
    var `scratchSym` {.noInit.}: Limbs[`scratchSlots`]
    var `edx`{.noInit.}: BaseType

    `scratchSym`[0] = cast[SecretWord](`a_MM`[0].unsafeAddr)
    `scratchSym`[1] = cast[SecretWord](`b_MM`[0].unsafeAddr)
    `scratchSym`[4] = SecretWord `m0ninv_MM`

  # Algorithm
  # -----------------------------------------
  # for i=0 to N-1
  #   for j=0 to N-1
  # 		(A,t[j])  := t[j] + a[j]*b[i] + A
  #   m := t[0]*m0ninv mod W
  # 	C,_ := t[0] + m*M[0]
  # 	for j=1 to N-1
  # 		(C,t[j-1]) := t[j] + m*M[j] + C
  #   t[N-1] = C + A

  # No register spilling handling
  doAssert N <= 6, "The Assembly-optimized montgomery multiplication requires at most 6 limbs."

  for i in 0 ..< N:
    if i == 0:
      ctx.mulx_by_word(
        A, t,
        a,
        b[0],
        C, rRDX
      )
    else:
      ctx.mulaccx_by_word(
        A, t,
        a, i,
        b[i],
        C, rRDX
      )

    ctx.partialRedx(
      A, t,
      M, m0ninv,
      lo, C, rRDX
    )

  ctx.finalSub(
    r, t, M,
    scratch
  )

  result.add ctx.generate

func montMul_CIOS_nocarry_asm_adx_bmi2*(r: var Limbs, a, b, M: Limbs, m0ninv: BaseType) =
  ## Constant-time modular multiplication
  montMul_CIOS_nocarry_adx_bmi2_gen(r, a, b, M, m0ninv)
