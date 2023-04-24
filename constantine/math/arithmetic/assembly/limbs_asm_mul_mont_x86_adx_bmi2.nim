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
  ./limbs_asm_redc_mont_x86_adx_bmi2,
  ./limbs_asm_mul_x86_adx_bmi2

# ############################################################
#
#        Assembly implementation of finite fields
#
# ############################################################

static: doAssert UseASM_X86_64

# MULX/ADCX/ADOX
{.localPassC:"-madx -mbmi2".}
# Necessary for the compiler to find enough registers
{.localPassC:"-fomit-frame-pointer".}  # (enabled at -O1)
{.localPassC:"-fno-sanitize=address".} # need 15 registers out of 16 (1 reserved for stack pointer, none available for Address Sanitizer)

# Montgomery Multiplication
# ------------------------------------------------------------

proc mulx_by_word(
       ctx: var Assembler_x86,
       hi: Operand,
       t: OperandArray,
       a: Operand, # Pointer in scratchspace
       word0: Operand,
       lo: Operand) =
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
       lo: Operand) =
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
       lo: Operand or Register,
       S: Operand) =
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

macro mulMont_CIOS_sparebit_adx_gen[N: static int](
        r_PIR: var Limbs[N], a_PIR, b_PIR,
        M_MEM: Limbs[N], m0ninv_REG: BaseType,
        skipFinalSub: static bool): untyped =
  ## Generate an optimized Montgomery Multiplication kernel
  ## using the CIOS method
  ## This requires the most significant word of the Modulus
  ##   M[^1] < high(SecretWord) shr 1 (i.e. less than 0b01111...1111)
  ## https://hackmd.io/@gnark/modular_multiplication

  # No register spilling handling
  doAssert N <= 6, "The Assembly-optimized montgomery multiplication requires at most 6 limbs."

  result = newStmtList()

  var ctx = init(Assembler_x86, BaseType)
  let
    scratchSlots = 6

    r = asmArray(r_PIR, N, PointerInReg, asmInputOutputEarlyClobber, memIndirect = memWrite) # MemOffsettable is the better constraint but compilers say it is impossible. Use early clobber to ensure it is not affected by constant propagation at slight pessimization (reloading it). # Changing that to MemOffsetable triggers an error in negmod in test_bindings. Missing clobber?
    # We could force M as immediate by specializing per moduli
    M = asmArray(M_MEM, N, MemOffsettable, asmInput)
    # If N is too big, we need to spill registers. TODO.
    tSym = ident"t"
    t = asmArray(tSym, N, ElemsInReg, asmOutputEarlyClobber)
    # MultiPurpose Register slots
    scratchSym = ident"scratch"
    scratch = asmArray(scratchSym, scratchSlots, ElemsInReg, asmInputOutputEarlyClobber)

    # MULX requires RDX as well

    a = scratch[0].asArrayAddr(a_PIR, len = N, memIndirect = memRead) # Store the `a` operand
    b = scratch[1].asArrayAddr(b_PIR, len = N, memIndirect = memRead) # Store the `b` operand
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

  result.add quote do:
    static: doAssert: sizeof(SecretWord) == sizeof(ByteAddress)

    var `tsym`{.noInit, used.}: typeof(`r_PIR`)
    # Assumes 64-bit limbs on 64-bit arch (or you can't store an address)
    var `scratchSym` {.noInit.}: Limbs[`scratchSlots`]
    `scratchSym`[0] = cast[SecretWord](`a_PIR`[0].unsafeAddr)
    `scratchSym`[1] = cast[SecretWord](`b_PIR`[0].unsafeAddr)
    `scratchSym`[4] = SecretWord `m0ninv_REG`

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
        C)
    else:
      ctx.mulaccx_by_word(
        A, t,
        a, i,
        b[i],
        C)

    ctx.partialRedx(
      A, t,
      M, m0ninv,
      lo, C)

  if skipFinalSub:
    for i in 0 ..< N:
      ctx.mov r[i], t[i]
  else:
    ctx.finalSubNoOverflowImpl(
      r, t, M,
      scratch)

  result.add ctx.generate()

func mulMont_CIOS_sparebit_asm_adx*(r: var Limbs, a, b, M: Limbs, m0ninv: BaseType, skipFinalSub: static bool = false) =
  ## Constant-time Montgomery multiplication
  ## If "skipFinalSub" is set
  ## the result is in the range [0, 2M)
  ## otherwise the result is in the range [0, M)
  ##
  ## This procedure can only be called if the modulus doesn't use the full bitwidth of its underlying representation
  r.mulMont_CIOS_sparebit_adx_gen(a, b, M, m0ninv, skipFinalSub)

# Montgomery Squaring
# ------------------------------------------------------------

func squareMont_CIOS_asm_adx*[N](
       r: var Limbs[N],
       a, M: Limbs[N],
       m0ninv: BaseType,
       spareBits: static int, skipFinalSub: static bool) =
  ## Constant-time modular squaring
  var r2x {.noInit.}: Limbs[2*N]
  r2x.square_asm_adx(a)
  r.redcMont_asm_adx(r2x, M, m0ninv, spareBits, skipFinalSub)

# Montgomery Sum of Products
# ------------------------------------------------------------

macro sumprodMont_CIOS_spare2bits_adx_gen[N, K: static int](
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

    # MULX requires RDX as well

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
      ctx.mov rdx, b[k, i]
      if i == 0 and k == 0: # First accumulation, overwrite t[0]
        ctx.mulx t[1], t[0], a[k, 0], rdx
      else:                 # Accumulate in t[0]
        ctx.mulx A, rax, a[k, 0], rdx
        ctx.adcx t[0], rax
        ctx.adox t[1], A

      for j in 1 ..< N-1:
        ctx.comment "        (A,t[j])  := t[j] + a[k][j]*b[k][i] + A"
        if i == 0 and k == 0:
          ctx.mulx t[j+1], rax, a[k, j], rdx
          if j == 1:
            ctx.add t[j], rax
          else:
            ctx.adc t[j], rax
        else:
          ctx.mulx A, rax, a[k, j], rdx
          ctx.adcx t[j], rax
          ctx.adox t[j+1], A

      # Last limb
      ctx.mulx A, rax, a[k, N-1], rdx
      if i == 0 and k == 0:
        ctx.adc t[N-1], rax
        ctx.comment "    tN += A"
        ctx.adc tN, A
      else:
        ctx.adcx t[N-1], rax
        ctx.comment "    tN += A"
        ctx.mov  rdx, 0 # Set to 0 without clearing flags
        ctx.adox tN, A
        ctx.adcx tN, rdx

    # Reduction step
    ctx.partialRedx(
      tN, t,
      M, m0ninv,
      rax, C)

  ctx.mov rax, r # move r away from scratchspace that will be used for final substraction
  let r2 = rax.asArrayAddr(r_PIR, len = N, memIndirect = memWrite)

  if skipFinalSub:
    ctx.comment "  Copy result"
    for i in 0 ..< N:
      ctx.mov r2[i], t[i]
  else:
    ctx.comment "  Final substraction"
    ctx.finalSubNoOverflowImpl(r2, t, M, scratch)
  result.add ctx.generate()

func sumprodMont_CIOS_spare2bits_asm_adx*[N, K: static int](
        r: var Limbs[N], a, b: array[K, Limbs[N]],
        M: Limbs[N], m0ninv: BaseType,
        skipFinalSub: static bool) =
  ## Sum of products ⅀aᵢ.bᵢ in the Montgomery domain
  ## If "skipFinalSub" is set
  ## the result is in the range [0, 2M)
  ## otherwise the result is in the range [0, M)
  ##
  ## This procedure can only be called if the modulus doesn't use the full bitwidth of its underlying representation
  r.sumprodMont_CIOS_spare2bits_adx_gen(a, b, M, m0ninv, skipFinalSub)