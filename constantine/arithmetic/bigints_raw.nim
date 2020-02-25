# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

# ############################################################
#
#         BigInt Raw representation and operations
#
# ############################################################
#
# This file holds the raw operations done on big ints
# The representation is optimized for:
# - constant-time (not leaking secret data via side-channel)
# - generated code size, datatype size and stack usage
# - performance
# in this order

# ############################################################
# Design

# To avoid carry issues we don't use the
# most significant bit of each machine word.
# i.e. for a uint64 base we only use 63-bit.
# More info: https://github.com/status-im/nim-constantine/wiki/Constant-time-arithmetics#guidelines
# Especially:
#    - https://bearssl.org/bigint.html
#    - https://cryptojedi.org/peter/data/pairing-20131122.pdf
#    - http://docs.milagro.io/en/amcl/milagro-crypto-library-white-paper.html
#
# Note that this might also be beneficial in terms of performance.
# Due to opcode latency, on Nehalem ADC is 6x times slower than ADD
# if it has dependencies (i.e the ADC depends on a previous ADC result)
#
# Control flow should only depends on the static maximum number of bits
# This number is defined per Finite Field/Prime/Elliptic Curve
#
# We internally order the limbs in little-endian
# So the least significant limb is limb[0]
# This is independent from the base type endianness.
#
# Constantine uses Nim generic integer to prevent mixing
# BigInts of different bitlength at compile-time and
# properly statically size the BigInt buffers.
#
# To avoid code-bloat due to monomorphization (i.e. duplicating code per announced bitlength)
# actual computation is deferred to type-erased routines.

import
  ../primitives/constant_time,
  ../primitives/extended_precision,
  ../config/common
from typetraits import distinctBase

# ############################################################
#
#                BigInts type-erased API
#
# ############################################################

# The "checked" API is exported as a building blocks
# with enforced compile-time checking of BigInt bitsize
# and memory ownership.
#
# The "raw" compute API uses views to avoid code duplication
# due to generic/static monomorphization.
#
# The "checked" API is a thin wrapper above the "raw" API to get the best of both world:
# - small code footprint
# - compiler enforced checks: types, bitsizes
# - compiler enforced memory: stack allocation and buffer ownership

type
  BigIntView* = ptr object
    ## Type-erased fixed-precision big integer
    ##
    ## This type mirrors the BigInt type and is used
    ## for the low-level computation API
    ## This design
    ## - avoids code bloat due to generic monomorphization
    ##   otherwise each bigint routines would have an instantiation for
    ##   each static `bits` parameter.
    ## - while not forcing the caller to preallocate computation buffers
    ##   for the high-level API and enforcing bitsizes
    ## - avoids runtime bound-checks on the view
    ##   for performance
    ##   and to ensure exception-free code
    ##   even when compiled in non "-d:danger" mode
    ##
    ## As with the BigInt type:
    ## - "bitLength" is the internal bitlength of the integer
    ##   This differs from the canonical bit-length as
    ##   Constantine word-size is smaller than a machine word.
    ##   This value should never be used as-is to prevent leaking secret data.
    ##   Computing this value requires constant-time operations.
    ##   Using this value requires converting it to the # of limbs in constant-time
    ##
    ## - "limbs" is an internal field that holds the internal representation
    ##   of the big integer. Least-significant limb first. Within limbs words are native-endian.
    ##
    ## This internal representation can be changed
    ## without notice and should not be used by external applications or libraries.
    ##
    ## Accesses should be done via BigIntViewConst / BigIntViewConst
    ## to have the compiler check for mutability
    bitLength: uint32
    limbs: UncheckedArray[Word]

  # "Indirection" to enforce pointer types deep immutability
  BigIntViewConst* = distinct BigIntView
    ## Immutable view into a BigInt
  BigIntViewMut* = distinct BigIntView
    ## Mutable view into a BigInt
  BigIntViewAny* = BigIntViewConst or BigIntViewMut

# No exceptions allowed
{.push raises: [].}

# ############################################################
#
#                 Deep Mutability safety
#
# ############################################################

template `[]`*(v: BigIntViewConst, limbIdx: int): Word =
  distinctBase(type v)(v).limbs[limbIdx]

template `[]`*(v: BigIntViewMut, limbIdx: int): var Word =
  distinctBase(type v)(v).limbs[limbIdx]

template `[]=`*(v: BigIntViewMut, limbIdx: int, val: Word) =
  distinctBase(type v)(v).limbs[limbIdx] = val

template bitSizeof(v: BigIntViewAny): uint32 =
  bind BigIntView
  distinctBase(type v)(v).bitLength

const divShiftor = log2(WordPhysBitSize)
template numLimbs*(v: BigIntViewAny): int =
  ## Compute the number of limbs from
  ## the **internal** bitlength
  (bitSizeof(v).int + WordPhysBitSize - 1) shr divShiftor

template setBitLength(v: BigIntViewMut, internalBitLength: uint32) =
  distinctBase(type v)(v).bitLength = internalBitLength

# TODO: Check if repeated v.numLimbs calls are optimized away

template `[]`*(v: BigIntViewConst, limbIdxFromEnd: BackwardsIndex): Word =
  distinctBase(type v)(v).limbs[numLimbs(v).int - int limbIdxFromEnd]

template `[]`*(v: BigIntViewMut, limbIdxFromEnd: BackwardsIndex): var Word =
  distinctBase(type v)(v).limbs[numLimbs(v).int - int limbIdxFromEnd]

template `[]=`*(v: BigIntViewMut, limbIdxFromEnd: BackwardsIndex, val: Word) =
  distinctBase(type v)(v).limbs[numLimbs(v).int - int limbIdxFromEnd] = val

# ############################################################
#
#           Checks and debug/test only primitives
#
# ############################################################

template checkMatchingBitlengths(a, b: distinct BigIntViewAny) =
  ## Check that bitlengths of bigints match
  ## This is only checked
  ## with "-d:debugConstantine" and when assertions are on.
  debug:
    assert distinctBase(type a)(a).bitLength ==
      distinctBase(type b)(b).bitLength, "Internal Error: operands bitlength do not match"

template checkValidModulus(m: BigIntViewConst) =
  ## Check that the modulus is valid
  ## The check is approximate, it only checks that
  ## the most-significant words is non-zero instead of
  ## checking that the last announced bit is 1.
  ## This is only checked
  ## with "-d:debugConstantine" and when assertions are on.
  debug:
    assert not isZero(m[^1]).bool, "Internal Error: the modulus must use all declared bits"

template checkOddModulus(m: BigIntViewConst) =
  ## CHeck that the modulus is odd
  ## and valid for use in the Montgomery n-residue representation
  debug:
    assert bool(BaseType(m[0]) and 1), "Internal Error: the modulus must be odd to use the Montgomery representation."

template checkWordShift(k: int) =
  ## Checks that the shift is less than the word bit size
  debug:
    assert k <= WordBitSize, "Internal Error: the shift must be less than the word bit size"

template checkPowScratchSpaceLen(len: int) =
  ## Checks that there is a minimum of scratchspace to hold the temporaries
  debug:
    assert len >= 2, "Internal Error: the scratchspace for powmod should be equal or greater than 2"

debug:
  func `$`*(a: BigIntViewAny): string =
    let len = a.numLimbs()
    result = "["
    for i in 0 ..< len - 1:
      result.add $a[i]
      result.add ", "
    result.add $a[len-1]
    result.add "] ("
    result.add $a.bitSizeof
    result.add " bits)"

# ############################################################
#
#                    BigInt primitives
#
# ############################################################

func isZero*(a: BigIntViewAny): CTBool[Word] =
  ## Returns true if a big int is equal to zero
  var accum: Word
  for i in 0 ..< a.numLimbs():
    accum = accum or a[i]
  result = accum.isZero()

func setZero(a: BigIntViewMut) =
  ## Set a BigInt to 0
  ## It's bit size is unchanged
  zeroMem(a[0].unsafeAddr, a.numLimbs() * sizeof(Word))

func ccopy*(a: BigIntViewMut, b: BigIntViewAny, ctl: CTBool[Word]) =
  ## Constant-time conditional copy
  ## If ctl is true: b is copied into a
  ## if ctl is false: b is not copied and a is untouched
  ## Time and memory accesses are the same whether a copy occurs or not
  checkMatchingBitlengths(a, b)
  for i in 0 ..< a.numLimbs():
    a[i] = ctl.mux(b[i], a[i])

# The arithmetic primitives all accept a control input that indicates
# if it is a placebo operation. It stills performs the
# same memory accesses to be side-channel attack resistant.

func cadd*(a: BigIntViewMut, b: BigIntViewAny, ctl: CTBool[Word]): CTBool[Word] =
  ## Constant-time in-place conditional addition
  ## The addition is only performed if ctl is "true"
  ## The result carry is always computed.
  ##
  ## a and b MAY be the same buffer
  ## a and b MUST have the same announced bitlength (i.e. `bits` static parameters)
  checkMatchingBitlengths(a, b)

  for i in 0 ..< a.numLimbs():
    let new_a = a[i] + b[i] + Word(result)
    result = new_a.isMsbSet()
    a[i] = ctl.mux(new_a.mask(), a[i])

func csub*(a: BigIntViewMut, b: BigIntViewAny, ctl: CTBool[Word]): CTBool[Word] =
  ## Constant-time in-place conditional substraction
  ## The substraction is only performed if ctl is "true"
  ## The result carry is always computed.
  ##
  ## a and b MAY be the same buffer
  ## a and b MUST have the same announced bitlength (i.e. `bits` static parameters)
  checkMatchingBitlengths(a, b)

  for i in 0 ..< a.numLimbs():
    let new_a = a[i] - b[i] - Word(result)
    result = new_a.isMsbSet()
    a[i] = ctl.mux(new_a.mask(), a[i])

func dec*(a: BigIntViewMut, w: Word): CTBool[Word] =
  ## Decrement a big int by a small word
  ## Returns the result carry

  a[0] -= w
  result = a[0].isMsbSet()
  a[0] = a[0].mask()
  for i in 1 ..< a.numLimbs():
    a[i] -= Word(result)
    result = a[i].isMsbSet()
    a[i] = a[i].mask()

func shiftRight*(a: BigIntViewMut, k: int) =
  ## Shift right by k.
  ##
  ## k MUST be less than the base word size (2^31 or 2^63)
  # We don't reuse shr for this in-place operation
  # Do we need to return the shifted out part?
  #
  # Note: for speed, loading a[i] and a[i+1]
  #       instead of a[i-1] and a[i]
  #       is probably easier to parallelize for the compiler
  #       (antidependence WAR vs loop-carried dependence RAW)
  checkWordShift(k)

  let len = a.numLimbs()
  for i in 0 ..< len-1:
    a[i] = (a[i] shr k) or mask(a[i+1] shl (WordBitSize - k))
  a[len-1] = a[len-1] shr k

# ############################################################
#
#          BigInt Primitives Optimized for speed
#
# ############################################################
#
# This section implements primitives that improve the speed
# of common use-cases at the expense of a slight increase in code-size.
# Where code size is a concern, the high-level API should use
# copy and/or the conditional operations.

func add*(a: BigIntViewMut, b: BigIntViewAny): CTBool[Word] =
  ## Constant-time in-place addition
  ## Returns the carry
  ##
  ## a and b MAY be the same buffer
  ## a and b MUST have the same announced bitlength (i.e. `bits` static parameters)
  checkMatchingBitlengths(a, b)

  for i in 0 ..< a.numLimbs():
    a[i] = a[i] + b[i] + Word(result)
    result = a[i].isMsbSet()
    a[i] = a[i].mask()

func sub*(a: BigIntViewMut, b: BigIntViewAny): CTBool[Word] =
  ## Constant-time in-place substraction
  ## Returns the borrow
  ##
  ## a and b MAY be the same buffer
  ## a and b MUST have the same announced bitlength (i.e. `bits` static parameters)
  checkMatchingBitlengths(a, b)

  for i in 0 ..< a.numLimbs():
    a[i] = a[i] - b[i] - Word(result)
    result = a[i].isMsbSet()
    a[i] = a[i].mask()

func sum*(r: BigIntViewMut, a, b: BigIntViewAny): CTBool[Word] =
  ## Sum `a` and `b` into `r`.
  ## `r` is initialized/overwritten
  ##
  ## Returns the carry
  checkMatchingBitlengths(a, b)

  r.setBitLength(bitSizeof(a))

  for i in 0 ..< a.numLimbs():
    r[i] = a[i] + b[i] + Word(result)
    result = a[i].isMsbSet()
    r[i] = r[i].mask()

func diff*(r: BigIntViewMut, a, b: BigIntViewAny): CTBool[Word] =
  ## Substract `b` from `a` and store the result into `r`.
  ## `r` is initialized/overwritten
  ##
  ## Returns the borrow
  checkMatchingBitlengths(a, b)

  r.setBitLength(bitSizeof(a))

  for i in 0 ..< a.numLimbs():
    r[i] = a[i] - b[i] - Word(result)
    result = a[i].isMsbSet()
    r[i] = r[i].mask()

# ############################################################
#
#                   Modular BigInt
#
# ############################################################

func shlAddMod(a: BigIntViewMut, c: Word, M: BigIntViewConst) =
  ## Fused modular left-shift + add
  ## Shift input `a` by a word and add `c` modulo `M`
  ##
  ## With a word W = 2^WordBitSize and a modulus M
  ## Does a <- a * W + c (mod M)
  ##
  ## The modulus `M` MUST announced most-significant bit must be set.
  checkValidModulus(M)

  let aLen = a.numLimbs()
  let mBits = bitSizeof(M)

  if mBits <= WordBitSize:
    # If M fits in a single limb
    var q: Word

    # (hi, lo) = a * 2^63 + c
    let hi = a[0] shr 1                   # 64 - 63 = 1
    let lo = (a[0] shl WordBitSize) or c  # Assumes most-significant bit in c is not set
    unsafeDiv2n1n(q, a[0], hi, lo, M[0])  # (hi, lo) mod M
    return

  else:
    ## Multiple limbs
    let hi = a[^1]                                          # Save the high word to detect carries
    let R = mBits and WordBitSize                       # R = mBits mod 64

    var a0, a1, m0: Word
    if R == 0:                                              # If the number of mBits is a multiple of 64
      a0 = a[^1]                                        #
      moveMem(a[1].addr, a[0].addr, (aLen-1) * Word.sizeof) # we can just shift words
      a[0] = c                                              # and replace the first one by c
      a1 = a[^1]
      m0 = M[^1]
    else:                                                   # Else: need to deal with partial word shifts at the edge.
      a0 = mask((a[^1] shl (WordBitSize-R)) or (a[^2] shr R))
      moveMem(a[1].addr, a[0].addr, (aLen-1) * Word.sizeof)
      a[0] = c
      a1 = mask((a[^1] shl (WordBitSize-R)) or (a[^2] shr R))
      m0 = mask((M[^1] shl (WordBitSize-R)) or (M[^2] shr R))

    # m0 has its high bit set. (a0, a1)/p0 fits in a limb.
    # Get a quotient q, at most we will be 2 iterations off
    # from the true quotient

    let
      a_hi = a0 shr 1                              # 64 - 63 = 1
      a_lo = (a0 shl WordBitSize) or a1
    var q, r: Word
    unsafeDiv2n1n(q, r, a_hi, a_lo, m0)            # Estimate quotient
    q = mux(                                       # If n_hi == divisor
          a0 == m0, MaxWord,                       # Quotient == MaxWord (0b0111...1111)
          mux(
            q.isZero, Zero,                        # elif q == 0, true quotient = 0
            q - One                                # else instead of being of by 0, 1 or 2
          )                                        # we returning q-1 to be off by -1, 0 or 1
        )

    # Now substract a*2^63 - q*p
    var carry = Zero
    var over_p = CtTrue                            # Track if quotient greater than the modulus

    for i in 0 ..< M.numLimbs():
      var qp_lo: Word

      block: # q*p
        # q * p + carry (doubleword) carry from previous limb
        let qp = unsafeExtPrecMul(q, M[i]) + carry.DoubleWord
        carry = Word(qp shr WordBitSize)           # New carry: high digit besides LSB
        qp_lo = qp.Word.mask()                     # Normalize to u63

      block: # a*2^63 - q*p
        a[i] -= qp_lo
        carry += Word(a[i].isMsbSet)               # Adjust if borrow
        a[i] = a[i].mask()                        # Normalize to u63

      over_p = mux(
                a[i] == M[i], over_p,
                a[i] > M[i]
              )

    # Fix quotient, the true quotient is either q-1, q or q+1
    #
    # if carry < q or carry == q and over_p we must do "a -= p"
    # if carry > hi (negative result) we must do "a += p"

    let neg = carry > hi
    let tooBig = not neg and (over_p or (carry < hi))

    discard a.cadd(M, ctl = neg)
    discard a.csub(M, ctl = tooBig)
    return

func reduce*(r: BigIntViewMut, a: BigIntViewAny, M: BigIntViewConst) =
  ## Reduce `a` modulo `M` and store the result in `r`
  ##
  ## The modulus `M` MUST announced most-significant bit must be set.
  ## The result `r` buffer size MUST be at least the size of `M` buffer
  ##
  ## CT: Depends only on the bitlength of `a` and the modulus `M`

  # Note: for all cryptographic intents and purposes the modulus is known at compile-time
  # but we don't want to inline it as it would increase codesize, better have Nim
  # pass a pointer+length to a fixed session of the BSS.
  checkValidModulus(M)

  let aBits = bitSizeof(a)
  let mBits = bitSizeof(M)
  let aLen = a.numLimbs()

  r.setBitLength(bitSizeof(M))

  if aBits < mBits:
    # if a uses less bits than the modulus,
    # it is guaranteed < modulus.
    # This relies on the precondition that the modulus uses all declared bits
    copyMem(r[0].addr, a[0].unsafeAddr, aLen * sizeof(Word))
    for i in aLen ..< r.numLimbs():
      r[i] = Zero
  else:
    # a length i at least equal to the modulus.
    # we can copy modulus.limbs-1 words
    # and modular shift-left-add the rest
    let mLen = M.numLimbs()
    let aOffset = aLen - mLen
    copyMem(r[0].addr, a[aOffset+1].unsafeAddr, (mLen-1) * sizeof(Word))
    r[^1] = Zero
    # Now shift-left the copied words while adding the new word modulo M
    for i in countdown(aOffset, 0):
      r.shlAddMod(a[i], M)

# ############################################################
#
#                 Montgomery Arithmetic
#
# ############################################################

template wordMul(a, b: Word): Word =
  mask(a * b)

func montyMul*(
       r: BigIntViewMut, a, b: distinct BigIntViewAny,
       M: BigIntViewConst, negInvModWord: Word) =
  ## Compute r <- a*b (mod M) in the Montgomery domain
  ## `negInvModWord` = -1/M (mod Word). Our words are 2^31 or 2^63
  ##
  ## This resets r to zero before processing. Use {.noInit.}
  ## to avoid duplicating with Nim zero-init policy
  ## The result `r` buffer size MUST be at least the size of `M` buffer
  ##
  ##
  ## Assuming 63-bit wors, the magic constant should be:
  ##
  ## - µ ≡ -1/M[0] (mod 2^63) for a general multiplication
  ##   This can be precomputed with `negInvModWord`
  ## - 1 for conversion from Montgomery to canonical representation
  ##   The library implements a faster `redc` primitive for that use-case
  ## - R^2 (mod M) for conversion from canonical to Montgomery representation
  ##
  # i.e. c'R <- a'R b'R * R^-1 (mod M) in the natural domain
  # as in the Montgomery domain all numbers are scaled by R

  checkValidModulus(M)
  checkOddModulus(M)
  checkMatchingBitlengths(a, M)
  checkMatchingBitlengths(b, M)

  let nLen = M.numLimbs()
  r.setBitLength(bitSizeof(M))
  setZero(r)

  var r_hi = Zero   # represents the high word that is used in intermediate computation before reduction mod M
  for i in 0 ..< nLen:

    let zi = (r[0] + wordMul(a[i], b[0])).wordMul(negInvModWord)
    var carry = Zero

    for j in 0 ..< nLen:
      let z = DoubleWord(r[j]) + unsafeExtPrecMul(a[i], b[j]) +
              unsafeExtPrecMul(zi, M[j]) + DoubleWord(carry)
      carry = Word(z shr WordBitSize)
      if j != 0: # "division" by a physical word 2^32 or 2^64
        r[j-1] = Word(z).mask()

    r_hi += carry
    r[^1] = r_hi.mask()
    r_hi = r_hi shr WordBitSize

  # If the extra word is not zero or if r-M does not borrow (i.e. r > M)
  # Then substract M
  discard r.csub(M, r_hi.isNonZero() or not r.csub(M, CtFalse))

func redc*(r: BigIntViewMut, a: BigIntViewAny, one, N: BigIntViewConst, negInvModWord: Word) {.inline.} =
  ## Transform a bigint ``a`` from it's Montgomery N-residue representation (mod N)
  ## to the regular natural representation (mod N)
  ##
  ## with W = N.numLimbs()
  ## and R = (2^WordBitSize)^W
  ##
  ## Does "a * R^-1 (mod N)"
  ##
  ## This is called a Montgomery Reduction
  ## The Montgomery Magic Constant is µ = -1/N mod N
  ## is used internally and can be precomputed with negInvModWord(Curve)
  # References:
  #   - https://eprint.iacr.org/2017/1057.pdf (Montgomery)
  #     page: Radix-r interleaved multiplication algorithm
  #   - https://en.wikipedia.org/wiki/Montgomery_modular_multiplication#Montgomery_arithmetic_on_multiprecision_(variable-radix)_integers
  #   - http://langevin.univ-tln.fr/cours/MLC/extra/montgomery.pdf
  #     Montgomery original paper
  #
  montyMul(r, a, one, N, negInvModWord)

func montyResidue*(
       r: BigIntViewMut, a: BigIntViewAny,
       N, r2modN: BigIntViewConst, negInvModWord: Word) {.inline.} =
  ## Transform a bigint ``a`` from it's natural representation (mod N)
  ## to a the Montgomery n-residue representation
  ##
  ## Montgomery-Multiplication - based
  ##
  ## with W = N.numLimbs()
  ## and R = (2^WordBitSize)^W
  ##
  ## Does "a * R (mod N)"
  ##
  ## `a`: The source BigInt in the natural representation. `a` in [0, N) range
  ## `N`: The field modulus. N must be odd.
  ## `r2modN`: 2^WordBitSize mod `N`. Can be precomputed with `r2mod` function
  ##
  ## Important: `r` is overwritten
  ## The result `r` buffer size MUST be at least the size of `M` buffer
  # Reference: https://eprint.iacr.org/2017/1057.pdf
  montyMul(r, a, r2ModN, N, negInvModWord)

func montySquare*(
       r: BigIntViewMut, a: BigIntViewAny,
       M: BigIntViewConst, negInvModWord: Word) {.inline.} =
  ## Compute r <- a^2 (mod M) in the Montgomery domain
  ## `negInvModWord` = -1/M (mod Word). Our words are 2^31 or 2^63
  montyMul(r, a, a, M, negInvModWord)

# Montgomery Modular Exponentiation
# ------------------------------------------
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
#   - the base^k is stored at each index of a temp table of size k
#   - the base^k to use is indexed by the hamming weight
#     of the exponent, leaking this to cache attacks
#   - in contrast BearSSL touches the whole table to
#     hide the actual selection

func getWindowLen(bufLen: int): uint =
  ## Compute the maximum window size that fits in the scratchspace buffer
  checkPowScratchSpaceLen(bufLen)
  result = 5
  while (1 shl result) + 1 > bufLen:
    dec result

func montyPowPrologue(
       a: BigIntViewMut, M, one: BigIntViewConst,
       negInvModWord: Word,
       scratchspace: openarray[BigIntViewMut]
     ): tuple[window: uint, bigIntSize: int] {.inline.}=
  # Due to the high number of parameters,
  # forcing this inline actually reduces the code size

  result.window = scratchspace.len.getWindowLen()
  result.bigIntSize = a.numLimbs() * sizeof(Word) + sizeof(BigIntView.bitLength)

  # Precompute window content, special case for window = 1
  # (i.e scratchspace has only space for 2 temporaries)
  # The content scratchspace[2+k] is set at a^k
  # with scratchspace[0] untouched
  if result.window == 1:
    copyMem(pointer scratchspace[1], pointer a, result.bigIntSize)
  else:
    copyMem(pointer scratchspace[2], pointer a, result.bigIntSize)
    for k in 2 ..< 1 shl result.window:
      scratchspace[k+1].montyMul(scratchspace[k], a, M, negInvModWord)

    scratchspace[1].setBitLength(bitSizeof(M))

  # Set a to one
  copyMem(pointer a, pointer one, result.bigIntSize)

func montyPowSquarings(
        a: BigIntViewMut,
        exponent: openarray[byte],
        M: BigIntViewConst,
        negInvModWord: Word,
        tmp: BigIntViewMut,
        window: uint,
        bigIntSize: int,
        acc, acc_len: var uint,
        e: var int,
      ): tuple[k, bits: uint] {.inline.}=
  ## Squaring step of exponentiation by squaring
  ## Get the next k bits in range [1, window)
  ## Square k times
  ## Returns the number of squarings done and the corresponding bits
  ##
  ## Updates iteration variables and accumulators
  # Due to the high number of parameters,
  # forcing this inline actually reduces the code size

  # Get the next bits
  var k = window
  if acc_len < window:
    if e < exponent.len:
      acc = (acc shl 8) or exponent[e].uint
      inc e
      acc_len += 8
    else: # Drained all exponent bits
      k = acc_len

  let bits = (acc shr (acc_len - k)) and ((1'u32 shl k) - 1)
  acc_len -= k

  # We have k bits and can do k squaring
  for i in 0 ..< k:
    tmp.montySquare(a, M, negInvModWord)
    copyMem(pointer a, pointer tmp, bigIntSize)

  return (k, bits)

func montyPow*(
       a: BigIntViewMut,
       exponent: openarray[byte],
       M, one: BigIntViewConst,
       negInvModWord: Word,
       scratchspace: openarray[BigIntViewMut]
      ) =
  ## Modular exponentiation r = a^exponent mod M
  ## in the Montgomery domain
  ##
  ## This uses fixed-window optimization if possible
  ##
  ## - On input ``a`` is the base, on ``output`` a = a^exponent (mod M)
  ##   ``a`` is in the Montgomery domain
  ## - ``exponent`` is the exponent in big-endian canonical format (octet-string)
  ##   Use ``exportRawUint`` for conversion
  ## - ``M`` is the modulus
  ## - ``one`` is 1 (mod M) in montgomery representation
  ## - ``negInvModWord`` is the montgomery magic constant "-1/M[0] mod 2^WordBitSize"
  ## - ``scratchspace`` with k the window bitsize of size up to 5
  ##   This is a buffer that can hold between 2^k + 1 big-ints
  ##   A window of of 1-bit (no window optimization) requires only 2 big-ints
  ##
  ## Note that the best window size require benchmarking and is a tradeoff between
  ## - performance
  ## - stack usage
  ## - precomputation
  ##
  ## For example BLS12-381 window size of 5 is 30% faster than no window,
  ## but windows of size 2, 3, 4 bring no performance benefit, only increased stack space.
  ## A window of size 5 requires (2^5 + 1)*(381 + 7)/8 = 33 * 48 bytes = 1584 bytes
  ## of scratchspace (on the stack).

  let (window, bigIntSize) = montyPowPrologue(a, M, one, negInvModWord, scratchspace)

  # We process bits with from most to least significant.
  # At each loop iteration with have acc_len bits in acc.
  # To maintain constant-time the number of iterations
  # or the number of operations or memory accesses should be the same
  # regardless of acc & acc_len
  var
    acc, acc_len: uint
    e = 0
  while acc_len > 0 or e < exponent.len:
    let (k, bits) = montyPowSquarings(
      a, exponent, M, negInvModWord,
      scratchspace[0], window, bigIntSize,
      acc, acc_len, e
    )

    # Window lookup: we set scratchspace[1] to the lookup value.
    # If the window length is 1, then it's already set.
    if window > 1:
      # otherwise we need a constant-time lookup
      # in particular we need the same memory accesses, we can't
      # just index the openarray with the bits to avoid cache attacks.
      for i in 1 ..< 1 shl k:
        let ctl = Word(i) == Word(bits)
        scratchspace[1].ccopy(scratchspace[1+i], ctl)

    # Multiply with the looked-up value
    # we keep the product only if the exponent bits are not all zero
    scratchspace[0].montyMul(a, scratchspace[1], M, negInvModWord)
    a.ccopy(scratchspace[0], Word(bits) != Zero)

func montyPowUnsafeExponent*(
       a: BigIntViewMut,
       exponent: openarray[byte],
       M, one: BigIntViewConst,
       negInvModWord: Word,
       scratchspace: openarray[BigIntViewMut]
      ) =
  ## Modular exponentiation r = a^exponent mod M
  ## in the Montgomery domain
  ##
  ## Warning ⚠️ :
  ## This is an optimization for public exponent
  ## Otherwise bits of the exponent can be retrieved with:
  ## - memory access analysis
  ## - power analysis
  ## - timing analysis

  # TODO: scratchspace[1] is unused when window > 1

  let (window, bigIntSize) = montyPowPrologue(
         a, M, one, negInvModWord, scratchspace)

  var
    acc, acc_len: uint
    e = 0
  while acc_len > 0 or e < exponent.len:
    let (k, bits) = montyPowSquarings(
      a, exponent, M, negInvModWord,
      scratchspace[0], window, bigIntSize,
      acc, acc_len, e
    )

    ## Warning ⚠️: Exposes the exponent bits
    if bits != 0:
      if window > 1:
        scratchspace[0].montyMul(a, scratchspace[1+bits], M, negInvModWord)
      else:
        # scratchspace[1] holds the original `a`
        scratchspace[0].montyMul(a, scratchspace[1], M, negInvModWord)
      copyMem(pointer a, pointer scratchspace[0], bigIntSize)
