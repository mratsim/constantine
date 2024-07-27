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
  constantine/platforms/abstractions,
  ./limbs_asm_mul_x86_adx_bmi2,
  ./limbs_asm_crandall_x86

# ############################################################
#
#        Assembly implementation of finite fields
#
# ############################################################


static: doAssert UseASM_X86_32

# Crandall reduction
# ------------------------------------------------------------

macro reduceCrandallPartial_adx_gen*[N: static int](
       r_PIR: var array[N, SecretWord],
       a_MEM: array[N*2, SecretWord],
       m: static int, c: static BaseType) =

  result = newStmtList()
  var ctx = init(Assembler_x86, BaseType)

  ctx.comment "Crandall reduction - Partial"
  ctx.comment "----------------------------"

  let
    r = asmArray(r_PIR, N, PointerInReg, asmInputOutputEarlyClobber, memIndirect = memWrite) # MemOffsettable is the better constraint but compilers say it is impossible. Use early clobber to ensure it is not affected by constant propagation at slight pessimization (reloading it).
    a = asmArray(a_MEM, 2*N, MemOffsettable, asmInput)

    tSym = ident"t"
    t = asmArray(tSym, N, ElemsInReg, asmOutputEarlyClobber)

    hiSym = ident"hi"
    hi = asmValue(hiSym, Reg, asmOutputEarlyClobber)

    csSym = ident"cs"
    cs = asmValue(csSym, Reg, asmOutputEarlyClobber)

    S =(N*WordBitWidth - m)
    csImm = c shl S

  # Prologue
  # ---------
  result.add quote do:
    var `hiSym`{.noinit.}, `csSym`{.noinit.}: BaseType
    var `tSym`{.noInit.}: typeof(`r_PIR`)

  ctx.`xor` rax, rax
  ctx.mov cs, csImm

  # Algorithm
  # ---------
  ctx.comment "First reduction pass"
  ctx.comment "--------------------"
  ctx.comment "(hi, r₀) <- aₙ*cs + a₀"
  ctx.mov  rdx, cs
  ctx.mov  t[0], a[0]
  for i in 0 ..< N:
    # TODO: should we alternate rax with another register?
    #       to deal with false dependencies?
    ctx.comment "  (hi, rᵢ) <- aᵢ₊ₙ*cs + aᵢ + hi"
    if i != N-1:
      ctx.mov t[i+1], a[i+1]
    ctx.mulx hi, rax, a[N+i], rdx
    ctx.adox t[i], rax
    if i != N-1:
      ctx.adcx t[i+1], hi

  # Final carries
  ctx.mov rdx, 0
  ctx.adcx hi, rdx
  ctx.adox hi, rdx

  # The first reduction pass may carry in `hi`
  # which would be hi*2ʷⁿ ≡ hi*2ʷⁿ⁻ᵐ*c (mod p)
  #                       ≡ hi*cs (mod p)
  ctx.shld  hi, t[N-1], S
  # High-bits have been "carried" to `hi`, cancel them in r[N-1].
  # Note: there might be up to `c` not reduced.
  ctx.mov rax, BaseType(MaxWord) shr S
  ctx.`and` t[N-1], rax

  # Partially reduce to up to `m` bits
  # We need to fold what's beyond `m` bits
  # by repeatedly multiplying it by cs
  # We distinguish 2 cases:
  # 1. Folding (N..2N)*cs onto 0..N
  #    may overflow and a 3rd folding is necessary
  # 2. Folding (N..2N)*cs onto 0..N
  #    may not overflow and 2 foldings are all we need.
  #    This is possible:
  #    - if we don't use the full 2ʷⁿ
  #      for example we use 255 bits out of 256 available
  #    - And (2ʷⁿ⁻ᵐ*c)² < 2ʷ
  #
  # There is a 3rd case that we don't handle
  # c > 2ʷ, for example secp256k1 on 32-bit

  if N*WordBitWidth == m: # Secp256k1 only according to eprint/iacr 2018/985
    # We shifted hi by 2ʷⁿ⁻ᵐ so no need for cs = 2ʷⁿ⁻ᵐc
    # we just need c
    ctx.mov rdx, c

    # Second pass
    ctx.mulx hi, rax, hi, rdx
    ctx.add t[0], rax
    ctx.mov rax, 0
    ctx.adc t[1], hi
    for i in 2 ..< N:
      ctx.adc t[i], 0
      ctx.mov r[i], t[i]

    # Third pass
    ctx.setc rax # This only sets the low 8 bits, need extra zero-out
    ctx.mulx hi, rax, rax, rdx
    ctx.add  t[0], rax
    ctx.mov  r[0], t[0]
    ctx.adc  t[1], hi
    ctx.mov  r[1], t[1]

  # We want to ensure that cs² < 2³² on 64-bit or 2¹⁶ on 32-bit
  # But doing unsigned cs² may overflow, so we sqrt the rhs instead
  elif csImm.uint64 < (1'u64 shl (WordBitWidth shr 1)) - 1:

    # Second pass

    # hi < cs, and cs² < 2ʷ (2³² on 32-bit or 2⁶⁴ on 64-bit)
    # hence hi *= c cannot overflow
    ctx.imul rax, hi, c
    ctx.add t[0], rax
    ctx.mov r[0], t[0]
    for i in 1 ..< N:
      ctx.adc t[i], 0
      ctx.mov r[i], t[i]

  else:
    error "Not implemented"

  # Code generation
  result.add ctx.generate()

func reduceCrandallPartial_asm_adx*[N: static int](
      r: var Limbs[N],
      a: array[2*N, SecretWord],
      m: static int, c: static SecretWord) =
  ## Partial Reduction modulo p
  ## with p with special form 2ᵐ-c
  ## called "Crandall prime" or Pseudo-Mersenne Prime in the litterature
  ##
  ## This is a partial reduction that reduces down to
  ## 2ᵐ, i.e. it fits in the same amount of word by p
  ## but values my be up to p+c
  ##
  ## Crandal primes allow fast reduction from the fact that
  ##        2ᵐ-c ≡  0     (mod p)
  ##   <=>  2ᵐ   ≡  c     (mod p)
  ##   <=> a2ᵐ+b ≡ ac + b (mod p)
  r.reduceCrandallPartial_adx_gen(a, m, BaseType(c))

# Crandall Multiplication and squaring
# ------------------------------------------------------------

func mulCranPartialReduce_asm_adx*[N: static int](
        r: var Limbs[N],
        a, b: Limbs[N],
        m: static int, c: static SecretWord) =
  var r2 {.noInit.}: Limbs[2*N]
  r2.mul_asm_adx(a, b)
  r.reduceCrandallPartial_asm_adx(r2, m, c)

func squareCranPartialReduce_asm_adx*[N: static int](
        r: var Limbs[N],
        a: Limbs[N],
        m: static int, c: static SecretWord) =
  var r2 {.noInit.}: Limbs[2*N]
  r2.square_asm_adx(a)
  r.reduceCrandallPartial_asm_adx(r2, m, c)

func mulCran_asm_adx*[N: static int](
        r: var Limbs[N],
        a, b, p: Limbs[N],
        m: static int, c: static SecretWord) =
  r.mulCranPartialReduce_asm_adx(a, b, m, c)
  r.reduceCrandallFinal_asm(p)

func squareCran_asm_adx*[N: static int](
        r: var Limbs[N],
        a, p: Limbs[N],
        m: static int, c: static SecretWord) =
  r.squareCranPartialReduce_asm_adx(a, m, c)
  r.reduceCrandallFinal_asm(p)
