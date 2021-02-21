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
  ./limbs_extmul,
  ./limbs_invmod,
  ./limbs_modular,
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

func setUint*(a: var BigInt, n: SomeUnsignedInt) =
  ## Set a BigInt to a machine-sized integer ``n``
  a.limbs.setUint(n)

func czero*(a: var BigInt, ctl: SecretBool) =
  ## Set ``a`` to 0 if ``ctl`` is true
  a.limbs.czero(ctl)

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

# Multiplication by small cosntants
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

func mollerGCD*[bits](r: var BigInt[bits], a, F, M, mp1div2: BigInt[bits]) =
  ## Compute F multiplied the modular inverse of ``a`` modulo M
  ## r ≡ F . a^-1 (mod M)
  ##
  ## M MUST be odd, M does not need to be prime.
  ## ``a`` MUST be less than M.
  r.limbs.mollerGCD(a.limbs, F.limbs, M.limbs, bits, mp1div2.limbs)

func invmod*[bits](r: var BigInt[bits], a, M, mp1div2: BigInt[bits]) =
  ## Compute the modular inverse of ``a`` modulo M
  ##
  ## The modulus ``M`` MUST be odd
  var one {.noInit.}: BigInt[bits]
  one.setOne()
  r.mollerGCD(a, one, M, mp1div2)

{.pop.} # inline
{.pop.} # raises no exceptions
