# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  ../../platforms/abstractions,
  ../config/type_bigint,
  ./limbs,
  ./limbs_extmul,
  ./limbs_exgcd,
  ../../math_arbitrary_precision/arithmetic/limbs_divmod

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
{.push raises: [], checks: off.}
{.push inline.}

# Initialization
# ------------------------------------------------------------

func setZero*(a: var BigInt) =
  ## Set a BigInt to 0
  a.limbs.setZero()

func setOne*(a: var BigInt) =
  ## Set a BigInt to 1
  a.limbs.setOne()

func setUint*(a: var BigInt, n: SomeUnsignedInt) =
  ## Set a BigInt to a machine-sized integer ``n``
  a.limbs.setUint(n)

func csetZero*(a: var BigInt, ctl: SecretBool) =
  ## Set ``a`` to 0 if ``ctl`` is true
  a.limbs.csetZero(ctl)

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
    dst.limbs[wordIdx] = Zero

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

func isEven*(a: BigInt): SecretBool =
  ## Returns true if a is even
  a.limbs.isEven

func isMsbSet*(a: BigInt): SecretBool =
  ## Returns true if MSB is set
  ## i.e. if a BigInt is interpreted
  ## as signed AND the full bitwidth
  ## is not used by construction
  ## This is equivalent to checking
  ## if the number is negative

  # MSB is at announced bits - (wordsRequired-1)*WordBitWidth - 1
  const msb_in_msw = BigInt.bits - (BigInt.bits.wordsRequired-1)*WordBitWidth - 1
  SecretBool((BaseType(a.limbs[a.limbs.len-1]) shr msb_in_msw) and 1)

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
  ##
  ## Truncation is at limb-level NOT bitlevel
  ## It is recommended to only use
  ## rBits >= aBits + bBits unless you know what you are doing.
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
  ## a * b >> (2^WordBitWidth)^lowestWordIndex (mod (2^WordBitWidth)^r.limbs.len)
  ##
  # This is useful for
  # - Barret reduction
  # - Approximating multiplication by a fractional constant in the form f(a) = K/C * a
  #   with K and C known at compile-time.
  #   We can instead find a well chosen M = (2^WordBitWidth)ʷ, with M > C (i.e. M is a power of 2 bigger than C)
  #   Precompute P = K*M/C at compile-time
  #   and at runtime do P*a/M <=> P*a >> WordBitWidth*w
  #   i.e. prod_high_words(result, P, a, w)
  r.limbs.prod_high_words(a.limbs, b.limbs, lowestWordIndex)

func square*[rBits, aBits](r: var BigInt[rBits], a: BigInt[aBits]) =
  ## Multi-precision squaring
  ## r <- a²
  ## `a`, `r` can have different sizes
  ## if r.bits < a.bits * 2
  ## the multiplication will overflow.
  ## It will be truncated if it cannot fit in r limbs.
  ##
  ## Truncation is at limb-level NOT bitlevel
  ## It is recommended to only use
  ## rBits >= aBits * 2 unless you know what you are doing.
  r.limbs.square(a.limbs)

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
  const SlotShift = log2_vartime(WordBitWidth.uint32)
  const SelectMask = WordBitWidth - 1
  const BitMask = One

  let slot = a.limbs[index shr SlotShift] # LimbEndianness is littleEndian
  result = ct(slot shr (index and SelectMask) and BitMask, uint8)

func bit0*(a: BigInt): Ct[uint8] =
  ## Access the least significant bit
  ct(a.limbs[0] and One, uint8)

func setBit*[bits: static int](a: var BigInt[bits], index: int) =
  ## Set an individual bit of `a` to 1.
  ## This has no effect if it is already 1
  const SlotShift = log2_vartime(WordBitWidth.uint32)
  const SelectMask = WordBitWidth - 1

  let slot = a.limbs[index shr SlotShift].addr
  let shifted = One shl (index and SelectMask)
  slot[] = slot[] or shifted

func getWindowAt*(a: BigInt, bitIndex: int, windowSize: static int): SecretWord {.inline.} =
  ## Access a window of `a` of size bitsize
  static: doAssert windowSize <= WordBitWidth

  const SlotShift = log2_vartime(WordBitWidth.uint32)
  const WordMask = WordBitWidth - 1
  const WindowMask = SecretWord((1 shl windowSize) - 1)

  let slot     = bitIndex shr SlotShift
  let word     = a.limbs[slot]                    # word in limbs
  let pos      = bitIndex and WordMask            # position in the word

  # This is constant-time, the branch does not depend on secret data.
  if pos + windowSize > WordBitWidth and slot+1 < a.limbs.len:
    # Read next word as well
    return ((word shr pos) or (a.limbs[slot+1] shl (WordBitWidth-pos))) and WindowMask
  else:
    return (word shr pos) and WindowMask

# Multiplication by small constants
# ------------------------------------------------------------

func `*=`*(a: var BigInt, b: static int) =
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

# Division by constants
# ------------------------------------------------------------

func div2*(a: var BigInt) =
  ## In-place divide ``a`` by 2
  a.limbs.shiftRight(1)

func div10*(a: var BigInt): SecretWord =
  ## In-place divide ``a`` by 10
  ## and return the remainder
  a.limbs.div10()

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

func invmod*[bits](
       r: var BigInt[bits],
       a, F, M: BigInt[bits]) =
  ## Compute the modular inverse of ``a`` modulo M
  ## r ≡ F.a⁻¹ (mod M)
  ##
  ## M MUST be odd, M does not need to be prime.
  ## ``a`` MUST be less than M.
  r.limbs.invmod(a.limbs, F.limbs, M.limbs, bits)

func invmod*[bits](
       r: var BigInt[bits],
       a: BigInt[bits],
       F, M: static BigInt[bits]) =
  ## Compute the modular inverse of ``a`` modulo M
  ## r ≡ F.a⁻¹ (mod M)
  ##
  ## with F and M known at compile-time
  ##
  ## M MUST be odd, M does not need to be prime.
  ## ``a`` MUST be less than M.
  r.limbs.invmod(a.limbs, F.limbs, M.limbs, bits)

func invmod*[bits](r: var BigInt[bits], a, M: BigInt[bits]) =
  ## Compute the modular inverse of ``a`` modulo M
  ##
  ## The modulus ``M`` MUST be odd
  var one {.noInit.}: BigInt[bits]
  one.setOne()
  r.invmod(a, one, M)

{.pop.} # inline

# ############################################################
#
#                   **Variable-Time**
#
# ############################################################

{.push inline.}

func invmod_vartime*[bits](
       r: var BigInt[bits],
       a, F, M: BigInt[bits]) {.tags: [VarTime].} =
  ## Compute the modular inverse of ``a`` modulo M
  ## r ≡ F.a⁻¹ (mod M)
  ##
  ## M MUST be odd, M does not need to be prime.
  ## ``a`` MUST be less than M.
  r.limbs.invmod_vartime(a.limbs, F.limbs, M.limbs, bits)

func invmod_vartime*[bits](
       r: var BigInt[bits],
       a: BigInt[bits],
       F, M: static BigInt[bits]) {.tags: [VarTime].} =
  ## Compute the modular inverse of ``a`` modulo M
  ## r ≡ F.a⁻¹ (mod M)
  ##
  ## with F and M known at compile-time
  ##
  ## M MUST be odd, M does not need to be prime.
  ## ``a`` MUST be less than M.
  r.limbs.invmod_vartime(a.limbs, F.limbs, M.limbs, bits)

func invmod_vartime*[bits](r: var BigInt[bits], a, M: BigInt[bits]) {.tags: [VarTime].} =
  ## Compute the modular inverse of ``a`` modulo M
  ##
  ## The modulus ``M`` MUST be odd
  var one {.noInit.}: BigInt[bits]
  one.setOne()
  r.invmod_vartime(a, one, M)

{.pop.}

# ############################################################
#
#                   Recoding
#
# ############################################################
#
# Litterature
#
# - Elliptic Curves in Cryptography
#   Blake, Seroussi, Smart, 1999
#
# - Efficient Arithmetic on Koblitz Curves
#   Jerome A. Solinas, 2000
#   https://decred.org/research/solinas2000.pdf
#
# - Optimal Left-to-Right Binary Signed-Digit Recoding
#   Joye, Yen, 2000
#   https://marcjoye.github.io/papers/JY00sd2r.pdf
#
# - Guide to Elliptic Curve Cryptography
#   Hankerson, Menezes, Vanstone, 2004
#
# - Signed Binary Representations Revisited
#   Katsuyuki Okeya, Katja Schmidt-Samoa, Christian Spahn, and Tsuyoshi Takagi, 2004
#   https://eprint.iacr.org/2004/195.pdf
#
# - Some Explicit Formulae of NAF and its Left-to-Right Analogue
#   Dong-Guk Han, Tetsuya Izu, and Tsuyoshi Takagi
#   https://eprint.iacr.org/2005/384.pdf
#
# See also on Booth encoding and Modified Booth Encoding (bit-pair recoding)
# - https://www.ece.ucdavis.edu/~bbaas/281/notes/Handout.booth.pdf
# - https://vulms.vu.edu.pk/Courses/CS501/Downloads/Booth%20and%20bit%20pair%20encoding.pdf
# - https://vulms.vu.edu.pk/Courses/CS501/Downloads/Bit-Pair%20Recoding.pdf
# - http://www.ecs.umass.edu/ece/koren/arith/simulator/ModBooth/

iterator recoding_l2r_signed_vartime*[bits: static int](a: BigInt[bits]): int8 =
  ## This is a minimum-Hamming-Weight left-to-right recoding.
  ## It outputs signed {-1, 0, 1} bits from MSB to LSB
  ## with minimal Hamming Weight to minimize operations
  ## in Miller Loops and vartime scalar multiplications
  ##
  ## ⚠️ While the recoding is constant-time,
  ##   usage of this recoding is intended vartime

  # As the caller is copy-pasted at each yield
  # we rework the algorithm so that we have a single yield point
  # We rely on the compiler for loop hoisting and/or loop peeling

  var bi, bi1, ri, ri1, ri2: int8

  var i = bits
  while true:     # JY00 outputs at mots bits+1 digits
    if i == bits: # We rely on compiler to hoist this branch out of the loop.
      ri = 0
      ri1 = int8 a.bit(bits-1)
      ri2 = int8 a.bit(bits-2)
      bi = 0
    else:
      bi = bi1
      ri = ri1
      ri1 = ri2
      if i < 2:
        ri2 = 0
      else:
        ri2 = int8 a.bit(i-2)

    bi1 = (bi + ri1 + ri2) shr 1
    let r = -2*bi + ri + bi1
    yield r

    if i != 0:
      i -= 1
    else:
      break

func recode_l2r_signed_vartime*[bits: static int](
       recoded: var array[bits+1, SomeSignedInt], a: BigInt[bits]): int {.tags:[VarTime].} =
  ## Recode left-to-right (MSB to LSB)
  ## Output from most significant to least significant
  ## Returns the number of bits used
  type I = SomeSignedInt
  var i = 0
  for bit in a.recoding_l2r_signed_vartime():
    recoded[i] = I(bit)
    inc i
  return i

iterator recoding_r2l_signed_vartime*[bits: static int](a: BigInt[bits]): int8 =
  ## This is a minimum-Hamming-Weight left-to-right recoding.
  ## It outputs signed {-1, 0, 1} bits from LSB to MSB
  ## with minimal Hamming Weight to minimize operations
  ## in Miller Loops and vartime scalar multiplications
  ##
  ## ⚠️ While the recoding is constant-time,
  ##   usage of this recoding is intended vartime
  ##
  ## Implementation uses 2-NAF
  # This is equivalent to `var r = (3a - a); if (r and 1) == 0: r shr 1`
  var ci, ci1, ri, ri1: int8

  var i = 0
  while i <= bits: # 2-NAF outputs at most bits+1 digits
    if i == 0:     # We rely on compiler to hoist this branch out of the loop.
      ri = int8 a.bit(0)
      ri1 = int8 a.bit(1)
      ci = 0
    else:
      ci = ci1
      ri = ri1
      if i >= bits - 1:
        ri1 = 0
      else:
        ri1 = int8 a.bit(i+1)

    ci1 = (ci + ri + ri1) shr 1
    let r = ci + ri - 2*ci1
    yield r

    i += 1

func recode_r2l_signed_vartime*[bits: static int](
       recoded: var array[bits+1, SomeSignedInt], a: BigInt[bits]): int {.tags:[VarTime].} =
  ## Recode right-to-left (LSB to MSB)
  ## Output from least significant to most significant
  ## Returns the number of bits used
  type I = SomeSignedInt
  var i = 0
  for bit in a.recoding_r2l_signed_vartime():
    recoded[i] = I(bit)
    inc i
  return i

iterator recoding_r2l_signed_window_vartime*[bits: static int](a: BigInt[bits], windowLogSize: int): int {.tags:[VarTime].} =
  ## This is a minimum-Hamming-Weight right-to-left windowed recoding with the following properties
  ## 1. The most significant non-zero bit is positive.
  ## 2. Among any w consecutive digits, at most one is non-zero.
  ## 3. Each non-zero digit is odd and less than 2ʷ⁻¹ in absolute value.
  ## 4. The length of the recoding is at most BigInt.bits + 1
  ##
  ## This returns input one digit at a time and not the whole window.
  ##
  ## ⚠️ not constant-time

  let sMax = 1 shl (windowLogSize - 1)
  let uMax = sMax + sMax
  let mask = uMax - 1

  var a {.noInit.} = a
  var zeroes = 0

  var j = 0
  while j <= bits:
    # 1. Count zeroes in LSB
    var ctz = 0
    for i in 0 ..< a.limbs.len:
      let ai = a.limbs[i]
      if ai.isZero().bool:
        ctz += WordBitWidth
      else:
        ctz += BaseType(ai).countTrailingZeroBits_vartime().int
        break

    # 2. Remove them
    if ctz >= WordBitWidth:
      let wordOffset = int(ctz shr log2_vartime(uint32 WordBitWidth))
      for i in 0 ..< a.limbs.len-wordOffset:
        a.limbs[i] = a.limbs[i+wordOffset]
      for i in a.limbs.len-wordOffset ..< a.limbs.len:
        a.limbs[i] = Zero
      ctz = ctz and (WordBitWidth-1)
      zeroes += wordOffset * WordBitWidth
    if ctz > 0:
      a.shiftRight(ctz)
      zeroes += ctz

    # 3. Yield - We merge yield points with a goto-based state machine
    # Nim copy-pastes the iterator for-loop body at yield points, we don't want to duplicate code
    # hence we need a single yield point

    type State = enum
      StatePrepareYield
      StateYield
      StateExit

    var yieldVal = 0
    var nextState = StatePrepareYield

    var state {.goto.} = StatePrepareYield
    case state
    of StatePrepareYield:
      # 3.a Yield zeroes
      zeroes -= 1
      if zeroes >= 0:
        state = StateYield # goto StateYield

      # 3.b Yield the least significant window
      var lsw = a.limbs[0].int and mask # signed is important
      a.shiftRight(windowLogSize)
      if (lsw and sMax) != 0:           # MSB of window set
        a += One                        #   Lend 2ʷ to next digit
        lsw -= uMax                     #   push from [0, 2ʷ) to [-2ʷ⁻¹, 2ʷ⁻¹)

      zeroes = windowLogSize-1
      yieldVal = lsw
      nextState = StateExit
      # Fall through StateYield

    of StateYield:
      yield yieldVal
      j += 1
      if j > bits: # wNAF outputs at most bits+1 digits
        break
      case nextState
      of StatePrepareYield: state = StatePrepareYield
      of StateExit:         state = StateExit
      else:                 unreachable()

    of StateExit:
      if a.isZero().bool:
        break

func recode_r2l_signed_window_vartime*[bits: static int](
       naf: var array[bits+1, SomeSignedInt], a: BigInt[bits], window: int): int {.tags:[VarTime].} =
  ## Minimum Hamming-Weight windowed NAF recoding
  ## Output from least significant to most significant
  ## Returns the number of bits used
  ##
  ## The `naf` output is returned one digit at a time and not one window at a time
  type I = SomeSignedInt
  var i = 0
  for digit in a.recoding_r2l_signed_window_vartime(window):
    naf[i] = I(digit)
    i += 1
  return i

func signedWindowEncoding(digit: SecretWord, bitsize: static int): tuple[val: SecretWord, neg: SecretBool] {.inline.} =
  ## Get the signed window encoding for `digit`
  ##
  ## This uses the fact that 999 = 100 - 1
  ## It replaces string of binary 1 with 1...-1
  ## i.e. 0111 becomes 1 0 0 -1
  ##
  ## This looks at [bitᵢ₊ₙ..bitᵢ | bitᵢ₋₁]
  ## and encodes   [bitᵢ₊ₙ..bitᵢ]
  ##
  ## Notes:
  ##   - This is not a minimum weight encoding unlike NAF
  ##   - Due to constant-time requirement in scalar multiplication
  ##     or bucketing large window in multi-scalar-multiplication
  ##     minimum weight encoding might not lead to saving operations
  ##   - Unlike NAF and wNAF encoding, there is no carry to propagate
  ##     hence this is suitable for parallelization without encoding precomputation
  ##     and for GPUs
  ##   - Implementation uses Booth encoding
  result.neg = SecretBool(digit shr bitsize)

  let negMask = -SecretWord(result.neg)
  const valMask = SecretWord((1 shl bitsize) - 1)

  let encode = (digit + One) shr 1            # Lookup bitᵢ₋₁, flip series of 1's
  result.val = (encode + negMask) xor negMask # absolute value
  result.val = result.val and valMask

func getSignedFullWindowAt*(a: BigInt, bitIndex: int, windowSize: static int): tuple[val: SecretWord, neg: SecretBool] {.inline.} =
  ## Access a signed window of `a` of size bitsize
  ## Returns a signed encoding.
  ##
  ## The result is `windowSize` bits at a time.
  ##
  ## bitIndex != 0 and bitIndex mod windowSize == 0
  debug: doAssert (bitIndex != 0) and (bitIndex mod windowSize) == 0
  let digit = a.getWindowAt(bitIndex-1, windowSize+1) # get the bit on the right of the window for Booth encoding
  return digit.signedWindowEncoding(windowSize)

func getSignedBottomWindow*(a: BigInt, windowSize: static int): tuple[val: SecretWord, neg: SecretBool] {.inline.} =
  ## Access the least significant signed window of `a` of size bitsize
  ## Returns a signed encoding.
  ##
  ## The result is `windowSize` bits at a time.
  let digit = a.getWindowAt(0, windowSize) shl 1 # Add implicit 0 on the right of LSB for Booth encoding
  return digit.signedWindowEncoding(windowSize)

func getSignedTopWindow*(a: BigInt, topIndex: int, excess: static int): tuple[val: SecretWord, neg: SecretBool] {.inline.} =
  ## Access the least significant signed window of `a` of size bitsize
  ## Returns a signed encoding.
  ##
  ## The result is `excess` bits at a time.
  ##
  ## bitIndex != 0 and bitIndex mod windowSize == 0
  let digit = a.getWindowAt(topIndex-1, excess+1) # Add implicit 0 on the left of MSB and get the bit on the right of the window
  return digit.signedWindowEncoding(excess+1)

{.pop.} # raises no exceptions
