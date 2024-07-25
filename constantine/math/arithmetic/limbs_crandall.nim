# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  constantine/platforms/abstractions,
  ./limbs

# No exceptions allowed
{.push raises: [], checks: off.}

# ############################################################
#
#         Multiprecision Crandall prime /
#        Pseudo-Mersenne Prime Arithmetic
#
# ############################################################
#
# Crandall primes have the form p = 2ᵐ-c
# We use special lazily reduced arithmetic
# where reduction is only done when we overflow 2ʷⁿ
# with w the word bitwidth and n the number of words
# to represent p.
# For example for Curve25519, p = 2²⁵⁵-19 and 2ʷⁿ=2²⁵⁶
# Hence reduction will only happen when overflowing 2²⁵⁶ bits

# Fast reduction
# ------------------------------------------------------------

func reduce_crandall_partial_impl[N: static int](
        r: var Limbs[N],
        a: Limbs[2*N],
        bits: static int,
        c: static SecretWord) =
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

  # In our case we split at 2ʷⁿ with w the word size (32 or 64-bit)
  # and N the number of words needed to represent the prime
  # hence  2ʷⁿ   ≡ 2ʷⁿ⁻ᵐc (mod p), we call this cs (c shifted)
  # so    a2ʷⁿ+b ≡ a2ʷⁿ⁻ᵐc + b (mod p)
  #
  # With concrete instantiations:
  # for p = 2²⁵⁵-19 (Curve25519)
  #   2²⁵⁵ ≡ 19 (mod p)
  #   2²⁵⁶ ≡ 2*19 (mod p)
  #   We rewrite the 510 bits multiplication result as
  #   a2²⁵⁶+b = a*2*19 + b (mod p)
  #
  # For Bitcoin/Ethereum, p = 2²⁵⁶-0x1000003D1 =
  #                       p = 2²⁵⁶ - (2³²+2⁹+2⁸+2⁷+2⁶+2⁴+1)
  #   2²⁵⁶ ≡ 0x1000003D1 (mod p)
  #   We rewrite the 512 bits multiplication result as
  #   a2²⁵⁶+b = a*0x1000003D1 + b (mod p)
  #
  # Note: on a w-bit architecture, c MUST be less than w-bit
  #       This is not the case for secp256k1 on 32-bit
  #       as it's c = 2³²+2⁹+2⁸+2⁷+2⁶+2⁴+1
  #       Though as multiplying by 2³² is free
  #       we can special-case the problem, if there was a
  #       32-bit platform with add-with-carry that is still a valuable target.
  #       (otherwise unsaturated arithmetic is superior)

  const S = (N*WordBitWidth - bits)
  const cs = c shl S
  static: doAssert 0 <= S and S < WordBitWidth

  var hi: SecretWord

  # First reduction pass
  # multiply high-words by c shifted and accumulate in low-words
  # assumes cs fits in a single word.

  # (hi, r₀) <- aₙ*cs + a₀
  muladd1(hi, r[0], a[N], cs, a[0])
  staticFor i, 1, N:
    # (hi, rᵢ) <- aᵢ₊ₙ*cs + aᵢ + hi
    muladd2(hi, r[i], a[i+N], cs, a[i], hi)

  # The first reduction pass may carry in `hi`
  # which would be hi*2ʷⁿ ≡ hi*2ʷⁿ⁻ᵐ*c (mod p)
  #                       ≡ hi*cs (mod p)

  # Move all extra bits to hi, i.e. double-word shift
  hi = (hi shl S) or (r[N-1] shr (WordBitWidth-S))

  # High-bit has been "carried" to `hi`, cancel it.
  # Note: there might be up to `c` not reduced.
  r[N-1] = r[N-1] and (MaxWord shr S)

  # hi*cs (mod p),
  # hi has already been shifted so we use `c` instead of `cs`
  when N*WordBitWidth == bits: # Secp256k1 only according to eprint/iacr 2018/985
    var t0, t1: SecretWord
    mul(t1, t0, hi, c)

    # Second pass
    var carry: Carry
    addC(carry, r[0], r[0], t0, Carry(0))
    addC(carry, r[1], r[1], t1, carry)
    staticFor i, 2, N:
      addC(carry, r[i], r[i], Zero, carry)

    # Third pass
    mul(t1, t0, SecretWord(carry), c)
    addC(carry, r[0], r[0], t0, Carry(0))
    addC(carry, r[1], r[1], t1, carry)

  else:
    hi *= c # Cannot overflow

    # Second pass
    var carry: Carry
    addC(carry, r[0], r[0], hi, Carry(0))
    staticFor i, 1, N:
      addC(carry, r[i], r[i], Zero, carry)

func reduce_crandall_final_impl[N: static int](
        a: var Limbs[N],
        bits: int,
        c: SecretWord) =
  ## Final Reduction modulo p
  ## with p with special form 2ᵐ-c
  ## called "Crandall prime" or Pseudo-Mersenne Prime in the litterature
  ##
  ## This reduces `a` from [0, 2ᵐ) to [0, 2ᵐ-c)
  let S = (N*WordBitWidth - bits)
  let top = MaxWord shr S
  debug: doAssert 0 <= S and S < WordBitWidth

  # 1. Substract p = 2ᵐ-c
  #    p is in the form 0x7FFF...FFFF`c` (7FFF or 3FFF or ... depending of 255-bit 254-bit ...)
  var t {.noInit.}: Limbs[N]
  var borrow: Borrow
  subB(borrow, t[0], a[0], -c, Borrow(0))
  for i in 1 ..< N-1:
    subB(borrow, t[i], a[i], MaxWord, borrow)
  when N >= 2:
    subB(borrow, t[N-1], a[N-1], top, borrow)

  # 2. If underflow, a has the proper reduced result
  #    otherwise t has the proper reduced result
  a.ccopy(t, not SecretBool(borrow))

func reduce_crandall_partial*[N: static int](
        r: var Limbs[N],
        a: Limbs[2*N],
        bits: static int,
        c: static SecretWord) =
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

  static: doAssert N*WordBitWidth >= bits
  reduce_crandall_partial_impl(r, a, bits, c)

func reduce_crandall_final*[N: static int](
        a: var Limbs[N],
        bits: static int,
        c: static SecretWord) =
  ## Final Reduction modulo p
  ## with p with special form 2ᵐ-c
  ## called "Crandall prime" or Pseudo-Mersenne Prime in the litterature
  ##
  ## This reduces `a` from [0, 2ᵐ) to [0, 2ᵐ-c)

  static: doAssert N*WordBitWidth >= bits
  reduce_crandall_final_impl(a, bits, c)

# lazily reduced arithmetic
# ------------------------------------------------------------


func sum_crandall_impl[N: static int](
        r: var Limbs[N], a, b: Limbs[N],
        bits: int,
        c: SecretWord) =

  let S = (N*WordBitWidth - bits)
  let cs = c shl S
  debug: doAssert 0 <= S and S < WordBitWidth

  let overflow1 = r.sum(a, b)
  # If there is an overflow, substract 2ˢp = 2ʷⁿ - 2ˢc
  # with w the word bitwidth and n the number of words
  # to represent p.
  # For example for Curve25519, p = 2²⁵⁵-19 and 2ʷⁿ=2²⁵⁶

  # 0x0000 if no overflow or 0xFFFF if overflow
  let mask1 = -SecretWord(overflow1)

  # 2ˢp = 2ʷⁿ - 2ˢc ≡ 2ˢc (mod p)
  let overflow2 = r.add(mask1 and cs)
  let mask2 = -SecretWord(overflow2)

  # We may carry again, but we just did -2ˢc
  # so adding back 2ˢc for the extra 2ʷⁿ bit cannot carry
  r[0] += mask2 and cs
