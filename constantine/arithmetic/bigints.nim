# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  ../config/common,
  ../primitives,
  ./limbs, ./limbs_montgomery, ./limbs_modular

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

func wordsRequired(bits: int): int {.compileTime.} =
  ## Compute the number of limbs required
  # from the **announced** bit length
  (bits + WordBitWidth - 1) div WordBitWidth

type
  BigInt*[bits: static int] = object
    ## Fixed-precision big integer
    ##
    ## - "bits" is the announced bit-length of the BigInt
    ##   This is public data, usually equal to the curve prime bitlength.
    ##
    ## - "limbs" is an internal field that holds the internal representation
    ##   of the big integer. Least-significant limb first. Within limbs words are native-endian.
    ##
    ## This internal representation can be changed
    ## without notice and should not be used by external applications or libraries.
    limbs*: array[bits.wordsRequired, SecretWord]

# For unknown reason, `bits` doesn't semcheck if
#   `limbs: Limbs[bits.wordsRequired]`
# with
#   `Limbs[N: static int] = distinct array[N, SecretWord]`
# so we don't set Limbs as a distinct type

debug:
  import strutils

  func `$`*(a: BigInt): string =
    result = "BigInt["
    result.add $BigInt.bits
    result.add "](limbs: "
    result.add a.limbs.toString()
    result.add ")"

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

# Arithmetic
# ------------------------------------------------------------

func cadd*(a: var BigInt, b: BigInt, ctl: SecretBool): SecretBool =
  ## Constant-time in-place conditional addition
  ## The addition is only performed if ctl is "true"
  ## The result carry is always computed.
  (SecretBool) cadd(a.limbs, b.limbs, ctl)

func csub*(a: var BigInt, b: BigInt, ctl: SecretBool): SecretBool =
  ## Constant-time in-place conditional addition
  ## The addition is only performed if ctl is "true"
  ## The result carry is always computed.
  (SecretBool) csub(a.limbs, b.limbs, ctl)

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

func `+=`*(a: var BigInt, b: SecretWord) =
  ## Constant-time in-pace addition
  ## Discards the carry
  discard add(a.limbs, b)

func sub*(a: var BigInt, b: BigInt): SecretBool =
  ## Constant-time in-place substraction
  ## Returns the borrow
  (SecretBool) sub(a.limbs, b.limbs)

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
  result = ct[uint8](slot shr (index and SelectMask) and BitMask)

func bit0*(a: BigInt): Ct[uint8] =
  ## Access the least significant bit
  ct[uint8](a.limbs[0] and SecretWord(1))

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

func div2mod*[bits](a: var BigInt[bits], mp1div2: BigInt[bits]) =
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
  a.limbs.div2mod(mp1div2.limbs)

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

  const scratchLen = if windowSize == 1: 2
                     else: (1 shl windowSize) + 1
  var scratchSpace {.noInit.}: array[scratchLen, Limbs[mBits.wordsRequired]]
  montyPow(a.limbs, expBE, M.limbs, one.limbs, negInvModWord, scratchSpace, canUseNoCarryMontyMul, canUseNoCarryMontySquare)

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

  const scratchLen = if windowSize == 1: 2
                     else: (1 shl windowSize) + 1
  var scratchSpace {.noInit.}: array[scratchLen, Limbs[mBits.wordsRequired]]
  montyPowUnsafeExponent(a.limbs, expBE, M.limbs, one.limbs, negInvModWord, scratchSpace, canUseNoCarryMontyMul, canUseNoCarryMontySquare)

func montyPowUnsafeExponent*[mBits: static int](
       a: var BigInt[mBits], exponent: openarray[byte],
       M, one: BigInt[mBits], negInvModWord: static BaseType, windowSize: static int,
       canUseNoCarryMontyMul, canUseNoCarryMontySquare: static bool
      ) =
  ## Compute a <- a^exponent (mod M)
  ## ``a`` in the Montgomery domain
  ## ``exponent`` is a BigInt in canonical representation
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

{.pop.} # inline
{.pop.} # raises no exceptions
