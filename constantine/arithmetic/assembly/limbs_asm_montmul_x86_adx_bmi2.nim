# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  # Standard library
  std/[macros, algorithm],
  # Internal
  ../../config/common,
  ../../primitives,
  ./limbs_asm_modular_x86,
  ./limbs_asm_montred_x86_adx_bmi2,
  ./limbs_asm_mul_x86_adx_bmi2

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
{.localPassC:"-fomit-frame-pointer".}

# Montgomery Multiplication
# ------------------------------------------------------------

proc mulx_by_word(
       ctx: var Assembler_x86,
       hi: Operand,
       t: OperandArray,
       a: Operand, # Pointer in scratchspace
       word0: Operand,
       lo: Operand
     ) =
  ## Multiply the `a[0..<N]` by `word` and store in `t[0..<N]`
  ## and carry register `C` (t[N])
  ## `t` and `C` overwritten
  ## `S` is a scratchspace carry register
  ## `rRDX` is the RDX register descriptor
  let N = min(a.len, t.len)

  ctx.comment "  Outer loop i = 0"

  # for j=0 to N-1
  #  (C,t[j])  := t[j] + a[j]*b[i] + C

  # First limb
  ctx.mov rdx, word0
  if N > 1:
    ctx.mulx t[1], t[0], a[0], rdx
    ctx.`xor` hi, hi # Clear flags - TODO: necessary?
  else:
    ctx.mulx hi, t[0], a[0], rdx
    return

  # Steady state
  for j in 1 ..< N-1:
    ctx.mulx t[j+1], lo, a[j], rdx
    if j == 1:
      ctx.add t[j], lo
    else:
      ctx.adc t[j], lo

  # Last limb
  ctx.comment "  Outer loop i = 0, last limb"
  ctx.mulx hi, lo, a[N-1], rdx
  ctx.adc t[N-1], lo

  # Final carries
  ctx.comment "  Accumulate last carries in hi word"
  ctx.adc hi, 0

proc mulaccx_by_word(
       ctx: var Assembler_x86,
       hi: Operand,
       t: OperandArray,
       a: Operand, # Pointer in scratchspace
       i: int,
       word: Operand,
       lo: Operand
     ) =
  ## Multiply the `a[0..<N]` by `word`
  ## and accumulate in `t[0..<N]`
  ## and carry register `C` (t[N])
  ## `t` and `C` are multiply-accumulated
  ## `S` is a scratchspace register
  let N = min(a.len, t.len)

  doAssert i != 0

  ctx.comment "  Outer loop i = " & $i & ", j in [0, " & $N & ")"
  ctx.mov rdx, word
  ctx.`xor` hi, hi # Clear flags - TODO: necessary?

  # for j=0 to N-1
  #  (C,t[j])  := t[j] + a[j]*b[i] + C

  # Steady state
  for j in 0 ..< N-1:
    ctx.mulx hi, lo, a[j], rdx
    ctx.adox t[j], lo
    ctx.adcx t[j+1], hi

  # Last limb
  ctx.comment "  Outer loop i = " & $i & ", last limb"
  ctx.mulx hi, lo, a[N-1], rdx
  ctx.adox t[N-1], lo

  # Final carries
  ctx.comment "  Accumulate last carries in hi word"
  ctx.mov  rdx, 0 # Set to 0 without clearing flags
  ctx.adcx hi, rdx
  ctx.adox hi, rdx

proc partialRedx(
       ctx: var Assembler_x86,
       C: Operand,
       t: OperandArray,
       M: OperandArray,
       m0ninv: Operand,
       lo, S: Operand
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
    ctx.mov  rdx, t[0]
    ctx.imul rdx, m0ninv

    # Clear carry flags
    ctx.`xor` S, S

    # S,_ := t[0] + m*M[0]
    ctx.comment "  S,_ := t[0] + m*M[0]"
    ctx.mulx S, lo, M[0], rdx
    ctx.adcx lo, t[0] # set the carry flag for the future ADCX
    ctx.mov  t[0], S

    ctx.mov lo, 0

    # for j=1 to N-1
    #   (S,t[j-1]) := t[j] + m*M[j] + S
    ctx.comment "  for j=1 to N-1"
    ctx.comment "    (S,t[j-1]) := t[j] + m*M[j] + S"
    for j in 1 ..< N:
      ctx.adcx t[j-1], t[j]
      ctx.mulx t[j], S, M[j], rdx
      ctx.adox t[j-1], S

    # Last carries
    # t[N-1] = S + C
    ctx.comment "  Reduction carry "
    ctx.adcx lo, C      # lo contains 0 so C += S
    ctx.adox t[N-1], lo

macro montMul_CIOS_sparebit_adx_bmi2_gen[N: static int](r_MM: var Limbs[N], a_MM, b_MM, M_MM: Limbs[N], m0ninv_MM: BaseType): untyped =
  ## Generate an optimized Montgomery Multiplication kernel
  ## using the CIOS method
  ## This requires the most significant word of the Modulus
  ##   M[^1] < high(SecretWord) shr 2 (i.e. less than 0b00111...1111)
  ## https://hackmd.io/@zkteam/modular_multiplication

  # No register spilling handling
  doAssert N <= 6, "The Assembly-optimized montgomery multiplication requires at most 6 limbs."

  result = newStmtList()

  var ctx = init(Assembler_x86, BaseType)
  let
    scratchSlots = max(N, 6)

    r = init(OperandArray, nimSymbol = r_MM, N, PointerInReg, InputOutput_EnsureClobber)
    # We could force M as immediate by specializing per moduli
    M = init(OperandArray, nimSymbol = M_MM, N, PointerInReg, Input)
    # If N is too big, we need to spill registers. TODO.
    t = init(OperandArray, nimSymbol = ident"t", N, ElemsInReg, Output_EarlyClobber)
    # MultiPurpose Register slots
    scratch = init(OperandArray, nimSymbol = ident"scratch", scratchSlots, ElemsInReg, InputOutput_EnsureClobber)

    # MULX requires RDX as well

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
  result.add quote do:
    static: doAssert: sizeof(SecretWord) == sizeof(ByteAddress)

    var `tsym`: typeof(`r_MM`) # zero init
    # Assumes 64-bit limbs on 64-bit arch (or you can't store an address)
    var `scratchSym` {.noInit.}: Limbs[`scratchSlots`]
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

  for i in 0 ..< N:
    if i == 0:
      ctx.mulx_by_word(
        A, t,
        a,
        b[0],
        C
      )
    else:
      ctx.mulaccx_by_word(
        A, t,
        a, i,
        b[i],
        C
      )

    ctx.partialRedx(
      A, t,
      M, m0ninv,
      lo, C
    )

  ctx.finalSubNoCarryImpl(
    r, t, M,
    scratch
  )

  result.add ctx.generate

func montMul_CIOS_sparebit_asm_adx_bmi2*(r: var Limbs, a, b, M: Limbs, m0ninv: BaseType) =
  ## Constant-time modular multiplication
  ## Requires the prime modulus to have a spare bit in the representation. (Hence if using 64-bit words and 4 words, to be at most 255-bit)
  r.montMul_CIOS_sparebit_adx_bmi2_gen(a, b, M, m0ninv)

# Montgomery Squaring
# ------------------------------------------------------------

func square_asm_adx_bmi2_inline[rLen, aLen: static int](r: var Limbs[rLen], a: Limbs[aLen]) {.inline.} =
  ## Multi-precision Squaring
  ## Extra indirection as the generator assumes that
  ## arrays are pointers, which is true for parameters
  ## but not for stack variables.
  sqrx_gen(r, a)

func montRed_asm_adx_bmi2_inline[N: static int](
       r: var array[N, SecretWord],
       a: array[N*2, SecretWord],
       M: array[N, SecretWord],
       m0ninv: BaseType,
       hasSpareBit: static bool
      ) {.inline.} =
  ## Constant-time Montgomery reduction
  ## Extra indirection as the generator assumes that
  ## arrays are pointers, which is true for parameters
  ## but not for stack variables.
  montyRedc2x_adx_gen(r, a, M, m0ninv, hasSpareBit)

func montSquare_CIOS_asm_adx_bmi2*[N](
       r: var Limbs[N],
       a, M: Limbs[N],
       m0ninv: BaseType,
       hasSpareBit: static bool) =
  ## Constant-time modular squaring
  var r2x {.noInit.}: Limbs[2*N]
  r2x.square_asm_adx_bmi2_inline(a)
  r.montRed_asm_adx_bmi2_inline(r2x, M, m0ninv, hasSpareBit)
