# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  constantine/platforms/abstractions,
  ./limbs, ./limbs_extmul

when UseASM_X86_32:
  import
    ./assembly/limbs_asm_crandall_x86,
    ./assembly/limbs_asm_crandall_x86_adx_bmi2

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

func reduceCrandallPartial_impl[N: static int](
        r: var Limbs[N],
        a: array[2*N, SecretWord], # using Limbs lead to type mismatch or ICE
        m: static int,
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

  const S = (N*WordBitWidth - m)
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

  # High-bits have been "carried" to `hi`, cancel them in r[N-1].
  # Note: there might be up to `c` not reduced.
  r[N-1] = r[N-1] and (MaxWord shr S)

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

  when N*WordBitWidth == m: # Secp256k1 only according to eprint/iacr 2018/985
    var t0, t1: SecretWord
    var carry: Carry

    # Second pass
    mul(t1, t0, hi, c)
    addC(carry, r[0], r[0], t0, Carry(0))
    addC(carry, r[1], r[1], t1, carry)
    staticFor i, 2, N:
      addC(carry, r[i], r[i], Zero, carry)

    # Third pass - the high-word to fold can only be m-bits+1
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

func reduceCrandallFinal_impl[N: static int](
        a: var Limbs[N],
        p: Limbs[N]) =
  ## Final Reduction modulo p
  ## with p with special form 2ᵐ-c
  ## called "Crandall prime" or Pseudo-Mersenne Prime in the litterature
  ##
  ## This reduces `a` from [0, 2ᵐ) to [0, 2ᵐ-c)

  # 1. Substract p = 2ᵐ-c
  var t {.noInit.}: Limbs[N]
  let underflow = t.diff(a, p)

  # 2. If underflow, a has the proper reduced result
  #    otherwise t has the proper reduced result
  a.ccopy(t, not SecretBool(underflow))

func reduceCrandallFinal[N: static int](
        a: var Limbs[N],
        p: Limbs[N]) {.inline.} =
  ## Final Reduction modulo p
  ## with p with special form 2ᵐ-c
  ## called "Crandall prime" or Pseudo-Mersenne Prime in the litterature
  ##
  ## This reduces `a` from [0, 2ᵐ) to [0, 2ᵐ-c)
  when UseASM_X86_32 and a.len in {3..6}:
    a.reduceCrandallFinal_asm(p)
  else:
    a.reduceCrandallFinal_impl(p)

# High-level API
# ------------------------------------------------------------

func mulCranPartialReduce[N: static int](
        r: var Limbs[N],
        a, b: Limbs[N],
        m: static int, c: static SecretWord) {.inline.} =
  when UseASM_X86_64 and a.len in {3..6}:
    # ADX implies BMI2
    if ({.noSideEffect.}: hasAdx()):
      r.mulCranPartialReduce_asm_adx(a, b, m, c)
    else:
      r.mulCranPartialReduce_asm(a, b, m, c)
  else:
    var r2 {.noInit.}: Limbs[2*N]
    r2.prod(a, b)
    r.reduceCrandallPartial_impl(r2, m, c)

func mulCran*[N: static int](
        r: var Limbs[N],
        a, b: Limbs[N],
        p: Limbs[N],
        m: static int, c: static SecretWord,
        lazyReduce: static bool = false) {.inline.} =
  when lazyReduce:
    r.mulCranPartialReduce(a, b, m, c)
  elif UseASM_X86_64 and a.len in {3..6}:
    # ADX implies BMI2
    if ({.noSideEffect.}: hasAdx()):
      r.mulCran_asm_adx(a, b, p, m, c)
    else:
      r.mulCran_asm(a, b, p, m, c)
  else:
    var r2 {.noInit.}: Limbs[2*N]
    r2.prod(a, b)
    r.reduceCrandallPartial_impl(r2, m, c)
    r.reduceCrandallFinal_impl(p)

func squareCranPartialReduce[N: static int](
        r: var Limbs[N],
        a: Limbs[N],
        m: static int, c: static SecretWord) {.inline.} =
  when UseASM_X86_64 and a.len in {3..6}:
    # ADX implies BMI2
    if ({.noSideEffect.}: hasAdx()):
      r.squareCranPartialReduce_asm_adx(a, m, c)
    else:
      r.squareCranPartialReduce_asm(a, m, c)
  else:
    var r2 {.noInit.}: Limbs[2*N]
    r2.square(a)
    r.reduceCrandallPartial_impl(r2, m, c)

func squareCran*[N: static int](
        r: var Limbs[N],
        a: Limbs[N],
        p: Limbs[N],
        m: static int, c: static SecretWord,
        lazyReduce: static bool = false) {.inline.} =
  when lazyReduce:
    r.squareCranPartialReduce(a, m, c)
  elif UseASM_X86_64 and a.len in {3..6}:
    # ADX implies BMI2
    if ({.noSideEffect.}: hasAdx()):
      r.squareCran_asm_adx(a, p, m, c)
    else:
      r.squareCran_asm(a, p, m, c)
  else:
    var r2 {.noInit.}: Limbs[2*N]
    r2.square(a)
    r.reduceCrandallPartial_impl(r2, m, c)
    r.reduceCrandallFinal_impl(p)

# Crandall Exponentiation
# ------------------------------------------------------------
# We use fixed-window based exponentiation
# that is constant-time: i.e. the number of multiplications
# does not depend on the number of set bits in the exponents
# those are always done and conditionally copied.
#
# The exponent MUST NOT be private data (until audited otherwise)
# - Power attack on RSA, https://www.di.ens.fr/~fouque/pub/ches06.pdf
# - Flush-and-reload on Sliding window exponentiation: https://tutcris.tut.fi/portal/files/8966761/p1639_pereida_garcia.pdf
# - Sliding right into disaster, https://eprint.iacr.org/2017/627.pdf
# - Fixed window leak: https://www.scirp.org/pdf/JCC_2019102810331929.pdf
# - Constructing sliding-windows leak, https://easychair.org/publications/open/fBNC
#
# For pairing curves, this is the case since exponentiation is only
# used for inversion via the Little Fermat theorem.
# For RSA, some exponentiations uses private exponents.
#
# Note:
# - Implementation closely follows Thomas Pornin's BearSSL
# - Apache Milagro Crypto has an alternative implementation
#   that is more straightforward however:
#   - the exponent hamming weight is used as loop bounds
#   - the baseᵏ is stored at each index of a temp table of size k
#   - the baseᵏ to use is indexed by the hamming weight
#     of the exponent, leaking this to cache attacks
#   - in contrast BearSSL touches the whole table to
#     hide the actual selection

template checkPowScratchSpaceLen(len: int) =
  ## Checks that there is a minimum of scratchspace to hold the temporaries
  debug:
    assert len >= 2, "Internal Error: the scratchspace for powmod should be equal or greater than 2"

func getWindowLen(bufLen: int): uint =
  ## Compute the maximum window size that fits in the scratchspace buffer
  checkPowScratchSpaceLen(bufLen)
  result = 5
  while (1 shl result) + 1 > bufLen:
    dec result

func powCranPrologue(
       a: var Limbs,
       scratchspace: var openarray[Limbs],
       m: static int, c: static SecretWord): uint =
  ## Setup the scratchspace
  ## Returns the fixed-window size for exponentiation with window optimization.
  result = scratchspace.len.getWindowLen()
  # Precompute window content, special case for window = 1
  # (i.e scratchspace has only space for 2 temporaries)
  # The content scratchspace[2+k] is set at aᵏ
  # with scratchspace[0] untouched
  if result == 1:
    scratchspace[1] = a
  else:
    scratchspace[2] = a
    for k in 2 ..< 1 shl result:
      scratchspace[k+1].mulCranPartialReduce(scratchspace[k], a, m, c)

  # Set a to one
  a.setOne()

func powCranSquarings(
        a: var Limbs,
        exponent: openarray[byte],
        tmp: var Limbs,
        window: uint,
        acc, acc_len: var uint,
        e: var int,
        m: static int, c: static SecretWord
      ): tuple[k, bits: uint] {.inline.}=
  ## Squaring step of exponentiation by squaring
  ## Get the next k bits in range [1, window)
  ## Square k times
  ## Returns the number of squarings done and the corresponding bits
  ##
  ## Updates iteration variables and accumulators
  # Due to the high number of parameters,
  # forcing this inline actually reduces the code size
  #
  # ⚠️: Extreme care should be used to not leak
  #    the exponent bits nor its real bitlength
  #    i.e. if the exponent is zero but encoded in a
  #    256-bit integer, only "256" should leak
  #    as for some application like RSA
  #    the exponent might be the user secret key.

  # Get the next bits
  # acc/acc_len must be uint to avoid Nim runtime checks leaking bits
  # acc/acc_len must be uint to avoid Nim runtime checks leaking bits
  # e is public
  var k = window
  if acc_len < window:
    if e < exponent.len:
      acc = (acc shl 8) or exponent[e].uint
      inc e
      acc_len += 8
    else: # Drained all exponent bits
      k = acc_len

  let bits = (acc shr (acc_len - k)) and ((1'u shl k) - 1)
  acc_len -= k

  # We have k bits and can do k squaring, skip final substraction for first k-1 ones.
  for i in 0 ..< k:
    a.squareCranPartialReduce(a, m, c)

  return (k, bits)

func powCran*(
       a: var Limbs,
       exponent: openarray[byte],
       p: Limbs,
       scratchspace: var openarray[Limbs],
       m: static int, c: static SecretWord,
       lazyReduce: static bool = false) =
  ## Modular exponentiation a <- a^exponent (mod M)
  ##
  ## This uses fixed-window optimization if possible
  ##
  ## - On input ``a`` is the base, on ``output`` a = a^exponent (mod M)
  ## - ``exponent`` is the exponent in big-endian canonical format (octet-string)
  ##   Use ``marshal`` for conversion
  ## - ``scratchspace`` with k the window bitsize of size up to 5
  ##   This is a buffer that can hold between 2ᵏ + 1 big-ints
  ##   A window of of 1-bit (no window optimization) requires only 2 big-ints
  ##
  ## Note that the best window size require benchmarking and is a tradeoff between
  ## - performance
  ## - stack usage
  ## - precomputation
  let window = powCranPrologue(a, scratchspace, m, c)

  # We process bits with from most to least significant.
  # At each loop iteration with have acc_len bits in acc.
  # To maintain constant-time the number of iterations
  # or the number of operations or memory accesses should be the same
  # regardless of acc & acc_len
  var
    acc, acc_len: uint
    e = 0
  while acc_len > 0 or e < exponent.len:
    let (k, bits) = powCranSquarings(
      a, exponent,
      scratchspace[0], window,
      acc, acc_len, e,
      m, c)

    # Window lookup: we set scratchspace[1] to the lookup value.
    # If the window length is 1, then it's already set.
    if window > 1:
      # otherwise we need a constant-time lookup
      # in particular we need the same memory accesses, we can't
      # just index the openarray with the bits to avoid cache attacks.
      for i in 1 ..< 1 shl k:
        let ctl = SecretWord(i) == SecretWord(bits)
        scratchspace[1].ccopy(scratchspace[1+i], ctl)

    # Multiply with the looked-up value
    # we keep the product only if the exponent bits are not all zeroes
    scratchspace[0].mulCranPartialReduce(a, scratchspace[1], m, c)
    a.ccopy(scratchspace[0], SecretWord(bits).isNonZero())

  when not lazyReduce:
    a.reduceCrandallFinal_impl(p)

func powCran_vartime*(
       a: var Limbs,
       exponent: openarray[byte],
       p: Limbs,
       scratchspace: var openarray[Limbs],
       m: static int, c: static SecretWord,
       lazyReduce: static bool = false) =
  ## Modular exponentiation a <- a^exponent (mod M)
  ##
  ## Warning ⚠️ :
  ## This is an optimization for public exponent
  ## Otherwise bits of the exponent can be retrieved with:
  ## - memory access analysis
  ## - power analysis
  ## - timing analysis

  # TODO: scratchspace[1] is unused when window > 1

  let window = powCranPrologue(a, scratchspace, m, c)

  var
    acc, acc_len: uint
    e = 0
  while acc_len > 0 or e < exponent.len:
    let (_, bits) = powCranSquarings(
      a, exponent,
      scratchspace[0], window,
      acc, acc_len, e,
      m, c)

    ## Warning ⚠️: Exposes the exponent bits
    if bits != 0:
      if window > 1:
        scratchspace[0].mulCranPartialReduce(a, scratchspace[1+bits], m, c)
      else:
        # scratchspace[1] holds the original `a`
        scratchspace[0].mulCranPartialReduce(a, scratchspace[1], m, c)
      a = scratchspace[0]

  when not lazyReduce:
    a.reduceCrandallFinal_impl(p)

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
        m: int,
        c: SecretWord) {.used.} =
  ## Lazily reduced addition
  ## Proof-of-concept. Currently unused.
  let S = (N*WordBitWidth - m)
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
