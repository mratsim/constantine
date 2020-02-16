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
from sugar import distinctBase

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

func setZero*(a: BigIntViewMut) =
  ## Set a BigInt to 0
  ## It's bit size is unchanged
  zeroMem(a[0].unsafeAddr, a.numLimbs() * sizeof(Word))

# The arithmetic primitives all accept a control input that indicates
# if it is a placebo operation. It stills performs the
# same memory accesses to be side-channel attack resistant.

func add*(a: BigIntViewMut, b: BigIntViewAny, ctl: CTBool[Word]): CTBool[Word] =
  ## Constant-time big integer in-place optional addition
  ## The addition is only performed if ctl is "true"
  ## The result carry is always computed.
  ##
  ## a and b MAY be the same buffer
  ## a and b MUST have the same announced bitlength (i.e. `bits` static parameters)
  checkMatchingBitlengths(a, b)

  for i in 0 ..< a.numLimbs():
    let new_a = a[i] + b[i] + Word(result)
    result = new_a.isMsbSet()
    a[i] = ctl.cmov(new_a and MaxWord, a[i])

func sub*(a: BigIntViewMut, b: BigIntViewAny, ctl: CTBool[Word]): CTBool[Word] =
  ## Constant-time big integer in-place optional substraction
  ## The substraction is only performed if ctl is "true"
  ## The result carry is always computed.
  ##
  ## a and b MAY be the same buffer
  ## a and b MUST have the same announced bitlength (i.e. `bits` static parameters)
  checkMatchingBitlengths(a, b)

  for i in 0 ..< a.numLimbs():
    let new_a = a[i] - b[i] - Word(result)
    result = new_a.isMsbSet()
    a[i] = ctl.cmov(new_a and MaxWord, a[i])

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
    let R = mBits and WordBitSize                           # R = mBits mod 64

    var a0, a1, m0: Word
    if R == 0:                                              # If the number of mBits is a multiple of 64
      a0 = a[^1]                                        #
      moveMem(a[1].addr, a[0].addr, (aLen-1) * Word.sizeof) # we can just shift words
      a[0] = c                                              # and replace the first one by c
      a1 = a[^1]
      m0 = M[^1]
    else:                                                   # Else: need to deal with partial word shifts at the edge.
      a0 = ((a[^1] shl (WordBitSize-R)) or (a[^2] shr R)) and MaxWord
      moveMem(a[1].addr, a[0].addr, (aLen-1) * Word.sizeof)
      a[0] = c
      a1 = ((a[^1] shl (WordBitSize-R)) or (a[^2] shr R)) and MaxWord
      m0 = ((M[^1] shl (WordBitSize-R)) or (M[^2] shr R)) and MaxWord

    # m0 has its high bit set. (a0, a1)/p0 fits in a limb.
    # Get a quotient q, at most we will be 2 iterations off
    # from the true quotient

    let
      a_hi = a0 shr 1                              # 64 - 63 = 1
      a_lo = (a0 shl WordBitSize) or a1
    var q, r: Word
    unsafeDiv2n1n(q, r, a_hi, a_lo, m0)            # Estimate quotient
    q = cmov(                                       # If n_hi == divisor
          a0 == m0, MaxWord,                       # Quotient == MaxWord (0b0111...1111)
          cmov(
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
        qp_lo = qp.Word and MaxWord                # Normalize to u63

      block: # a*2^63 - q*p
        a[i] -= qp_lo
        carry += Word(a[i].isMsbSet)               # Adjust if borrow
        a[i] = a[i] and MaxWord                    # Normalize to u63

      over_p = cmov(
                a[i] == M[i], over_p,
                a[i] > M[i]
              )

    # Fix quotient, the true quotient is either q-1, q or q+1
    #
    # if carry < q or carry == q and over_p we must do "a -= p"
    # if carry > hi (negative result) we must do "a += p"

    let neg = carry > hi
    let tooBig = not neg and (over_p or (carry < hi))

    discard a.add(M, ctl = neg)
    discard a.sub(M, ctl = tooBig)
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

# TODO: when not optimizing for code-size we can benefit from
#       specialized implementations of
#       - Montgomery Multiplication by 1 (redc)
#       - Montgomery squaring
#       - Almost Montgomery Multiplication for Modular exponentiation:
#         https://eprint.iacr.org/2011/239.pdf

template wordMul(a, b: Word): Word =
  (a * b) and MaxWord

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
      if j != 0:
        r[j-1] = Word(z) and MaxWord

    r_hi += carry
    r[^1] = r_hi and MaxWord
    r_hi = r_hi shr WordBitSize

  # If the extra word is not zero or if r-M does not borrow (i.e. r > M)
  # Then substract M
  discard r.sub(M, r_hi.isNonZero() or not r.sub(M, CtFalse))

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
  checkValidModulus(N)
  checkOddModulus(N)
  checkMatchingBitlengths(a, N)

  # TODO: This is a Montgomery multiplication by 1 and can be specialized
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
  checkValidModulus(N)
  checkOddModulus(N)
  checkMatchingBitlengths(a, N)

  montyMul(r, a, r2ModN, N, negInvModWord)
