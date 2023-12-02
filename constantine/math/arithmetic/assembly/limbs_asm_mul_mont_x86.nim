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
  ./limbs_asm_modular_x86,
  ./limbs_asm_redc_mont_x86,
  ./limbs_asm_mul_x86

# ############################################################
#
#        Assembly implementation of finite fields
#
# ############################################################

static: doAssert UseASM_X86_64

# Necessary for the compiler to find enough registers
{.localPassC:"-fomit-frame-pointer".}  # (enabled at -O1)
{.localPassC:"-fno-sanitize=address".} # need 15 registers out of 16 (1 reserved for stack pointer, none available for Address Sanitizer)

# Montgomery multiplication
# ------------------------------------------------------------
# Fallback when no ADX and BMI2 support (MULX, ADCX, ADOX)
macro mulMont_CIOS_sparebit_gen[N: static int](
        r_PIR: var Limbs[N], a_PIR, b_PIR,
        M_MEM: Limbs[N], m0ninv_REG: BaseType,
        skipFinalSub: static bool): untyped =
  ## Generate an optimized Montgomery Multiplication kernel
  ## using the CIOS method
  ##
  ## The multiplication and reduction are further merged in the same loop
  ##
  ## This requires the most significant word of the Modulus
  ##   M[^1] < high(SecretWord) shr 1 (i.e. less than 0b01111...1111)
  ## https://hackmd.io/@gnark/modular_multiplication

  # No register spilling handling
  doAssert N <= 6, "The Assembly-optimized montgomery multiplication requires at most 6 limbs."

  result = newStmtList()

  var ctx = init(Assembler_x86, BaseType)
  let
    scratchSlots = 6

    # We could force M as immediate by specializing per moduli
    M = asmArray(M_MEM, N, MemOffsettable, asmInput)
    # If N is too big, we need to spill registers. TODO.
    tSym = ident"t"
    t = asmArray(tSym, N, ElemsInReg, asmOutputEarlyClobber)
    # MultiPurpose Register slots
    scratchSym = ident"scratch"
    scratch = asmArray(scratchSym, scratchSlots, ElemsInReg, asmInputOutputEarlyClobber)

    # MUL requires RAX and RDX

    m0ninv = asmValue(m0ninv_REG, Mem, asmInput)

    # We're really constrained by register and somehow setting as memory doesn't help
    # So we store the result `r` in the scratch space and then reload it in RDX
    # before the scratchspace is used in final substraction
    a = scratch[0].asArrayAddr(a_PIR, len = N, memIndirect = memRead) # Store the `a` operand
    b = scratch[1].asArrayAddr(b_PIR, len = N, memIndirect = memRead) # Store the `b` operand
    A = scratch[2]                      # High part of extended precision multiplication
    C = scratch[3]
    m = scratch[4]                      # Stores (t[0] * m0ninv) mod 2ʷ
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

  result.add quote do:
    static: doAssert: sizeof(SecretWord) == sizeof(ByteAddress)

    var `tSym`{.noInit, used.}: typeof(`r_PIR`)
    # Assumes 64-bit limbs on 64-bit arch (or you can't store an address)
    var `scratchSym` {.noInit.}: Limbs[`scratchSlots`]
    `scratchSym`[0] = cast[SecretWord](`a_PIR`[0].unsafeAddr)
    `scratchSym`[1] = cast[SecretWord](`b_PIR`[0].unsafeAddr)
    `scratchSym`[5] = cast[SecretWord](`r_PIR`[0].unsafeAddr)

  # Algorithm
  # -----------------------------------------
  # for i=0 to N-1
  #   (A, t[0]) <- a[0] * b[i] + t[0]
  #    m        <- (t[0] * m0ninv) mod 2ʷ
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
    ctx.mov rax, a[0]
    ctx.mul rdx, rax, b[i], rax
    if i == 0: # overwrite t[0]
      ctx.mov t[0], rax
    else:      # Accumulate in t[0]
      ctx.add t[0], rax
      ctx.adc rdx, 0
    ctx.mov A, rdx

    # m        <- (t[0] * m0ninv) mod 2ʷ
    ctx.mov m, m0ninv
    ctx.imul m, t[0]

    # (C, _)    <- m * M[0] + t[0]
    ctx.`xor` C, C
    ctx.mov rax, M[0]
    ctx.mul rdx, rax, m, rax
    ctx.add rax, t[0]
    ctx.adc C, rdx

    for j in 1 ..< N:
      # (A, t[j])   <- a[j] * b[i] + A + t[j]
      ctx.mov rax, a[j]
      ctx.mul rdx, rax, b[i], rax
      if i == 0:
        ctx.mov t[j], A
      else:
        ctx.add t[j], A
        ctx.adc rdx, 0
      ctx.`xor` A, A
      ctx.add t[j], rax
      ctx.adc A, rdx

      # (C, t[j-1]) <- m * M[j] + C + t[j]
      ctx.mov rax, M[j]
      ctx.mul rdx, rax, m, rax
      ctx.add C, t[j]
      ctx.adc rdx, 0
      ctx.add C, rax
      ctx.adc rdx, 0
      ctx.mov t[j-1], C
      ctx.mov C, rdx

    ctx.add A, C
    ctx.mov t[N-1], A

  ctx.mov rax, r # move r away from scratchspace that will be used for final substraction
  let r2 = rax.asArrayAddr(r_PIR, len = N, memIndirect = memWrite)

  if skipFinalSub:
    for i in 0 ..< N:
      ctx.mov r2[i], t[i]
  else:
    ctx.finalSubNoOverflowImpl(r2, t, M, scratch)
  result.add ctx.generate()

func mulMont_CIOS_sparebit_asm*(r: var Limbs, a, b, M: Limbs, m0ninv: BaseType, skipFinalSub: static bool = false) =
  ## Constant-time Montgomery multiplication
  ## If "skipFinalSub" is set
  ## the result is in the range [0, 2M)
  ## otherwise the result is in the range [0, M)
  ##
  ## This procedure can only be called if the modulus doesn't use the full bitwidth of its underlying representation
  r.mulMont_CIOS_sparebit_gen(a, b, M, m0ninv, skipFinalSub)

# Montgomery Squaring
# ------------------------------------------------------------

func squareMont_CIOS_asm*[N](
       r: var Limbs[N],
       a, M: Limbs[N],
       m0ninv: BaseType,
       spareBits: static int, skipFinalSub: static bool) =
  ## Constant-time modular squaring
  var r2x {.noInit.}: Limbs[2*N]
  square_asm(r2x, a)
  r.redcMont_asm(r2x, M, m0ninv, spareBits, skipFinalSub)

# Montgomery Sum of Products
# ------------------------------------------------------------

macro sumprodMont_CIOS_spare2bits_gen[N, K: static int](
        r_PIR: var Limbs[N], a_PIR, b_PIR: array[K, Limbs[N]],
        M_MEM: Limbs[N], m0ninv_REG: BaseType,
        skipFinalSub: static bool): untyped =
  ## Generate an optimized Montgomery merged sum of products ⅀aᵢ.bᵢ kernel
  ## using the CIOS method
  ##
  ## This requires 2 spare bits in the most significant word
  ## so that we can skip the intermediate reductions

  # No register spilling handling
  doAssert N <= 6, "The Assembly-optimized montgomery multiplication requires at most 6 limbs."

  doAssert K <= 8, "we cannot sum more than 8 products"
  # Bounds:
  # 1. To ensure mapping in [0, 2p), we need ⅀aᵢ.bᵢ <=pR
  #    for all intent and purposes this is true since aᵢ.bᵢ is:
  #    if reduced inputs: (p-1).(p-1) = p²-2p+1 which would allow more than p sums
  #    if unreduced inputs: (2p-1).(2p-1) = 4p²-4p+1,
  #    with 4p < R due to the 2 unused bits constraint so more than p sums are allowed
  # 2. We have a high-word tN to accumulate overflows.
  #    with 2 unused bits in the last word,
  #    the multiplication of two last words will leave 4 unused bits
  #    enough for accumulating 8 additions and overflow.

  result = newStmtList()

  var ctx = init(Assembler_x86, BaseType)
  let
    scratchSlots = 6

    # We could force M as immediate by specializing per moduli
    M = asmArray(M_MEM, N, MemOffsettable, asmInput)
    # If N is too big, we need to spill registers. TODO.
    tSym = ident"t"
    t = asmArray(tSym, N, ElemsInReg, asmOutputEarlyClobber)
    # MultiPurpose Register slots
    scratchSym = ident"scratch"
    scratch = asmArray(scratchSym, scratchSlots, ElemsInReg, asmInputOutputEarlyClobber)

    # MUL requires RAX and RDX

    m0ninv = asmValue(m0ninv_REG, Mem, asmInput)

    # We're really constrained by register and somehow setting as memory doesn't help
    # So we store the result `r` in the scratch space and then reload it in RDX
    # before the scratchspace is used in final substraction
    a = scratch[0].as2dArrayAddr(a_PIR, rows = K, cols = N, memIndirect = memRead) # Store the `a` operand
    b = scratch[1].as2dArrayAddr(b_PIR, rows = K, cols = N, memIndirect = memRead) # Store the `b` operand
    tN = scratch[2]                                  # High part of extended precision multiplication
    C = scratch[3]                                   # Carry during reduction step
    r = scratch[4]                                   # Stores the `r` operand
    S = scratch[5]                                   # Mul step: Stores the carry A
                                                     # Red step: Stores (t[0] * m0ninv) mod 2ʷ

  # Registers used:
  # - 1 for `M`
  # - 6 for `t`     (at most)
  # - 6 for `scratch`
  # - 2 for RAX and RDX
  # Total 15 out of 16
  # We can save 1 by hardcoding M as immediate (and m0ninv)
  # but this prevent reusing the same code for multiple curves like BLS12-377 and BLS12-381
  # We might be able to save registers by having `r` and `M` be memory operand as well
  result.add quote do:
    static: doAssert: sizeof(SecretWord) == sizeof(ByteAddress)

    var `tsym`{.noInit, used.}: typeof(`r_PIR`)
    # Assumes 64-bit limbs on 64-bit arch (or you can't store an address)
    var `scratchSym` {.noInit.}: Limbs[`scratchSlots`]
    `scratchSym`[0] = cast[SecretWord](`a_PIR`[0][0].unsafeAddr)
    `scratchSym`[1] = cast[SecretWord](`b_PIR`[0][0].unsafeAddr)
    `scratchSym`[4] = cast[SecretWord](`r_PIR`[0].unsafeAddr)

  # Algorithm
  # -----------------------------------------
  # for i=0 to N-1
  #   tN := 0
  #   for k=0 to K-1
  #     A := 0
  #     for j=0 to N-1
  # 		  (A,t[j])  := t[j] + a[k][j]*b[k][i] + A
  #     tN += A
  #   m := t[0]*m0ninv mod W
  # 	C,_ := t[0] + m*M[0]
  # 	for j=1 to N-1
  # 		(C,t[j-1]) := t[j] + m*M[j] + C
  #   t[N-1] = tN + C

  # No register spilling handling
  doAssert N <= 6, "The Assembly-optimized montgomery multiplication requires at most 6 limbs."

  for i in 0 ..< N:
    # Multiplication step
    ctx.comment "  Multiplication step"
    ctx.comment "  tN = 0"
    ctx.`xor` tN, tN
    for k in 0 ..< K:
      template A: untyped = S

      ctx.comment "    A = 0"
      ctx.`xor` A, A
      ctx.comment "      (A,t[0])  := t[0] + a[k][0]*b[k][i] + A"
      ctx.mov rax, a[k, 0]
      ctx.mul rdx, rax, b[k, i], rax
      if i == 0 and k == 0: # First accumulation, overwrite t[0]
        ctx.mov t[0], rax
      else:                 # Accumulate in t[0]
        ctx.add t[0], rax
        ctx.adc rdx, 0
      ctx.mov A, rdx

      for j in 1 ..< N:
        ctx.comment "        (A,t[j])  := t[j] + a[k][j]*b[k][i] + A"
        ctx.mov rax, a[k, j]
        ctx.mul rdx, rax, b[k, i], rax
        if i == 0 and k == 0: # First accumulation, overwrite t[0]
          ctx.mov t[j], A
        else:                 # Accumulate in t[0]
          ctx.add t[j], A
          ctx.adc rdx, 0
        ctx.`xor` A, A
        ctx.add t[j], rax
        ctx.adc A, rdx

      ctx.comment "    tN += A"
      ctx.add tN, A

    # Reduction step
    ctx.comment "  Reduction step"
    template m: untyped = S
    ctx.comment "  m := t[0]*m0ninv mod 2ʷ"
    ctx.mov rax, m0ninv
    ctx.imul rax, t[0]
    ctx.mov m, rax
    ctx.comment "  C,_ := t[0] + m*M[0]"
    ctx.`xor` C, C
    ctx.mul rdx, rax, M[0], rax
    ctx.add rax, t[0]
    ctx.adc C, rdx

    for j in 1 ..< N:
      ctx.comment "    (C,t[j-1]) := t[j] + m*M[j] + C"
      ctx.mov rax, M[j]
      ctx.mul rdx, rax, m, rax
      ctx.add C, t[j]
      ctx.adc rdx, 0
      ctx.add C, rax
      ctx.adc rdx, 0
      ctx.mov t[j-1], C
      ctx.mov C, rdx

    ctx.comment "t[N-1] = tN + C"
    ctx.add tN, C
    ctx.mov t[N-1], tN


  ctx.mov rax, r # move r away from scratchspace that will be used for final substraction
  let r2 = rax.asArrayAddr(r_PIR, len = N, memIndirect = memWrite)

  if skipFinalSub:
    ctx.comment "  Copy result"
    for i in 0 ..< N:
      ctx.mov r2[i], t[i]
  else:
    ctx.comment "  Final substraction"
    ctx.finalSubNoOverflowImpl(
      r2, t, M,
      scratch)
  result.add ctx.generate()

func sumprodMont_CIOS_spare2bits_asm*[N, K: static int](
        r: var Limbs[N], a, b: array[K, Limbs[N]],
        M: Limbs[N], m0ninv: BaseType,
        skipFinalSub: static bool) =
  ## Sum of products ⅀aᵢ.bᵢ in the Montgomery domain
  ## If "skipFinalSub" is set
  ## the result is in the range [0, 2M)
  ## otherwise the result is in the range [0, M)
  ##
  ## This procedure can only be called if the modulus doesn't use the full bitwidth of its underlying representation
  r.sumprodMont_CIOS_spare2bits_gen(a, b, M, m0ninv, skipFinalSub)