# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  ../config/[common, type_bigint],
  ../primitives,
  ./limbs,
  ./limbs_generic_modular,
  ./limbs_montgomery

export BigInt

# ############################################################
#
#                        BigInts
#
# ############################################################

# The API is exported as a building block
# with enforced compile-time checking of BigInt bitwidth
# and memory ownership.

# ############################################################
# Design
#
# Control flow should only depends on the static maximum number of bits
# This number is defined per Finite Field/Prime/Elliptic Curve
#
# Data Layout
#
# The previous implementation of Constantine used type-erased views
# to optimized code-size (1)
# Also instead of using the full 64-bit of an uint64 it used
# 63-bit with the last bit to handle carries (2)
#
# (1) brought an advantage in terms of code-size if multiple curves
# were supported.
# However it prevented unrolling for some performance critical routines
# like addition and Montgomery multiplication. Furthermore, addition
# is only 1 or 2 instructions per limbs meaning unrolling+inlining
# is probably smaller in code-size than a function call.
#
# (2) Not using the full 64-bit eased carry and borrow handling.
# Also on older x86 Arch, the add-with-carry "ADC" instruction
# may be up to 6x slower than plain "ADD" with memory operand in a carry-chain.
#
# However, recent CPUs (less than 5 years) have reasonable or lower ADC latencies
# compared to the shifting and masking required when using 63 bits.
# Also we save on words to iterate on (1 word for BN254, secp256k1, BLS12-381)
#
# Furthermore, pairing curves are not fast-reduction friendly
# meaning that lazy reductions and lazy carries are impractical
# and so it's simpler to always carry additions instead of
# having redundant representations that forces costly reductions before multiplications.
# https://github.com/mratsim/constantine/issues/15

# No exceptions allowed
{.push raises: [].}
{.push inline.}

# Initialization
# ------------------------------------------------------------

func setZero*(a: var BigInt) =
  ## Set a BigInt to 0
  a.limbs.setZero()

func setOne*(a: var BigInt) =
  ## Set a BigInt to 1
  a.limbs.setOne()

# Copy
# ------------------------------------------------------------

func ccopy*(a: var BigInt, b: BigInt, ctl: SecretBool) =
  ## Constant-time conditional copy
  ## If ctl is true: b is copied into a
  ## if ctl is false: b is not copied and a is untouched
  ## Time and memory accesses are the same whether a copy occurs or not
  ccopy(a.limbs, b.limbs, ctl)

func cswap*(a, b: var BigInt, ctl: CTBool) =
  ## Swap ``a`` and ``b`` if ``ctl`` is true
  ##
  ## Constant-time:
  ## Whether ``ctl`` is true or not, the same
  ## memory accesses are done (unless the compiler tries to be clever)
  cswap(a.limbs, b.limbs, ctl)

func copyTruncatedFrom*[dBits, sBits: static int](dst: var BigInt[dBits], src: BigInt[sBits]) =
  ## Copy `src` into `dst`
  ## if `dst` is not big enough, only the low words are copied
  ## if `src` is smaller than `dst` the higher words of `dst` will be overwritten

  for wordIdx in 0 ..< min(dst.limbs.len, src.limbs.len):
    dst.limbs[wordIdx] = src.limbs[wordIdx]
  for wordIdx in min(dst.limbs.len, src.limbs.len) ..< dst.limbs.len:
    dst.limbs[wordIdx] = SecretWord(0)

# Comparison
# ------------------------------------------------------------

func `==`*(a, b: BigInt): SecretBool =
  ## Returns true if 2 big ints are equal
  ## Comparison is constant-time
  a.limbs == b.limbs

func `<`*(a, b: BigInt): SecretBool =
  ## Returns true if a < b
  a.limbs < b.limbs

func `<=`*(a, b: BigInt): SecretBool =
  ## Returns true if a <= b
  a.limbs <= b.limbs

func isZero*(a: BigInt): SecretBool =
  ## Returns true if a big int is equal to zero
  a.limbs.isZero

func isOne*(a: BigInt): SecretBool =
  ## Returns true if a big int is equal to one
  a.limbs.isOne

func isOdd*(a: BigInt): SecretBool =
  ## Returns true if a is odd
  a.limbs.isOdd

func isMsbSet*(a: BigInt): SecretBool =
  ## Returns true if MSB is set
  ## i.e. if a BigInt is interpreted
  ## as signed AND the full bitwidth
  ## is not used by construction
  ## This is equivalent to checking
  ## if the number is negative

  # MSB is at announced bits - (wordsRequired - 1)
  const msb_pos = BigInt.bits-1 - (BigInt.bits.wordsRequired - 1)
  SecretBool((BaseType(a.limbs[a.limbs.len-1]) shr msb_pos) and 1)

func eq*(a: BigInt, n: SecretWord): SecretBool =
  ## Returns true if ``a`` is equal
  ## to the specified small word
  a.limbs.eq n

# Arithmetic
# ------------------------------------------------------------

func cadd*(a: var BigInt, b: BigInt, ctl: SecretBool): SecretBool =
  ## Constant-time in-place conditional addition
  ## The addition is only performed if ctl is "true"
  ## The result carry is always computed.
  (SecretBool) cadd(a.limbs, b.limbs, ctl)

func cadd*(a: var BigInt, b: SecretWord, ctl: SecretBool): SecretBool =
  ## Constant-time in-place conditional addition
  ## The addition is only performed if ctl is "true"
  ## The result carry is always computed.
  (SecretBool) cadd(a.limbs, b, ctl)

func csub*(a: var BigInt, b: BigInt, ctl: SecretBool): SecretBool =
  ## Constant-time in-place conditional substraction
  ## The substraction is only performed if ctl is "true"
  ## The result borrow is always computed.
  (SecretBool) csub(a.limbs, b.limbs, ctl)

func csub*(a: var BigInt, b: SecretWord, ctl: SecretBool): SecretBool =
  ## Constant-time in-place conditional substraction
  ## The substraction is only performed if ctl is "true"
  ## The result borrow is always computed.
  (SecretBool) csub(a.limbs, b, ctl)

func cdouble*(a: var BigInt, ctl: SecretBool): SecretBool =
  ## Constant-time in-place conditional doubling
  ## The doubling is only performed if ctl is "true"
  ## The result carry is always computed.
  (SecretBool) cadd(a.limbs, a.limbs, ctl)

func add*(a: var BigInt, b: BigInt): SecretBool =
  ## Constant-time in-place addition
  ## Returns the carry
  (SecretBool) add(a.limbs, b.limbs)

func add*(a: var BigInt, b: SecretWord): SecretBool =
  ## Constant-time in-place addition
  ## Returns the carry
  (SecretBool) add(a.limbs, b)

func `+=`*(a: var BigInt, b: BigInt) =
  ## Constant-time in-place addition
  ## Discards the carry
  discard add(a.limbs, b.limbs)

func `+=`*(a: var BigInt, b: SecretWord) =
  ## Constant-time in-place addition
  ## Discards the carry
  discard add(a.limbs, b)

func sub*(a: var BigInt, b: BigInt): SecretBool =
  ## Constant-time in-place substraction
  ## Returns the borrow
  (SecretBool) sub(a.limbs, b.limbs)

func sub*(a: var BigInt, b: SecretWord): SecretBool =
  ## Constant-time in-place substraction
  ## Returns the borrow
  (SecretBool) sub(a.limbs, b)

func `-=`*(a: var BigInt, b: BigInt) =
  ## Constant-time in-place substraction
  ## Discards the borrow
  discard sub(a.limbs, b.limbs)

func `-=`*(a: var BigInt, b: SecretWord) =
  ## Constant-time in-place substraction
  ## Discards the borrow
  discard sub(a.limbs, b)

func double*(a: var BigInt): SecretBool =
  ## Constant-time in-place doubling
  ## Returns the carry
  (SecretBool) add(a.limbs, a.limbs)

func sum*(r: var BigInt, a, b: BigInt): SecretBool =
  ## Sum `a` and `b` into `r`.
  ## `r` is initialized/overwritten
  ##
  ## Returns the carry
  (SecretBool) sum(r.limbs, a.limbs, b.limbs)

func diff*(r: var BigInt, a, b: BigInt): SecretBool =
  ## Substract `b` from `a` and store the result into `r`.
  ## `r` is initialized/overwritten
  ##
  ## Returns the borrow
  (SecretBool) diff(r.limbs, a.limbs, b.limbs)

func double*(r: var BigInt, a: BigInt): SecretBool =
  ## Double `a` into `r`.
  ## `r` is initialized/overwritten
  ##
  ## Returns the carry
  (SecretBool) sum(r.limbs, a.limbs, a.limbs)

func div2*(a: var BigInt) =
  ## In-place divide ``a`` by 2
  a.limbs.shiftRight(1)

func cneg*(a: var BigInt, ctl: CTBool) =
  ## Conditional negation.
  ## Negate if ``ctl`` is true
  a.limbs.cneg(ctl)

func prod*[rBits, aBits, bBits](r: var BigInt[rBits], a: BigInt[aBits], b: BigInt[bBits]) =
  ## Multi-precision multiplication
  ## r <- a*b
  ## `a`, `b`, `r` can have different sizes
  ## if r.bits < a.bits + b.bits
  ## the multiplication will overflow.
  ## It will be truncated if it cannot fit in r limbs.
  r.limbs.prod(a.limbs, b.limbs)

func mul*[aBits, bBits](a: var BigInt[aBits], b: BigInt[bBits]) =
  ## Multi-precision multiplication
  ## a <- a*b
  ## `a`, `b`, can have different sizes
  var t{.noInit.}: typeof(a)
  t.limbs.prod(a.limbs, b.limbs)
  a = t

func prod_high_words*[rBits, aBits, bBits](r: var BigInt[rBits], a: BigInt[aBits], b: BigInt[bBits], lowestWordIndex: static int) =
  ## Multi-precision multiplication keeping only high words
  ## r <- a*b >> (2^WordBitWidth)^lowestWordIndex
  ##
  ## `a`, `b`, `r` can have a different number of limbs
  ## if `r`.limbs.len < a.limbs.len + b.limbs.len - lowestWordIndex
  ## The result will be truncated, i.e. it will be
  ## a * b >> (2^WordBitWidth)^lowestWordIndex (mod (2^WordBitwidth)^r.limbs.len)
  ##
  # This is useful for
  # - Barret reduction
  # - Approximating multiplication by a fractional constant in the form f(a) = K/C * a
  #   with K and C known at compile-time.
  #   We can instead find a well chosen M = (2^WordBitWidth)^w, with M > C (i.e. M is a power of 2 bigger than C)
  #   Precompute P = K*M/C at compile-time
  #   and at runtime do P*a/M <=> P*a >> WordBitWidth*w
  #   i.e. prod_high_words(result, P, a, w)
  r.limbs.prod_high_words(a.limbs, b.limbs, lowestWordIndex)

# Bit Manipulation
# ------------------------------------------------------------

func shiftRight*(a: var BigInt, k: int) =
  ## Shift right by k.
  ##
  ## k MUST be less than the base word size (2^31 or 2^63)
  a.limbs.shiftRight(k)

func bit*[bits: static int](a: BigInt[bits], index: int): Ct[uint8] =
  ## Access an individual bit of `a`
  ## Bits are accessed as-if the bit representation is bigEndian
  ## for a 8-bit "big-integer" we have
  ## (b7, b6, b5, b4, b3, b2, b1, b0)
  ## for a 256-bit big-integer
  ## (b255, b254, ..., b1, b0)
  const SlotShift = log2(WordBitWidth.uint32)
  const SelectMask = WordBitWidth - 1
  const BitMask = SecretWord 1

  let slot = a.limbs[index shr SlotShift] # LimbEndianness is littleEndian
  result = ct(slot shr (index and SelectMask) and BitMask, uint8)

func bit0*(a: BigInt): Ct[uint8] =
  ## Access the least significant bit
  ct(a.limbs[0] and SecretWord(1), uint8)

# Multiplication by small cosntants
# ------------------------------------------------------------

func `*=`*(a: var BigInt, b: static int) {.inline.} =
  ## Multiplication by a small integer known at compile-time
  # Implementation:
  #
  # we hardcode addition chains for small integer
  const negate = b < 0
  const b = if negate: -b
            else: b
  when negate:
    a.neg(a)
  when b == 0:
    a.setZero()
  elif b == 1:
    return
  elif b == 2:
    discard a.double()
  elif b == 3:
    let t1 = a
    discard a.double()
    a += t1
  elif b == 4:
    discard a.double()
    discard a.double()
  elif b == 5:
    let t1 = a
    discard a.double()
    discard a.double()
    a += t1
  elif b == 6:
    discard a.double()
    let t2 = a
    discard a.double() # 4
    a += t2
  elif b == 7:
    let t1 = a
    discard a.double()
    let t2 = a
    discard a.double() # 4
    a += t2
    a += t1
  elif b == 8:
    discard a.double()
    discard a.double()
    discard a.double()
  elif b == 9:
    let t1 = a
    discard a.double()
    discard a.double()
    discard a.double() # 8
    a += t1
  elif b == 10:
    discard a.double()
    let t2 = a
    discard a.double()
    discard a.double() # 8
    a += t2
  elif b == 11:
    let t1 = a
    discard a.double()
    let t2 = a
    discard a.double()
    discard a.double() # 8
    a += t2
    a += t1
  elif b == 12:
    discard a.double()
    discard a.double() # 4
    let t4 = a
    discard a.double() # 8
    a += t4
  else:
    {.error: "Multiplication by this small int not implemented".}

func `*`*(b: static int, a: BigInt): BigInt {.noinit, inline.} =
  ## Multiplication by a small integer known at compile-time
  result = a
  result *= b

# ############################################################
#
#                   Modular BigInt
#
# ############################################################

func reduce*[aBits, mBits](r: var BigInt[mBits], a: BigInt[aBits], M: BigInt[mBits]) =
  ## Reduce `a` modulo `M` and store the result in `r`
  ##
  ## The modulus `M` **must** use `mBits` bits (bits at position mBits-1 must be set)
  ##
  ## CT: Depends only on the length of the modulus `M`

  # Note: for all cryptographic intents and purposes the modulus is known at compile-time
  # but we don't want to inline it as it would increase codesize, better have Nim
  # pass a pointer+length to a fixed session of the BSS.
  reduce(r.limbs, a.limbs, aBits, M.limbs, mBits)

func div2_modular*[bits](a: var BigInt[bits], mp1div2: BigInt[bits]) =
  ## Compute a <- a/2 (mod M)
  ## `mp1div2` is the modulus (M+1)/2
  ##
  ## Normally if `a` is odd we add the modulus before dividing by 2
  ## but this may overflow and we might lose a bit before shifting.
  ## Instead we shift first and then add half the modulus rounded up
  ##
  ## Assuming M is odd, `mp1div2` can be precomputed without
  ## overflowing the "Limbs" by dividing by 2 first
  ## and add 1
  ## Otherwise `mp1div2` should be M/2
  a.limbs.div2_modular(mp1div2.limbs)

func steinsGCD*[bits](r: var BigInt[bits], a, F, M, mp1div2: BigInt[bits]) =
  ## Compute F multiplied the modular inverse of ``a`` modulo M
  ## r ≡ F . a^-1 (mod M)
  ##
  ## M MUST be odd, M does not need to be prime.
  ## ``a`` MUST be less than M.
  r.limbs.steinsGCD(a.limbs, F.limbs, M.limbs, bits, mp1div2.limbs)

func invmod*[bits](r: var BigInt[bits], a, M, mp1div2: BigInt[bits]) =
  ## Compute the modular inverse of ``a`` modulo M
  ##
  ## The modulus ``M`` MUST be odd
  var one {.noInit.}: BigInt[bits]
  one.setOne()
  r.steinsGCD(a, one, M, mp1div2)

# ############################################################
#
#                 Montgomery Arithmetic
#
# ############################################################

func montyResidue*(mres: var BigInt, a, N, r2modM: BigInt, m0ninv: static BaseType, canUseNoCarryMontyMul: static bool) =
  ## Convert a BigInt from its natural representation
  ## to the Montgomery n-residue form
  ##
  ## `mres` is overwritten. It's bitlength must be properly set before calling this procedure.
  ##
  ## Caller must take care of properly switching between
  ## the natural and montgomery domain.
  ## Nesting Montgomery form is possible by applying this function twice.
  ##
  ## The Montgomery Magic Constants:
  ## - `m0ninv` is µ = -1/N (mod M)
  ## - `r2modM` is R² (mod M)
  ## with W = M.len
  ## and R = (2^WordBitSize)^W
  montyResidue(mres.limbs, a.limbs, N.limbs, r2modM.limbs, m0ninv, canUseNoCarryMontyMul)

func redc*[mBits](r: var BigInt[mBits], a, M: BigInt[mBits], m0ninv: static BaseType, canUseNoCarryMontyMul: static bool) =
  ## Convert a BigInt from its Montgomery n-residue form
  ## to the natural representation
  ##
  ## `mres` is modified in-place
  ##
  ## Caller must take care of properly switching between
  ## the natural and montgomery domain.
  let one = block:
    var one {.noInit.}: BigInt[mBits]
    one.setOne()
    one
  redc(r.limbs, a.limbs, one.limbs, M.limbs, m0ninv, canUseNoCarryMontyMul)

func montyMul*(r: var BigInt, a, b, M: BigInt, negInvModWord: static BaseType, canUseNoCarryMontyMul: static bool) =
  ## Compute r <- a*b (mod M) in the Montgomery domain
  ##
  ## This resets r to zero before processing. Use {.noInit.}
  ## to avoid duplicating with Nim zero-init policy
  montyMul(r.limbs, a.limbs, b.limbs, M.limbs, negInvModWord, canUseNoCarryMontyMul)

func montySquare*(r: var BigInt, a, M: BigInt, negInvModWord: static BaseType, canUseNoCarryMontyMul: static bool) =
  ## Compute r <- a^2 (mod M) in the Montgomery domain
  ##
  ## This resets r to zero before processing. Use {.noInit.}
  ## to avoid duplicating with Nim zero-init policy
  montySquare(r.limbs, a.limbs, M.limbs, negInvModWord, canUseNoCarryMontyMul)

func montyPow*[mBits: static int](
       a: var BigInt[mBits], exponent: openarray[byte],
       M, one: BigInt[mBits], negInvModWord: static BaseType, windowSize: static int,
       canUseNoCarryMontyMul, canUseNoCarryMontySquare: static bool
      ) =
  ## Compute a <- a^exponent (mod M)
  ## ``a`` in the Montgomery domain
  ## ``exponent`` is a BigInt in canonical big-endian representation
  ##
  ## Warning ⚠️ :
  ## This is an optimization for public exponent
  ## Otherwise bits of the exponent can be retrieved with:
  ## - memory access analysis
  ## - power analysis
  ## - timing analysis
  ##
  ## This uses fixed window optimization
  ## A window size in the range [1, 5] must be chosen

  const scratchLen = if windowSize == 1: 2
                     else: (1 shl windowSize) + 1
  var scratchSpace {.noInit.}: array[scratchLen, Limbs[mBits.wordsRequired]]
  montyPow(a.limbs, exponent, M.limbs, one.limbs, negInvModWord, scratchSpace, canUseNoCarryMontyMul, canUseNoCarryMontySquare)

func montyPowUnsafeExponent*[mBits: static int](
       a: var BigInt[mBits], exponent: openarray[byte],
       M, one: BigInt[mBits], negInvModWord: static BaseType, windowSize: static int,
       canUseNoCarryMontyMul, canUseNoCarryMontySquare: static bool
      ) =
  ## Compute a <- a^exponent (mod M)
  ## ``a`` in the Montgomery domain
  ## ``exponent`` is a BigInt in canonical big-endian representation
  ##
  ## Warning ⚠️ :
  ## This is an optimization for public exponent
  ## Otherwise bits of the exponent can be retrieved with:
  ## - memory access analysis
  ## - power analysis
  ## - timing analysis
  ##
  ## This uses fixed window optimization
  ## A window size in the range [1, 5] must be chosen

  const scratchLen = if windowSize == 1: 2
                     else: (1 shl windowSize) + 1
  var scratchSpace {.noInit.}: array[scratchLen, Limbs[mBits.wordsRequired]]
  montyPowUnsafeExponent(a.limbs, exponent, M.limbs, one.limbs, negInvModWord, scratchSpace, canUseNoCarryMontyMul, canUseNoCarryMontySquare)

func montyPow*[mBits, eBits: static int](
       a: var BigInt[mBits], exponent: BigInt[eBits],
       M, one: BigInt[mBits], negInvModWord: static BaseType, windowSize: static int,
       canUseNoCarryMontyMul, canUseNoCarryMontySquare: static bool
      ) =
  ## Compute a <- a^exponent (mod M)
  ## ``a`` in the Montgomery domain
  ## ``exponent`` is any BigInt, in the canonical domain
  ##
  ## This uses fixed window optimization
  ## A window size in the range [1, 5] must be chosen
  ##
  ## This is constant-time: the window optimization does
  ## not reveal the exponent bits or hamming weight
  mixin exportRawUint # exported in io_bigints which depends on this module ...

  var expBE {.noInit.}: array[(ebits + 7) div 8, byte]
  expBE.exportRawUint(exponent, bigEndian)

  montyPow(a, expBE, M, one, negInvModWord, windowSize, canUseNoCarryMontyMul, canUseNoCarryMontySquare)

func montyPowUnsafeExponent*[mBits, eBits: static int](
       a: var BigInt[mBits], exponent: BigInt[eBits],
       M, one: BigInt[mBits], negInvModWord: static BaseType, windowSize: static int,
       canUseNoCarryMontyMul, canUseNoCarryMontySquare: static bool
      ) =
  ## Compute a <- a^exponent (mod M)
  ## ``a`` in the Montgomery domain
  ## ``exponent`` is any BigInt, in the canonical domain
  ##
  ## Warning ⚠️ :
  ## This is an optimization for public exponent
  ## Otherwise bits of the exponent can be retrieved with:
  ## - memory access analysis
  ## - power analysis
  ## - timing analysis
  ##
  ## This uses fixed window optimization
  ## A window size in the range [1, 5] must be chosen
  mixin exportRawUint # exported in io_bigints which depends on this module ...

  var expBE {.noInit.}: array[(ebits + 7) div 8, byte]
  expBE.exportRawUint(exponent, bigEndian)

  montyPowUnsafeExponent(a, expBE, M, one, negInvModWord, windowSize, canUseNoCarryMontyMul, canUseNoCarryMontySquare)

{.pop.} # inline
{.pop.} # raises no exceptions
