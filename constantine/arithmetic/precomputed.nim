# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  ./bigints,
  ../primitives/constant_time,
  ../config/common,
  ../io/io_bigints

# Precomputed constants
# ############################################################

# ############################################################
#
#                   Modular primitives
#
# ############################################################
#
# Those primitives are intended to be compile-time only
# Those are NOT tagged compile-time, using CTBool seems to confuse the VM

# We don't use distinct types here, they confuse the VM
# Similarly, using addC / subB confuses the VM

# As we choose to use the full 32/64 bits of the integers and there is no carry flag
# in the compile-time VM we need a portable (and slow) "adc" and "sbb".
# Hopefully compilation time stays decent.

const
  HalfWidth = WordBitWidth shr 1
  HalfBase = (BaseType(1) shl HalfWidth)
  HalfMask = HalfBase - 1

func split(n: BaseType): tuple[hi, lo: BaseType] =
  result.hi = n shr HalfWidth
  result.lo = n and HalfMask

func merge(hi, lo: BaseType): BaseType =
  (hi shl HalfWidth) or lo

func addC(cOut, sum: var BaseType, a, b, cIn: BaseType) =
  # Add with carry, fallback for the Compile-Time VM
  # (CarryOut, Sum) <- a + b + CarryIn
  let (aHi, aLo) = split(a)
  let (bHi, bLo) = split(b)
  let tLo = aLo + bLo + cIn
  let (cLo, rLo) = split(tLo)
  let tHi = aHi + bHi + cLo
  let (cHi, rHi) = split(tHi)
  cOut = cHi
  sum = merge(rHi, rLo)

func subB(bOut, diff: var BaseType, a, b, bIn: BaseType) =
  # Substract with borrow, fallback for the Compile-Time VM
  # (BorrowOut, Sum) <- a - b - BorrowIn
  let (aHi, aLo) = split(a)
  let (bHi, bLo) = split(b)
  let tLo = HalfBase + aLo - bLo - bIn
  let (noBorrowLo, rLo) = split(tLo)
  let tHi = HalfBase + aHi - bHi - BaseType(noBorrowLo == 0)
  let (noBorrowHi, rHi) = split(tHi)
  bOut = BaseType(noBorrowHi == 0)
  diff = merge(rHi, rLo)

func add(a: var BigInt, w: BaseType): bool =
  ## Limbs addition, add a number that fits in a word
  ## Returns the carry
  var carry, sum: BaseType
  addC(carry, sum, BaseType(a.limbs[0]), w, carry)
  a.limbs[0] = SecretWord(sum)
  for i in 1 ..< a.limbs.len:
    let ai = BaseType(a.limbs[i])
    addC(carry, sum, ai, 0, carry)
    a.limbs[i] = SecretWord(sum)

  result = bool(carry)

func dbl(a: var BigInt): bool =
  ## In-place multiprecision double
  ##   a -> 2a
  var carry, sum: BaseType
  for i in 0 ..< a.limbs.len:
    let ai = BaseType(a.limbs[i])
    addC(carry, sum, ai, ai, carry)
    a.limbs[i] = SecretWord(sum)

  result = bool(carry)

func sub(a: var BigInt, w: BaseType): bool =
  ## Limbs substraction, sub a number that fits in a word
  ## Returns the carry
  var borrow, diff: BaseType
  subB(borrow, diff, BaseType(a.limbs[0]), w, borrow)
  a.limbs[0] = SecretWord(diff)
  for i in 1 ..< a.limbs.len:
    let ai = BaseType(a.limbs[i])
    subB(borrow, diff, ai, 0, borrow)
    a.limbs[i] = SecretWord(diff)

  result = bool(borrow)

func cadd(a: var BigInt, b: BigInt, ctl: bool): bool =
  ## In-place optional addition
  ##
  ## It is NOT constant-time and is intended
  ## only for compile-time precomputation
  ## of non-secret data.
  var carry, sum: BaseType
  for i in 0 ..< a.limbs.len:
    let ai = BaseType(a.limbs[i])
    let bi = BaseType(b.limbs[i])
    addC(carry, sum, ai, bi, carry)
    if ctl:
      a.limbs[i] = SecretWord(sum)

  result = bool(carry)

func csub(a: var BigInt, b: BigInt, ctl: bool): bool =
  ## In-place optional substraction
  ##
  ## It is NOT constant-time and is intended
  ## only for compile-time precomputation
  ## of non-secret data.
  var borrow, diff: BaseType
  for i in 0 ..< a.limbs.len:
    let ai = BaseType(a.limbs[i])
    let bi = BaseType(b.limbs[i])
    subB(borrow, diff, ai, bi, borrow)
    if ctl:
      a.limbs[i] = SecretWord(diff)

  result = bool(borrow)

func doubleMod(a: var BigInt, M: BigInt) =
  ## In-place modular double
  ##   a -> 2a (mod M)
  ##
  ## It is NOT constant-time and is intended
  ## only for compile-time precomputation
  ## of non-secret data.
  var ctl = dbl(a)
  ctl = ctl or not a.csub(M, false)
  discard csub(a, M, ctl)

# ############################################################
#
#          Montgomery Magic Constants precomputation
#
# ############################################################

func checkOddModulus(M: BigInt) =
  doAssert bool(BaseType(M.limbs[0]) and 1), "Internal Error: the modulus must be odd to use the Montgomery representation."

func checkValidModulus(M: BigInt) =
  const expectedMsb = M.bits-1 - WordBitWidth * (M.limbs.len - 1)
  let msb = log2(BaseType(M.limbs[^1]))

  doAssert msb == expectedMsb, "Internal Error: the modulus must use all declared bits and only those"

func useNoCarryMontyMul*(M: BigInt): bool =
  ## Returns if the modulus is compatible
  ## with the no-carry Montgomery Multiplication
  ## from https://hackmd.io/@zkteam/modular_multiplication
  # Indirection needed because static object are buggy
  # https://github.com/nim-lang/Nim/issues/9679
  BaseType(M.limbs[^1]) < high(BaseType) shr 1

func useNoCarryMontySquare*(M: BigInt): bool =
  ## Returns if the modulus is compatible
  ## with the no-carry Montgomery Squaring
  ## from https://hackmd.io/@zkteam/modular_multiplication
  # Indirection needed because static object are buggy
  # https://github.com/nim-lang/Nim/issues/9679
  BaseType(M.limbs[^1]) < high(BaseType) shr 2

func negInvModWord*(M: BigInt): BaseType =
  ## Returns the Montgomery domain magic constant for the input modulus:
  ##
  ##   µ ≡ -1/M[0] (mod SecretWord)
  ##
  ## M[0] is the least significant limb of M
  ## M must be odd and greater than 2.
  ##
  ## Assuming 64-bit words:
  ##
  ## µ ≡ -1/M[0] (mod 2^64)

  # We use BaseType for return value because static distinct type
  # confuses Nim semchecks [UPSTREAM BUG]
  # We don't enforce compile-time evaluation here
  # because static BigInt[bits] also causes semcheck troubles [UPSTREAM BUG]

  # Modular inverse algorithm:
  # Explanation p11 "Dumas iterations" based on Newton-Raphson:
  # - Cetin Kaya Koc (2017), https://eprint.iacr.org/2017/411
  # - Jean-Guillaume Dumas (2012), https://arxiv.org/pdf/1209.6626v2.pdf
  # - Colin Plumb (1994), http://groups.google.com/groups?selm=1994Apr6.093116.27805%40mnemosyne.cs.du.edu
  # Other sources:
  # - https://crypto.stackexchange.com/questions/47493/how-to-determine-the-multiplicative-inverse-modulo-64-or-other-power-of-two
  # - https://mumble.net/~campbell/2015/01/21/inverse-mod-power-of-two
  # - http://marc-b-reynolds.github.io/math/2017/09/18/ModInverse.html

  # For Montgomery magic number, we are in a special case
  # where a = M and m = 2^WordBitWidth.
  # For a and m to be coprimes, a must be odd.

  # We have the following relation
  # ax ≡ 1 (mod 2^k) <=> ax(2 - ax) ≡ 1 (mod 2^(2k))
  #
  # To get  -1/M0 mod LimbSize
  # we can negate the result x of `ax(2 - ax) ≡ 1 (mod 2^(2k))`
  # or if k is odd: do ax(2 + ax) ≡ 1 (mod 2^(2k))
  #
  # To get the the modular inverse of 2^k' with arbitrary k'
  # we can do modInv(a, 2^64) mod 2^63 as mentionned in Koc paper.

  checkOddModulus(M)
  checkValidModulus(M)

  let
    M0 = BaseType(M.limbs[0])
    k = log2(WordBitWidth.uint32)

  result = M0                 # Start from an inverse of M0 modulo 2, M0 is odd and it's own inverse
  for _ in 0 ..< k:           # at each iteration we get the inverse mod(2^2k)
    result *= 2 - M0 * result # x' = x(2 - ax)

  # negate to obtain the negative inverse
  result = not(result) + 1

func r_powmod(n: static int, M: BigInt): BigInt =
  ## Returns the Montgomery domain magic constant for the input modulus:
  ##
  ##   R ≡ R (mod M) with R = (2^WordBitWidth)^numWords
  ##   or
  ##   R² ≡ R² (mod M) with R = (2^WordBitWidth)^numWords
  ##
  ## Assuming a field modulus of size 256-bit with 63-bit words, we require 5 words
  ##   R² ≡ ((2^63)^5)^2 (mod M) = 2^630 (mod M)

  # Algorithm
  # Bos and Montgomery, Montgomery Arithmetic from a Software Perspective
  # https://eprint.iacr.org/2017/1057.pdf
  #
  # For R = r^n = 2^wn and 2^(wn − 1) ≤ N < 2^wn
  # r^n = 2^63 in on 64-bit and w the number of words
  #
  # 1. C0 = 2^(wn - 1), the power of two immediately less than N
  # 2. for i in 1 ... wn+1
  #      Ci = C(i-1) + C(i-1) (mod M)
  #
  # Thus: C(wn+1) ≡ 2^(wn+1) C0 ≡ 2^(wn + 1) 2^(wn - 1) ≡ 2^(2wn) ≡ (2^wn)^2 ≡ R² (mod M)

  checkOddModulus(M)
  checkValidModulus(M)

  const
    w = M.limbs.len
    msb = M.bits-1 - WordBitWidth * (w - 1)
    start = (w-1)*WordBitWidth + msb
    stop = n*WordBitWidth*w

  result.limbs[^1] = SecretWord(BaseType(1) shl msb) # C0 = 2^(wn-1), the power of 2 immediatly less than the modulus
  for _ in start ..< stop:
    result.doubleMod(M)

func r2mod*(M: BigInt): BigInt =
  ## Returns the Montgomery domain magic constant for the input modulus:
  ##
  ##   R² ≡ R² (mod M) with R = (2^WordBitWidth)^numWords
  ##
  ## Assuming a field modulus of size 256-bit with 63-bit words, we require 5 words
  ##   R² ≡ ((2^63)^5)^2 (mod M) = 2^630 (mod M)
  r_powmod(2, M)

func montyOne*(M: BigInt): BigInt =
  ## Returns "1 (mod M)" in the Montgomery domain.
  ## This is equivalent to R (mod M) in the natural domain
  r_powmod(1, M)

func montyPrimeMinus1*(P: BigInt): BigInt =
  ## Compute P-1 in the Montgomery domain
  ## For use in constant-time sqrt
  result = P
  discard result.csub(P.montyOne(), true)

func primeMinus2_BE*[bits: static int](
       P: BigInt[bits]
     ): array[(bits+7) div 8, byte] {.noInit.} =
  ## Compute an input prime-2
  ## and return the result as a canonical byte array / octet string
  ## For use to precompute modular inverse exponent
  ## when using inversion by Little Fermat Theorem a^-1 = a^(p-2) mod p

  var tmp = P
  discard tmp.sub(2)

  result.exportRawUint(tmp, bigEndian)

func primePlus1div2*(P: BigInt): BigInt =
  ## Compute (P+1)/2, assumes P is odd
  ## For use in constant-time modular inversion
  ##
  ## Warning ⚠️: Result is in the canonical domain (not Montgomery)
  checkOddModulus(P)

  # (P+1)/2 = P/2 + 1 if P is odd,
  # this avoids overflowing if the prime uses all bits
  # i.e. in the form (2^64)^w - 1 or (2^32)^w - 1

  result = P
  result.shiftRight(1)
  let carry = result.add(1)
  doAssert not carry

func primeMinus1div2_BE*[bits: static int](
       P: BigInt[bits]
     ): array[(bits+7) div 8, byte] {.noInit.} =
  ## For an input prime `p`, compute (p-1)/2
  ## and return the result as a canonical byte array / octet string
  ## For use to check if a number is a square (quadratic residue)
  ## in a field by Euler's criterion
  ##
  # Output size:
  # - (bits + 7) div 8: bits => byte conversion rounded up
  # - (bits + 7 - 1): dividing by 2 means 1 bit is unused
  # => TODO: reduce the output size (to potentially save a byte and corresponding multiplication/squarings)

  var tmp = P
  discard tmp.sub(1)
  tmp.shiftRight(1)

  result.exportRawUint(tmp, bigEndian)

func primeMinus3div4_BE*[bits: static int](
       P: BigInt[bits]
     ): array[(bits+7) div 8, byte] {.noInit.} =
  ## For an input prime `p`, compute (p-3)/4
  ## and return the result as a canonical byte array / octet string
  ## For use to check if a number is a square (quadratic residue)
  ## and if so compute the square root in a fused manner
  ##
  # Output size:
  # - (bits + 7) div 8: bits => byte conversion rounded up
  # - (bits + 7 - 2): dividing by 4 means 2 bits is unused
  # => TODO: reduce the output size (to potentially save a byte and corresponding multiplication/squarings)

  var tmp = P
  discard tmp.sub(3)
  tmp.shiftRight(2)

  result.exportRawUint(tmp, bigEndian)

func primePlus1Div4_BE*[bits: static int](
       P: BigInt[bits]
     ): array[(bits+7) div 8, byte] {.noInit.} =
  ## For an input prime `p`, compute (p+1)/4
  ## and return the result as a canonical byte array / octet string
  ## For use to check if a number is a square (quadratic residue)
  ## in a field by Euler's criterion
  ##
  # Output size:
  # - (bits + 7) div 8: bits => byte conversion rounded up
  # - (bits + 7 - 1): dividing by 4 means 2 bits are unused
  #                   but we also add 1 to an odd number so using an extra bit
  # => TODO: reduce the output size (to potentially save a byte and corresponding multiplication/squarings)
  checkOddModulus(P)

  # First we do P+1/2 in a way that guarantees no overflow
  var tmp = primePlus1div2(P)
  # then divide by 2
  tmp.shiftRight(1)

  result.exportRawUint(tmp, bigEndian)

func toCanonicalIntRepr*[bits: static int](
       a: BigInt[bits]
     ): array[(bits+7) div 8, byte] {.noInit.} =
  ## Export a bigint to its canonical BigEndian representation
  ## (octet-string)
  result.exportRawUint(a, bigEndian)

func bn_6u_minus_1_BE*[bits: static int](
       u: BigInt[bits]
     ): array[(bits+7+3) div 8, byte] {.noInit.} =
  ## For a BN curve
  ## Precompute 6u-1 (for Little Fermat inversion)
  ## and store it in canonical integer representation
  # TODO: optimize output size
  #       each extra 0-bit is an extra useless squaring for a public exponent
  #       For example, for BN254-Snarks, u = 0x44E992B44A6909F1 (63-bit)
  #       and 6u+1 is 65-bit (not 66 as inferred)

  # Zero-extend "u"
  var u_ext: BigInt[bits+3]

  for i in 0 ..< u.limbs.len:
    u_ext.limbs[i] = u.limbs[i]

  # Addition chain to u -> 6u
  discard u_ext.dbl()              # u_ext = 2u
  let u_ext2 = u_ext               # u_ext2 = 2u
  discard u_ext.dbl()              # u_ext = 4u
  discard u_ext.cadd(u_ext2, true)  # u_ext = 6u

  # Sustract 1
  discard u_ext.sub(1)

  # Export
  result.exportRawUint(u_ext, bigEndian)
