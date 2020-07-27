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
  ./limbs,
  ./limbs_asm_montred_x86

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

# Necessary for the compiler to find enough registers (enabled at -O1)
{.localPassC:"-fomit-frame-pointer".}

# Montgomery multiplication
# ------------------------------------------------------------
# Fallback when no ADX and BMI2 support (MULX, ADCX, ADOX)
macro montMul_CIOS_nocarry_gen[N: static int](r_MM: var Limbs[N], a_MM, b_MM, M_MM: Limbs[N], m0ninv_MM: BaseType): untyped =
  ## Generate an optimized Montgomery Multiplication kernel
  ## using the CIOS method
  ##
  ## The multiplication and reduction are further merged in the same loop
  ##
  ## This requires the most significant word of the Modulus
  ##   M[^1] < high(SecretWord) shr 2 (i.e. less than 0b00111...1111)
  ## https://hackmd.io/@zkteam/modular_multiplication

  result = newStmtList()

  var ctx = init(Assembler_x86, BaseType)
  let
    scratchSlots = max(N, 6)

    # We could force M as immediate by specializing per moduli
    M = init(OperandArray, nimSymbol = M_MM, N, PointerInReg, Input)
    # If N is too big, we need to spill registers. TODO.
    t = init(OperandArray, nimSymbol = ident"t", N, ElemsInReg, Output_EarlyClobber)
    # MultiPurpose Register slots
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

    m0ninv = Operand(
               desc: OperandDesc(
                 asmId: "[m0ninv]",
                 nimSymbol: m0ninv_MM,
                 rm: MemOffsettable,
                 constraint: Input,
                 cEmit: "&" & $m0ninv_MM
               )
             )

    # We're really constrained by register and somehow setting as memory doesn't help
    # So we store the result `r` in the scratch space and then reload it in RDX
    # before the scratchspace is used in final substraction
    a = scratch[0].asArrayAddr(len = N) # Store the `a` operand
    b = scratch[1].asArrayAddr(len = N) # Store the `b` operand
    A = scratch[2]                      # High part of extended precision multiplication
    C = scratch[3]
    m = scratch[4]                      # Stores (t[0] * m0ninv) mod 2^w
    r = scratch[5]                      # Stores the `r` operand

  # Registers used:
  # - 1 for `M`
  # - 6 for `t`     (at most)
  # - 6 for `scratch`
  # - 2 for RAX and RDX
  # Total 15 out of 16
  # We can save 1 by hardcoding M as immediate (and m0ninv)
  # but this prevent reusing the same code for multiple curves like BLS12-377 and BLS12-381
  # We might be able to save registers by having `r` and `M` be memory operand as well

  let tsym = t.nimSymbol
  let scratchSym = scratch.nimSymbol
  let eax = rRAX.desc.nimSymbol
  let edx = rRDX.desc.nimSymbol
  result.add quote do:
    static: doAssert: sizeof(SecretWord) == sizeof(ByteAddress)

    var `tsym`: typeof(`r_MM`) # zero init
    # Assumes 64-bit limbs on 64-bit arch (or you can't store an address)
    var `scratchSym` {.noInit.}: Limbs[`scratchSlots`]
    var `eax`{.noInit.}, `edx`{.noInit.}: BaseType

    `scratchSym`[0] = cast[SecretWord](`a_MM`[0].unsafeAddr)
    `scratchSym`[1] = cast[SecretWord](`b_MM`[0].unsafeAddr)
    `scratchSym`[5] = cast[SecretWord](`r_MM`[0].unsafeAddr)

  # Algorithm
  # -----------------------------------------
  # for i=0 to N-1
  #   (A, t[0]) <- a[0] * b[i] + t[0]
  #    m        <- (t[0] * m0ninv) mod 2^w
  #   (C, _)    <- m * M[0] + t[0]
  #   for j=1 to N-1
  #     (A, t[j])   <- a[j] * b[i] + A + t[j]
  #     (C, t[j-1]) <- m * M[j] + C + t[j]
  #
  #   t[N-1] = C + A

  # No register spilling handling
  doAssert N <= 6, "The Assembly-optimized montgomery multiplication requires at most 6 limbs."

  for i in 0 ..< N:
    # (A, t[0]) <- a[0] * b[i] + t[0]
    ctx.mov rRAX, a[0]
    ctx.mul rdx, rax, b[i], rax
    if i == 0: # overwrite t[0]
      ctx.mov t[0], rRAX
    else:      # Accumulate in t[0]
      ctx.add t[0], rRAX
      ctx.adc rRDX, 0
    ctx.mov A, rRDX

    # m        <- (t[0] * m0ninv) mod 2^w
    ctx.mov m, m0ninv
    ctx.imul m, t[0]

    # (C, _)    <- m * M[0] + t[0]
    ctx.`xor` C, C
    ctx.mov rRAX, M[0]
    ctx.mul rdx, rax, m, rax
    ctx.add rRAX, t[0]
    ctx.adc C, rRDX

    for j in 1 ..< N:
      # (A, t[j])   <- a[j] * b[i] + A + t[j]
      ctx.mov rRAX, a[j]
      ctx.mul rdx, rax, b[i], rax
      if i == 0:
        ctx.mov t[j], A
      else:
        ctx.add t[j], A
        ctx.adc rRDX, 0
      ctx.`xor` A, A
      ctx.add t[j], rRAX
      ctx.adc A, rRDX

      # (C, t[j-1]) <- m * M[j] + C + t[j]
      ctx.mov rRAX, M[j]
      ctx.mul rdx, rax, m, rax
      ctx.add C, t[j]
      ctx.adc rRDX, 0
      ctx.add C, rRAX
      ctx.adc rRDX, 0
      ctx.mov t[j-1], C
      ctx.mov C, rRDX

    ctx.add A, C
    ctx.mov t[N-1], A

  ctx.mov rRDX, r
  let r2 = rRDX.asArrayAddr(len = N)

  ctx.finalSub(
    r2, t, M,
    scratch
  )

  result.add ctx.generate

func montMul_CIOS_nocarry_asm*(r: var Limbs, a, b, M: Limbs, m0ninv: BaseType) =
  ## Constant-time modular multiplication
  montMul_CIOS_nocarry_gen(r, a, b, M, m0ninv)
