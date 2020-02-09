# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.


# ############################################################
#
#                    BigInt representation
#
# ############################################################

# To avoid carry issues we don't use the
# most significant bit of each word.
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

# Control flow should only depends on the static maximum number of bits
# This number is defined per Finite Field/Prime/Elliptic Curve
#
# For efficiency, our limbs will use a word size of 63-bit
# Warning ⚠️ : This assumes that u64 + u64 and u64 * u64
#              are constant-time even on 32-bit platforms
#
# We internally order the limbs in little-endian
# So the least significant limb is limb[0]
# This is independent from the base type endianness.

import ./primitives
from ./private/primitives_internal import unsafeDiv2n1n, unsafeExtendedPrecMul

type Word* = Ct[uint32]
type BaseType* = uint32 # Exported type for conversion in "normal integers"

const WordBitSize* = sizeof(Word) * 8 - 1
  ## Limbs are 63-bit by default

const
  Zero* = Word(0)
  One* = Word(1)
  MaxWord* = (not Zero) shr 1
    ## This represents 0x7F_FF_FF_FF__FF_FF_FF_FF
    ## also 0b0111...1111
    ## This biggest representable number in our limbs.
    ## i.e. The most significant bit is never set at the end of each function

func wordsRequired(bits: int): int {.compileTime.}=
  (bits + WordBitSize - 1) div WordBitSize

# TODO: Currently the library is instantiation primitives like "add"
#       for each "bits" size supported. This will lead to duplication
#       if many sizes (for example for scp256k1, bn254 and BLS12-381)
#       are required.
#       It could be avoided by having the bitsize be a runtime field
#       of the bigint. However the tradeoff would be:
#       - overhead of this additional field
#       - limbs have to be stored in an UncheckedArray instead of an array
#         introducing memory management issues

type
  BigInt*[bits: static int] = object
    ## Fixed-precision big integer
    ##
    ## "limbs" is an internal field that holds the internal representation
    ## of the big integer. This internal representation can be changed
    ## without notice and should not be used by external applications or libraries.
    # Constantine BigInt have a word-size chosen to minimize bigint memory usage
    # while allowing carry-less operations in a machine-efficient type like uint32
    # uint64 or uint128 if available.
    # In practice the word size is 63-bit.
    #
    # "Limb-endianess" is little-endian (least significant limb at BigInt.limbs[0])
    limbs*: array[bits.wordsRequired, Word]

# No exceptions allowed
# TODO: can we use compile-time "Natural" instead of "int" in that case?
{.push raises: [].}

# ############################################################
#
#                         Internal
#
# ############################################################

func copyLimbs*[dstBits, srcBits](
        dst: var BigInt[dstBits], dstStart: static int,
        src: BigInt[srcBits], srcStart: static int,
        numLimbs: static int) {.inline.}=
  ## Copy `numLimbs` from src into dst
  ## If `dst` buffer is larger than `numLimbs` buffer
  ## the extra space will be zero-ed out
  ##
  ## Limbs ordering is little-endian. limb 0 is the least significant/
  ##
  ## This should work at both compile-time and runtime.
  ##
  ## `numLimbs` must be less or equal the limbs of the `dst` and `src` buffers
  ## This is checked at compile-time and has no runtime impact

  static:
    doAssert numLimbs >= 0, "`numLimbs` must be greater or equal zero"

    doAssert numLimbs + srcStart <= src.limbs.len,
      "The number of limbs to copy (" & $numLimbs &
      ") must be less or equal to the number of limbs in the `src` buffer (" &
      $src.limbs.len & " for " & $srcBits & " bits)"

    doAssert numLimbs + dstStart <= dst.limbs.len,
      "The number of limbs to copy (" & $numLimbs &
      ") must be less or equal to the number of limbs in the `dst` buffer (" &
      $dst.limbs.len & " for " & $dstBits & " bits)"

  # TODO: do we need a copyMem / memcpy specialization for runtime
  #       or use dst.limbs[0..<numLimbs] = src.toOpenarray(0, numLimbs - 1)
  for i in static(0 ..< numLimbs):
    dst.limbs[i+dstStart] = src.limbs[i+srcStart]

func setZero*(a: var BigInt, start, stop: static int) {.inline.} =
  ## Set limbs to zero
  ## The [start, stop] range is inclusive
  ## If stop < start, a is unmodified
  static:
    doAssert start in 0 ..< a.limbs.len, $start & " not in 0 ..< " & $a.limbs.len & " (numLimbs)"
    doAssert stop  in 0 ..< a.limbs.len, $stop & " not in 0 ..< " & $a.limbs.len & " (numLimbs)"

  for i in static(start .. stop):
    a.limbs[i] = Zero

# ############################################################
#
#                    BigInt primitives
#
# ############################################################

# TODO: {.inline.} analysis

func isZero*(a: BigInt): CTBool[Word] =
  ## Returns if a big int is equal to zero
  var accum: Word
  for i in static(0 ..< a.limbs.len):
    accum = accum or a.limbs[i]
  result = accum.isZero()

func `==`*(a, b: BigInt): CTBool[Word] =
  ## Returns true if 2 big ints are equal
  var accum: Word
  for i in static(0 ..< a.limbs.len):
    accum = accum or (a.limbs[i] xor b.limbs[i])
  result = accum.isZero

# The arithmetic primitives all accept a control input that indicates
# if it is a placebo operation. It stills performs the
# same memory accesses to be side-channel attack resistant.

func add*[bits](a: var BigInt[bits], b: BigInt[bits], ctl: CTBool[Word]): CTBool[Word] =
  ## Constant-time big integer in-place optional addition
  ## The addition is only performed if ctl is "true"
  ## The result carry is always computed.
  for i in static(0 ..< a.limbs.len):
    let new_a = a.limbs[i] + b.limbs[i] + Word(result)
    result = new_a.isMsbSet()
    a.limbs[i] = ctl.mux(new_a and MaxWord, a.limbs[i])

func sub*[bits](a: var BigInt[bits], b: BigInt[bits], ctl: CTBool[Word]): CTBool[Word] =
  ## Constant-time big integer in-place optional substraction
  ## The substraction is only performed if ctl is "true"
  ## The result carry is always computed.
  for i in static(0 ..< a.limbs.len):
    let new_a = a.limbs[i] - b.limbs[i] - Word(result)
    result = new_a.isMsbSet()
    a.limbs[i] = ctl.mux(new_a and MaxWord, a.limbs[i])

# ############################################################
#
#                   Modular BigInt
#
# ############################################################

# TODO: push boundsCheck off. They would be extremely costly.

func shlAddMod[bits](a: var BigInt[bits], c: Word, M: BigInt[bits]) =
  ## Fused modular left-shift + add
  ## Shift input `a` by a word and add `c` modulo `M`
  ##
  ## With a word W = 2^WordBitSize and a modulus M
  ## Does a <- a * W + c (mod M)
  ##
  ## The modulus `M` **must** use `mBits` bits.
  assert not M.limbs[^1].isZero.bool, "The modulus must use all declared bits"

  const len = a.limbs.len

  when bits <= WordBitSize:
    # If M fits in a single limb
    var q: Word

    # (hi, lo) = a * 2^63 + c
    let hi = a.limbs[0] shr 1                        # 64 - 63 = 1
    let lo = (a.limbs[0] shl WordBitSize) or c       # Assumes most-significant bit in c is not set
    unsafeDiv2n1n(q, a.limbs[0], hi, lo, M.limbs[0]) # (hi, lo) mod M
    return

  else: # TODO replace moveMem with a proc that also works at compile-time
    ## Multiple limbs
    let hi = a.limbs[^1]                                               # Save the high word to detect carries
    const R = bits and WordBitSize                                     # R = bits mod 64

    when R == 0:                                                       # If the number of bits is a multiple of 64
      let a0 = a.limbs[^1]                                             #
      moveMem(a.limbs[1].addr, a.limbs[0].addr, (len-1) * Word.sizeof) # we can just shift words
      a.limbs[0] = c                                                   # and replace the first one by c
      let a1 = a.limbs[^1]
      let m0 = M.limbs[^1]
    else: # Need to deal with partial word shifts at the edge.
      let a0 = ((a.limbs[^1] shl (WordBitSize-R)) or (a.limbs[^2] shr R)) and MaxWord
      moveMem(a.limbs[1].addr, a.limbs[0].addr, (len-1) * Word.sizeof)
      a.limbs[0] = c
      let a1 = ((a.limbs[^1] shl (WordBitSize-R)) or (a.limbs[^2] shr R)) and MaxWord
      let m0 = ((M.limbs[^1] shl (WordBitSize-R)) or (M.limbs[^2] shr R)) and MaxWord

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
    var over_p = ctrue(Word)                       # Track if quotient greater than the modulus

    for i in static(0 ..< M.limbs.len):
      var qp_lo: Word

      block: # q*p
        var qp_hi: Word
        unsafeExtendedPrecMul(qp_hi, qp_lo, q, M.limbs[i])  # q * p
        # assert qp_lo.isMsbSet.not.bool
        # assert carry.isMsbSet.not.bool
        qp_lo += carry                                      # Add carry from previous limb
        let qp_carry = qp_lo.isMsbSet
        carry = mux(qp_carry, qp_hi + One, qp_hi)           # New carry

        qp_lo = qp_lo and MaxWord                           # Normalize to u63

      block: # a*2^63 - q*p
        a.limbs[i] -= qp_lo
        carry += Word(a.limbs[i].isMsbSet)                  # Adjust if borrow
        a.limbs[i] = a.limbs[i] and MaxWord                 # Normalize to u63

      over_p = mux(
                a.limbs[i] == M.limbs[i], over_p,
                a.limbs[i] > M.limbs[i]
              )

    # Fix quotient, the true quotient is either q-1, q or q+1
    #
    # if carry < q or carry == q and over_p we must do "a -= p"
    # if carry > hi (negative result) we must do "a += p"

    let neg = carry < hi
    let tooBig = not neg and (over_p or (carry < hi))

    discard a.add(M, ctl = neg)
    discard a.sub(M, ctl = tooBig)
    return

func reduce*[aBits, mBits](r: var BigInt[mBits], a: BigInt[aBits], M: BigInt[mBits]) =
  ## Reduce `a` modulo `M` and store the result in `r`
  ##
  ## The modulus `M` **must** use `mBits` bits.
  ##
  ## CT: Depends only on the length of the modulus `M`

  # Note: for all cryptographic intents and purposes the modulus is known at compile-time
  # but we don't want to inline it as it would increase codesize, better have Nim
  # pass a pointer+length to a fixed session of the BSS.

  assert not M.limbs[^1].isZero.bool, "The modulus must use all declared bits"

  when aBits < mBits:
    # if a uses less bits than the modulus,
    # it is guaranteed < modulus.
    # This relies on the precondition that the modulus uses all declared bits
    copyLimbs(r, 0, a, 0, a.limbs.len)
    r.setZero(a.limbs.len, r.limbs.len-1)
  else:
    # a length i at least equal to the modulus.
    # we can copy modulus.limbs-1 words
    # and modular shift-left-add the rest
    const aOffset = a.limbs.len - M.limbs.len
    copyLimbs(r, 0, a, aOffset, M.limbs.len - 1)
    r.limbs[^1] = Zero
    for i in countdown(aOffset, 0):
      r.shlAddMod(a.limbs[i], M)
