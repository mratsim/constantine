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
  constantine/platforms/abstractions

when UseASM_X86_64:
  import ./limbs_asm_mul_x86

# ############################################################
#
#        Assembly implementation of finite fields
#
# ############################################################


static: doAssert UseASM_X86_32

# Crandall reductions
# ------------------------------------------------------------

macro reduceCrandallPartial_gen*[N: static int](
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
  result.add quote do:
    var `hiSym`{.noinit.}, `csSym`{.noinit.}: BaseType
    var `tSym`{.noInit.}: typeof(`r_PIR`)

  ctx.`xor` hi, hi
  ctx.mov cs, csImm

  # Algorithm
  # Note: always accumulate into a register.
  #       add-carry into memory is huge pessimization

  ctx.comment "First reduction pass"
  ctx.comment "--------------------"
  ctx.comment "(hi, r₀) <- aₙ*cs + a₀"
  ctx.mov rax, a[N]
  ctx.mul rdx, rax, cs, rax
  ctx.add rax, a[0]
  ctx.mov t[0], rax
  ctx.adc hi, rdx # hi = 0
  for i in 1 ..< N:
    ctx.comment "  (hi, rᵢ) <- aᵢ₊ₙ*cs + aᵢ + hi"
    ctx.mov   rax, a[i+N]
    ctx.mul   rdx, rax, cs, rax
    ctx.add   rax, hi
    ctx.adc   rdx, 0
    ctx.`xor` hi, hi
    ctx.add   rax, a[i]
    ctx.adc   hi, rdx
    ctx.mov   t[i], rax

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
    ctx.mov cs, c

    # Second pass
    ctx.mov rax, hi
    ctx.mul rdx, rax, cs, rax
    ctx.add t[0], rax
    ctx.mov rax, 0
    ctx.adc t[1], rdx
    for i in 2 ..< N:
      ctx.adc t[i], 0
      ctx.mov r[i], t[i]

    # Third pass
    ctx.setc rax # This only sets the low 8 bits, need extra zero-out
    ctx.mul rdx, rax, cs, rax
    ctx.add t[0], rax
    ctx.mov r[0], t[0]
    ctx.adc t[1], rdx
    ctx.mov r[1], t[1]

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

func reduceCrandallPartial_asm*[N: static int](
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
  r.reduceCrandallPartial_gen(a, m, BaseType(c))

macro reduceCrandallFinal_gen*[N: static int](
      a_PIR: var Limbs[N], p_MEM: Limbs[N]) =
  ## Final Reduction modulo p
  ## with p with special form 2ᵐ-c
  ## called "Crandall prime" or Pseudo-Mersenne Prime in the litterature
  ##
  ## This reduces `a` from [0, 2ᵐ) to [0, 2ᵐ-c)

  result = newStmtList()
  var ctx = init(Assembler_x86, BaseType)

  ctx.comment "Crandall reduction - Final substraction"
  ctx.comment "---------------------------------------"

  let a =asmArray(a_PIR, N, PointerInReg, asmInputOutputEarlyClobber, memIndirect = memWrite) # MemOffsettable is the better constraint but_ec_shortw_prj_g1_sum_reduce.nimt compilers say it is impossible. Use early clobber to ensure it is not affected by constant propagation at slight pessimization (reloading it).
  let tSym = ident"t"
  let t = asmArray(tSym, N, ElemsInReg, asmOutputEarlyClobber)
  let p = asmArray(p_MEM, N, MemOffsettable, asmInput)

  result.add quote do:
    var `tsym`{.noInit.}: typeof(`a_PIR`)

  # Substract the modulus, and test a < p with the last borrow
  ctx.mov t[0], a[0]
  ctx.sub t[0], p[0]
  for i in 1 ..< N:
    ctx.mov t[i], a[i]
    ctx.sbb t[i], p[i]

  # If we borrowed it means that we were smaller than
  # the modulus and we don't need "scratch".
  var r0 = rax
  var r1 = rdx
  for i in 0 ..< N:
    ctx.mov r0, a[i]
    ctx.cmovnc r0, t[i]
    ctx.mov a[i], r0
    swap(r0, r1)

  # Codegen
  result.add ctx.generate()

func reduceCrandallFinal_asm*[N: static int](
      a: var Limbs[N], p: Limbs[N]) =
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
  a.reduceCrandallFinal_gen(p)

# Crandall Multiplication and squaring
# ------------------------------------------------------------

func mulCranPartialReduce_asm*[N: static int](
        r: var Limbs[N],
        a, b: Limbs[N],
        m: static int, c: static SecretWord) =
  static: doAssert UseASM_X86_64, "x86-32 does not have enough registers for multiplication"
  var r2 {.noInit.}: Limbs[2*N]
  r2.mul_asm(a, b)
  r.reduceCrandallPartial_asm(r2, m, c)

func squareCranPartialReduce_asm*[N: static int](
        r: var Limbs[N],
        a: Limbs[N],
        m: static int, c: static SecretWord) =
  static: doAssert UseASM_X86_64, "x86-32 does not have enough registers for squaring"
  var r2 {.noInit.}: Limbs[2*N]
  r2.square_asm(a)
  r.reduceCrandallPartial_asm(r2, m, c)

func mulCran_asm*[N: static int](
        r: var Limbs[N],
        a, b, p: Limbs[N],
        m: static int, c: static SecretWord) =
  r.mulCranPartialReduce_asm(a, b, m, c)
  r.reduceCrandallFinal_asm(p)

func squareCran_asm*[N: static int](
        r: var Limbs[N],
        a, p: Limbs[N],
        m: static int, c: static SecretWord) =
  r.squareCranPartialReduce_asm(a, m, c)
  r.reduceCrandallFinal_asm(p)
