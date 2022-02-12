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

macro montMul_CIOS_sparebit_adx_bmi2_gen[N: static int](
        t_EIR: var Limbs[N], a_PIR, b_PIR, M_PIR: Limbs[N], m0ninv_REG: BaseType): untyped =
  ## Generate an optimized Montgomery Multiplication kernel
  ## using the CIOS method
  ## This requires the most significant word of the Modulus
  ##   M[^1] < high(SecretWord) shr 2 (i.e. less than 0b00111...1111)
  ## https://hackmd.io/@zkteam/modular_multiplication
  
  # No register spilling handling
  doAssert N in {2..6}, "The Assembly-optimized montgomery multiplication requires at [2, 6] limbs."

  result = newStmtList()

  var ctx = init(Assembler_x86, BaseType)
  let
    # We could force M as immediate by specializing per moduli
    a = init(OperandArray, nimSymbol = a_PIR, N, PointerInReg, Input)
    b = init(OperandArray, nimSymbol = b_PIR, N, PointerInReg, Input)
    M = init(OperandArray, nimSymbol = M_PIR, N, PointerInReg, Input)
    # If N is too big, we need to spill registers. TODO.
    t = init(OperandArray, nimSymbol = t_EIR, N, ElemsInReg, Output_EarlyClobber)

    # MULX requires RDX as well

    m0ninv = Operand(
               desc: OperandDesc(
                 asmId: "[m0ninv]",
                 nimSymbol: m0ninv_REG,
                 rm: MemOffsettable, # TODO, should be Register
                 constraint: Input,
                 cEmit: "&" & $m0ninv_REG
               )
             )
  # Rolling workspace
  var w = init(OperandArray, nimSymbol = ident"w", 2, ElemsInReg, InputOutput_EnsureClobber)
  # Fixed sctachspace
  var s = init(OperandArray, nimSymbol = ident"s", 2, ElemsInReg, InputOutput_EnsureClobber)

  # It is likely that 80% of cryptographic code
  # is spent in Montgomery multiplication.
  # Improving it by some % has an immediate impact on everything.

  # Registers used:
  # - 1   for `a`
  # - 1   for `b`
  # - 1   for `M`
  # - 6   for `t` (assuming 6 limbs)
  # - 2   for `w` (rolling workspace)
  # - 2   for `s` (fixed scratchspace)
  # - 1   for RDX to hold the multiplier for MULX
  # - 1   for RAX for carries
  # Total 15 out of 16
  # + RSP reserved by the compiler for the stack pointer
  #
  # We can save 1 by hardcoding M as immediate (and m0ninv)
  # but this prevent reusing the same code for multiple curves like BLS12-377 and BLS12-381
  # We might be able to save registers by having `r` and `M` be memory operand as well

  let wsym = w.nimSymbol
  let ssym = s.nimSymbol
  result.add quote do:
    var `wsym` {.noInit.}: Limbs[2]
    var `ssym` {.noInit.}: Limbs[2]

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

  # The workspace is used to prefetch
  # a[j] and M[j]
  # They will be stored in a set of rolling registers
  # for 6 limbs
  # [a₀, a₁, a₂, a₃, a₄, a₅, M₀, M₁, M₂, M₃, M₄, M₅]
  var prefetch: seq[Operand]
  for i in 0 ..< N: prefetch.add a[i]
  for i in 0 ..< N: prefetch.add M[i]

  # First iteration
  ctx.mov rdx, b[0]

  # Prefetch the first 4 limbs
  # w = [a₀, a₁]
  # prefetch = [a₂, a₃, a₄, a₅, M₀, M₁, M₂, M₃, M₄, M₅, a₀, a₁]
  for i in 0 ..< w.len:
    ctx.mov w[i], prefetch[0]
    prefetch.rotateLeft(1)

  template rollWorkspace(): untyped =
    w.rotateLeft()
    ctx.mov w[w.len-1], prefetch[0] # Physical roll
    prefetch.rotateLeft(1)

  let
    # Carries for the multiplication step.
    # and extra workspace, usually containing zero
    hiM = s[0]
    z = s[1]

  for i in 0 ..< N:
    # Multiplication by a single word
    # -------------------------------
    #
    #   for j=0 to N-1
    # 		(A,t[j])  := t[j] + a[j]*b[i] + A

    ctx.comment "  Outer loop i = " & $i & ", j in [0, " & $N & ")"
    ctx.`xor` z, z # Reset carry flags and zero z

    for j in 0 ..< N-1:
      ctx.comment "    (A,t[j])  := t[j] + a[j]*b[i] + A with i = " & $i & ", j = " & $j
      if i == 0 and j == 0:
        ctx.mulx t[1], t[0], w[0], rdx
      elif i == 0:
        ctx.mulx t[j+1], rax, w[0], rdx
        if j == 1:
          ctx.add t[j], rax
        else:
          ctx.adc t[j], rax
      else:
        if j != 0:
          ctx.adcx t[j], hiM
        ctx.mulx hiM, rax, w[0], rdx
        ctx.adox t[j], hiM
      ctx.comment "    Preload j+2 step"
      rollWorkspace()
 
    # Prefetch for reduction step
    ctx.mov rdx, t[0]

    ctx.comment "Final carries"
    if i == 0:
      ctx.adc hiM, 0
    else:
      ctx.adcx z, hiM # z is 0
      ctx.adox hiM, z

    # Reduction
    # ---------
    #   m := t[0]*m0ninv mod W
    # 	C,_ := t[0] + m*M[0]
    # 	for j=1 to N-1
    # 		(C,t[j-1]) := t[j] + m*M[j] + C
    #   t[N-1] = C + A

    # w = [M₀, M₁]
    # prefetch = [M₂, M₃, M₄, M₅, a₀, a₁, a₂, a₃, a₄, a₅, M₀, M₁]

    # m = t[0] * m0ninv mod 2ʷ
    ctx.comment "  Reduction"
    ctx.comment "  m = t[0] * m0ninv mod 2ʷ"
    ctx.imul rdx, m0ninv

    # Clear carry flags and zero z
    ctx.`xor` z, z

    # C,_ := t[0] + m*M[0]
    ctx.comment "  C,_ := t[0] + m*M[0]"
    ctx.mulx z, rax, w[0], rdx
    # Prefetch
    rollWorkspace()
    ctx.adcx rax, t[0] # set the carry flag for the future ADCX
    ctx.mov  t[0], z
    ctx.mov  z, 0      # zero z without upsetting the carry flag

    # for j=1 to N-1
    #   (S,t[j-1]) := t[j] + m*M[j] + S
    ctx.comment "  for j=1 to N-1"
    ctx.comment "    (S,t[j-1]) := t[j] + m*M[j] + S"
    for j in 1 ..< N:
      ctx.adcx t[j-1], t[j]
      ctx.mulx t[j], rax, w[0], rdx
      rollWorkspace()
      ctx.adox t[j-1], rax

    # Prefetch next iteration
    if i+1 < N:
      ctx.mov rdx, b[i+1]

    # Last carries
    # t[N-1] = A + C
    ctx.comment "  Reduction carry "
    ctx.adcx hiM, z # z is zero
    ctx.adox t[N-1], hiM

    # w = [a₀, a₁]
    # prefetch = [a₂, a₃, a₄, a₅, M₀, M₁, M₂, M₃, M₄, M₅, a₀, a₁]

  # --------------------------

  result.add ctx.generate

func montMul_CIOS_sparebit_asm_adx_bmi2*(r: var Limbs, a, b, M: Limbs, m0ninv: BaseType) =
  ## Constant-time modular multiplication
  ## Requires the prime modulus to have a spare bit in the representation. (Hence if using 64-bit words and 4 words, to be at most 255-bit)
  var t{.noInit.}: typeof(r)
  montMul_CIOS_sparebit_adx_bmi2_gen(t, a, b, M, m0ninv)

  # Map from [0, 2p) to [0, p)
  var scratch{.noInit.}: typeof(r)
  r.finalSub_gen(a, M, scratch, mayCarry = false)

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
