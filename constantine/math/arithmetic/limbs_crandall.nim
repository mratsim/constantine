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

  # Partially reduce to up to `bits`
  # We need to fold what's beyond `bits`
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

  when N*WordBitWidth == bits: # Secp256k1 only according to eprint/iacr 2018/985
    var t0, t1: SecretWord
    var carry: Carry

    # Second pass
    mul(t1, t0, hi, c)
    addC(carry, r[0], r[0], t0, Carry(0))
    addC(carry, r[1], r[1], t1, carry)
    staticFor i, 2, N:
      addC(carry, r[i], r[i], Zero, carry)

    # Third pass - the high-word to fold can only be bits+1
    mul(t1, t0, SecretWord(carry), c)
    addC(carry, r[0], r[0], t0, Carry(0))
    addC(carry, r[1], r[1], t1, carry)

  # We want to ensure that cs² < 2³² on 64-bit or 2¹⁶ on 32-bit
  # But doing unsigned cs² may overflow, so we sqrt the rhs instead
  elif uint64(cs) < (1'u64 shl (WordBitWidth shr 1)) - 1:
    var carry: Carry

    # Second pass

    # hi < cs, and cs² < 2ʷ (2³² on 32-bit or 2⁶⁴ on 64-bit)
    # hence hi *= c cannot overflow
    hi *= c
    addC(carry, r[0], r[0], hi, Carry(0))
    staticFor i, 1, N:
      addC(carry, r[i], r[i], Zero, carry)

  else:
    {.error: "Not implemented".}

func reduce_crandall_final_impl[N: static int](
        a: var Limbs[N],
        bits: static int,
        c: static SecretWord) =
  ## Final Reduction modulo p
  ## with p with special form 2ᵐ-c
  ## called "Crandall prime" or Pseudo-Mersenne Prime in the litterature
  ##
  ## This reduces `a` from [0, 2ᵐ) to [0, 2ᵐ-c)
  const S = (N*WordBitWidth - bits)
  const top = MaxWord shr S
  static: doAssert 0 <= S and S < WordBitWidth

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

# Lazily reduced arithmetic
# ------------------------------------------------------------

# We can use special lazily reduced arithmetic
# where reduction is only done when we overflow 2ʷⁿ
# with w the word bitwidth and n the number of words
# to represent p.
# For example for Curve25519, p = 2²⁵⁵-19 and 2ʷⁿ=2²⁵⁶
# Hence reduction will only happen when overflowing 2²⁵⁶ bits
#
# However:
# - Restricting it to mul/squaring in addchain
#   makes it consistent with generic Montgomery representation
# - We don't really gain something for addition and substraction
#   as modular addition needs:
#   1. One pass of add-with-carry
#   2. One pass of sub-with-borrow
#   3. One pass of conditional mov
#   And lazily reduced needs
#   the same first 2 pass and replace the third with
#   masking + single addition
#   Total number of instruction doesn't seem to change
#   and conditional moves can be issued 2 per cycle
#   so we save ~1 clock cycle

func sum_crandall_impl[N: static int](
        r: var Limbs[N], a, b: Limbs[N],
        bits: int,
        c: SecretWord) {.used.} =
  ## Lazily reduced addition
  ## Proof-of-concept. Currently unused.
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
  # to higher limbs
  r[0] += mask2 and cs
