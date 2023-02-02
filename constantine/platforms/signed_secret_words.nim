# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import ./abstractions

type SignedSecretWord* = distinct SecretWord

when sizeof(int) == 8 and not defined(Constantine32):
  type
    SignedBaseType* = int64
else:
  type
    SignedBaseType* = int32

# ############################################################
#
#                      Arithmetic
#
# ############################################################

template fmap(x: SignedSecretWord, op: untyped, y: SignedSecretWord): SignedSecretWord =
  ## Unwrap x and y from their distinct type
  ## Apply op, and rewrap them
  SignedSecretWord(op(SecretWord(x), SecretWord(y)))

template fmapAsgn(x: SignedSecretWord, op: untyped, y: SignedSecretWord) =
  ## Unwrap x and y from their distinct type
  ## Apply assignment op, and rewrap them
  op(SecretWord(x), SecretWord(y))

template `and`*(x, y: SignedSecretWord): SignedSecretWord    = fmap(x, `and`, y)
template `or`*(x, y: SignedSecretWord): SignedSecretWord     = fmap(x, `or`, y)
template `xor`*(x, y: SignedSecretWord): SignedSecretWord    = SignedSecretWord(BaseType(x) xor BaseType(y))
template `not`*(x: SignedSecretWord): SignedSecretWord       = SignedSecretWord(not SecretWord(x))
template `+`*(x, y: SignedSecretWord): SignedSecretWord      = fmap(x, `+`, y)
template `+=`*(x: var SignedSecretWord, y: SignedSecretWord) = fmapAsgn(x, `+=`, y)
template `-`*(x, y: SignedSecretWord): SignedSecretWord      = fmap(x, `-`, y)
template `-=`*(x: var SignedSecretWord, y: SignedSecretWord) = fmapAsgn(x, `-=`, y)

template `-`*(x: SignedSecretWord): SignedSecretWord =
  # We don't use Nim signed integers to avoid range checks
  SignedSecretWord(-SecretWord(x))

template `*`*(x, y: SignedSecretWord): SignedSecretWord =
  # Warning ⚠️ : We assume that hardware multiplication is constant time
  # but this is not always true. See https://www.bearssl.org/ctmul.html
  fmap(x, `*`, y)

# shifts
template ashr*(x: SignedSecretWord, y: SomeNumber): SignedSecretWord =
  ## Arithmetic right shift
  # We need to cast to Nim ints without Nim checks
  SignedSecretWord(cast[SignedBaseType](x).ashr(y))

template lshr*(x: SignedSecretWord, y: SomeNumber): SignedSecretWord =
  ## Logical right shift
  SignedSecretWord(SecretWord(x) shr y)

template lshl*(x: SignedSecretWord, y: SomeNumber): SignedSecretWord =
  ## Logical left shift
  SignedSecretWord(SecretWord(x) shl y)

# ############################################################
#
#             Hardened Boolean primitives
#
# ############################################################

template `==`*(x, y: SignedSecretWord): SecretBool =
  SecretWord(x) == SecretWord(y)

# ############################################################
#
#                Conditional arithmetic
#
# ############################################################

# SignedSecretWord
# ----------------

func isNeg*(a: SignedSecretWord): SignedSecretWord {.inline.} =
  ## Returns 1 if a is negative
  ## and 0 otherwise
  a.lshr(WordBitWidth-1)

func isOdd*(a: SignedSecretWord): SignedSecretWord {.inline.} =
  ## Returns 1 if a is odd
  ## and 0 otherwise
  a and SignedSecretWord(1)

func isZeroMask*(a: SignedSecretWord): SignedSecretWord {.inline.} =
  ## Produce the -1 mask if a is 0
  ## and 0 otherwise
  # In x86 assembly, we can use "neg" + "sbb"
  -SignedSecretWord(a.SecretWord().isZero())

func isNegMask*(a: SignedSecretWord): SignedSecretWord {.inline.} =
  ## Produce the -1 mask if a is negative
  ## and 0 otherwise
  a.ashr(WordBitWidth-1)

func isOddMask*(a: SignedSecretWord): SignedSecretWord {.inline.} =
  ## Produce the -1 mask if a is odd
  ## and 0 otherwise
  -(a and SignedSecretWord(1))

func csetZero*(a: var SignedSecretWord, mask: SignedSecretWord) {.inline.} =
  ## Conditionally set `a` to 0
  ## mask must be 0 (0x00000...0000) (kept as is)
  ## or -1 (0xFFFF...FFFF) (zeroed)
  a = a and mask

func cneg*(
       a: SignedSecretWord,
       mask: SignedSecretWord): SignedSecretWord {.inline.} =
  ## Conditionally negate `a`
  ## mask must be 0 (0x00000...0000) (no negation)
  ## or -1 (0xFFFF...FFFF) (negation)
  (a xor mask) - mask

func cadd*(
       a: var SignedSecretWord,
       b: SignedSecretWord,
       mask: SignedSecretWord) {.inline.} =
  ## Conditionally add `b` to `a`
  ## mask must be 0 (0x00000...0000) (no addition)
  ## or -1 (0xFFFF...FFFF) (addition)
  a = a + (b and mask)

func csub*(
       a: var SignedSecretWord,
       b: SignedSecretWord,
       mask: SignedSecretWord) {.inline.} =
  ## Conditionally substract `b` from `a`
  ## mask must be 0 (0x00000...0000) (no substraction)
  ## or -1 (0xFFFF...FFFF) (substraction)
  a = a - (b and mask)

# ############################################################
#
#                Double-Width signed arithmetic
#
# ############################################################

type DSWord* = object
  lo*, hi*: SignedSecretWord

func smulAccNoCarry*(r: var DSWord, a, b: SignedSecretWord) {.inline.}=
  ## Signed accumulated multiplication
  ## (_, hi, lo) += a*b
  ## This assumes no overflowing
  var UV: array[2, SecretWord]
  var carry: Carry
  smul(UV[1], UV[0], SecretWord a, SecretWord b)
  addC(carry, UV[0], UV[0], SecretWord r.lo, Carry(0))
  addC(carry, UV[1], UV[1], SecretWord r.hi, carry)

  r.lo = SignedSecretWord UV[0]
  r.hi = SignedSecretWord UV[1]

func ssumprodAccNoCarry*(r: var DSWord, a, u, b, v: SignedSecretWord) {.inline.}=
  ## Accumulated sum of products
  ## (_, hi, lo) += a*u + b*v
  ## This assumes no overflowing
  var carry: Carry
  var x1, x0, y1, y0: SecretWord
  smul(x1, x0, SecretWord a, SecretWord u)
  addC(carry, x0, x0, SecretWord r.lo, Carry(0))
  addC(carry, x1, x1, SecretWord r.hi, carry)
  smul(y1, y0, SecretWord b, SecretWord v)
  addC(carry, x0, x0, y0, Carry(0))
  addC(carry, x1, x1, y1, carry)

  r.lo = SignedSecretWord x0
  r.hi = SignedSecretWord x1

func ashr*(
       r: var DSWord,
       k: SomeInteger) {.inline.} =
  ## Arithmetic right-shift of a double-word
  ## This does not normalize the excess bits
  r.lo = r.lo.lshr(k) or r.hi.lshl(WordBitWidth - k)
  r.hi = r.hi.ashr(k)