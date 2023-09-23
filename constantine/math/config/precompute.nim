# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  ../../platforms/abstractions,
  ./type_bigint,
  ../io/io_bigints

{.used.}

# Precomputed constants
# We need alternate code paths for the VM
# for various reasons
# ------------------------------------------------------------

# ############################################################
#
#                   BigInt primitives
#
# ############################################################
#
# Those primitives are intended to be compile-time only
# Those are NOT tagged compile-time, using CTBool seems to confuse the VM

# We don't use distinct types here, they confuse the VM
# Similarly, using addC / subB from primitives confuses the VM

# As we choose to use the full 32/64 bits of the integers and there is no carry flag
# in the compile-time VM we need a portable (and slow) "adc" and "sbb".
# Hopefully compilation time stays decent.

const
  HalfWidth = WordBitWidth shr 1
  HalfBase = (BaseType(1) shl HalfWidth)
  HalfMask = HalfBase - 1

func hi(n: BaseType): BaseType =
  result = n shr HalfWidth

func lo(n: BaseType): BaseType =
  result = n and HalfMask

func split(n: BaseType): tuple[hi, lo: BaseType] =
  result.hi = n.hi
  result.lo = n.lo

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

func mul(hi, lo: var BaseType, u, v: BaseType) =
  ## Extended precision multiplication
  ## (hi, lo) <- u * v
  var x0, x1, x2, x3: BaseType

  let
    (uh, ul) = u.split()
    (vh, vl) = v.split()

  x0 = ul * vl
  x1 = ul * vh
  x2 = uh * vl
  x3 = uh * vh

  x1 += hi(x0)          # This can't carry
  x1 += x2              # but this can
  if x1 < x2:           # if carry, add it to x3
    x3 += HalfBase

  hi = x3 + hi(x1)
  lo = merge(x1, lo(x0))

func muladd1(hi, lo: var BaseType, a, b, c: BaseType) {.inline.} =
  ## Extended precision multiplication + addition
  ## (hi, lo) <- a*b + c
  ##
  ## Note: 0xFFFFFFFF_FFFFFFFF² -> (hi: 0xFFFFFFFFFFFFFFFE, lo: 0x0000000000000001)
  ##       so adding any c cannot overflow
  var carry: BaseType
  mul(hi, lo, a, b)
  addC(carry, lo, lo, c, 0)
  addC(carry, hi, hi, 0, carry)

func muladd2(hi, lo: var BaseType, a, b, c1, c2: BaseType) {.inline.}=
  ## Extended precision multiplication + addition + addition
  ## (hi, lo) <- a*b + c1 + c2
  ##
  ## Note: 0xFFFFFFFF_FFFFFFFF² -> (hi: 0xFFFFFFFFFFFFFFFE, lo: 0x0000000000000001)
  ##       so adding 0xFFFFFFFFFFFFFFFF leads to (hi: 0xFFFFFFFFFFFFFFFF, lo: 0x0000000000000000)
  ##       and we have enough space to add again 0xFFFFFFFFFFFFFFFF without overflowing
  var carry1, carry2: BaseType

  mul(hi, lo, a, b)
  # Carry chain 1
  addC(carry1, lo, lo, c1, 0)
  addC(carry1, hi, hi, 0, carry1)
  # Carry chain 2
  addC(carry2, lo, lo, c2, 0)
  addC(carry2, hi, hi, 0, carry2)

func cadd(a: var BigInt, b: BigInt, ctl: bool): bool {.used.} =
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

func `<`(a, b: BigInt): bool =
  var diff, borrow: BaseType
  for i in 0 ..< a.limbs.len:
    subB(borrow, diff, BaseType(a.limbs[i]), BaseType(b.limbs[i]), borrow)

  result = bool borrow

func shiftRight*(a: var BigInt, k: int) =
  ## Shift right by k.
  ##
  ## k MUST be less than the base word size (2^32 or 2^64)

  for i in 0 ..< a.limbs.len-1:
    a.limbs[i] = (a.limbs[i] shr k) or (a.limbs[i+1] shl (WordBitWidth - k))
  a.limbs[a.limbs.len-1] = a.limbs[a.limbs.len-1] shr k

# ############################################################
#
#          Montgomery Magic Constants precomputation
#
# ############################################################

func checkOdd(a: BaseType) =
  doAssert bool(a and 1), "Internal Error: the modulus must be odd to use the Montgomery representation."

func checkOdd(M: BigInt) =
  checkOdd(BaseType M.limbs[0])

func checkValidModulus(M: BigInt) =
  const expectedMsb = M.bits-1 - WordBitWidth * (M.limbs.len - 1)
  let msb = log2_vartime(BaseType(M.limbs[M.limbs.len-1]))

  # This is important for the constant-time explicit modulo operation
  # "reduce" and bigint division.
  doAssert msb == expectedMsb, "Internal Error: the modulus must use all declared bits and only those:\n" &
    "    Modulus '" & M.toHex() & "' is declared with " & $M.bits &
    " bits but uses " & $(msb + WordBitWidth * (M.limbs.len - 1)) & " bits."

func countSpareBits*(M: BigInt): int =
  ## Count the number of extra bits
  ## in the modulus M representation.
  ##
  ## This is used for no-carry operations
  ## or lazily reduced operations by allowing
  ## output in range:
  ## - [0, 2p) if 1 bit is available
  ## - [0, 4p) if 2 bits are available
  ## - [0, 8p) if 3 bits are available
  ## - ...
  checkValidModulus(M)
  let msb = log2_vartime(BaseType(M.limbs[M.limbs.len-1]))
  result = WordBitWidth - 1 - msb.int

func invModBitwidth*[T: SomeUnsignedInt](a: T): T =
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

  # We are in a special case
  # where m = 2^WordBitWidth.
  # For a and m to be coprimes, a must be odd.
  #
  # We have the following relation
  # ax ≡ 1 (mod 2ᵏ) <=> ax(2 - ax) ≡ 1 (mod 2^(2k))
  # which grows in O(log(log(a)))
  checkOdd(a)

  let k = log2_vartime(T.sizeof().uint32 * 8)
  result = a                 # Start from an inverse of M0 modulo 2, M0 is odd and it's own inverse
  for _ in 0 ..< k:          # at each iteration we get the inverse mod(2^2k)
    result *= 2 - a * result # x' = x(2 - ax)

func negInvModWord*[T: SomeUnsignedInt or SecretWord](a: T): T =
  let t = invModBitwidth(BaseType a)
  {.push hint[ConvFromXtoItselfNotNeeded]: off.}
  return T(-SecretWord(t))
  {.pop.}

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
  checkValidModulus(M)
  return BaseType M.limbs[0].negInvModWord()

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

  checkOdd(M)
  checkValidModulus(M)

  const
    w = M.limbs.len
    msb = M.bits-1 - WordBitWidth * (w - 1)
    start = (w-1)*WordBitWidth + msb
    stop = n*WordBitWidth*w

  result.limbs[M.limbs.len-1] = SecretWord(BaseType(1) shl msb) # C0 = 2^(wn-1), the power of 2 immediatly less than the modulus
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

func r3mod*(M: BigInt): BigInt =
  ## Returns
  ##
  ##   R³ ≡ R³ (mod M) with R = (2^WordBitWidth)^numWords
  ##
  ## This is used in hash-to-curve to
  ## reduce a double-sized bigint mod M
  ## and map it to the Montgomery domain
  ## with just redc2x + mulMont
  r_powmod(3, M)

func montyOne*(M: BigInt): BigInt =
  ## Returns "1 (mod M)" in the Montgomery domain.
  ## This is equivalent to R (mod M) in the natural domain
  r_powmod(1, M)

func montyPrimeMinus1*(P: BigInt): BigInt =
  ## Compute P-1 in the Montgomery domain
  ## For use in constant-time sqrt
  result = P
  discard result.csub(P.montyOne(), true)

func primePlus1div2*(P: BigInt): BigInt =
  ## Compute (P+1)/2, assumes P is odd
  ## For use in constant-time modular inversion
  ##
  ## Warning ⚠️: Result is in the canonical domain (not Montgomery)
  checkOdd(P)

  # (P+1)/2 = P/2 + 1 if P is odd,
  # this avoids overflowing if the prime uses all bits
  # i.e. in the form (2^64)ʷ - 1 or (2^32)ʷ - 1

  result = P
  result.shiftRight(1)
  let carry = result.add(1)
  doAssert not carry

func primeMinus1div2*(P: BigInt): BigInt =
  ## Compute (P-1)/2
  ## For use in constant-time modular inversion
  ##
  ## Warning ⚠️: Result is in the canonical domain (not Montgomery)

  result = P
  # discard result.sub(1) # right-shifting automatically implies "-1" for odd numbers (which all prime >2 are).
  result.shiftRight(1)

func primeMinus3div4_BE*[bits: static int](
       P: BigInt[bits]
     ): array[bits.ceilDiv_vartime(8), byte] {.noInit.} =
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

  discard result.marshal(tmp, bigEndian)

func primeMinus5div8_BE*[bits: static int](
       P: BigInt[bits]
     ): array[bits.ceilDiv_vartime(8), byte] {.noInit.} =
  ## For an input prime `p`, compute (p-5)/8
  ## and return the result as a canonical byte array / octet string
  ## For use to check if a number is a square (quadratic residue)
  ## and if so compute the square root in a fused manner
  ##
  # Output size:
  # - (bits + 7) div 8: bits => byte conversion rounded up
  # - (bits + 7 - 3): dividing by 8 means 3 bits is unused
  # => TODO: reduce the output size (to potentially save a byte and corresponding multiplication/squarings)

  var tmp = P
  discard tmp.sub(5)
  tmp.shiftRight(3)

  discard result.marshal(tmp, bigEndian)

# ############################################################
#
#       Compile-time Conversion to Montgomery domain
#
# ############################################################
# This is needed to avoid recursive dependencies

func mulMont_precompute(r: var BigInt, a, b, M: BigInt, m0ninv: BaseType) =
  ## Montgomery Multiplication using Coarse Grained Operand Scanning (CIOS)
  var t: typeof(M)   # zero-init
  const N = t.limbs.len
  var tN: BaseType
  var tNp1: BaseType

  var tmp: BaseType # Distinct types bug in the VM are a huge pain ...

  for i in 0 ..< N:
    var A: BaseType
    for j in 0 ..< N:
      muladd2(A, tmp, BaseType(a.limbs[j]), BaseType(b.limbs[i]), BaseType(t.limbs[j]), A)
      t.limbs[j] = SecretWord(tmp)
    addC(tNp1, tN, tN, A, 0)

    var C, lo: BaseType
    let m = BaseType(t.limbs[0]) * m0ninv
    muladd1(C, lo, m, BaseType(M.limbs[0]), BaseType(t.limbs[0]))
    for j in 1 ..< N:
      muladd2(C, tmp, m, BaseType(M.limbs[j]), BaseType(t.limbs[j]), C)
      t.limbs[j-1] = SecretWord(tmp)

    var carry: BaseType
    addC(carry, tmp, tN, C, 0)
    t.limbs[N-1] = SecretWord(tmp)
    addC(carry, tN, tNp1, 0, carry)

  discard t.csub(M, (tN != 0) or not(precompute.`<`(t, M)))
  r = t

func montyResidue_precompute*(r: var BigInt, a, M, r2modM: BigInt,
                              m0ninv: BaseType) =
  ## Transform a bigint ``a`` from it's natural representation (mod N)
  ## to a the Montgomery n-residue representation
  ## This is intended for compile-time precomputations-only
  mulMont_precompute(r, a, r2ModM, M, m0ninv)
