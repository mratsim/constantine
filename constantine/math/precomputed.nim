# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  ./bigints_checked,
  ../primitives/constant_time,
  ../config/common

# Precomputed constants
# ############################################################

# ############################################################
#
#                   Modular primitives
#
# ############################################################
#
# Those primitives are intended to be compile-time only
# They are generic over the bitsize: enabling them at runtime
# would create a copy for each bitsize used (monomorphization)
# leading to code-bloat.
# Thos are NOT compile-time, using CTBool seems to confuse the VM

# We don't use distinct types here, they confuse the VM
# Similarly, isMsbSet causes trouble with distinct type in the VM

func isMsbSet(x: BaseType): bool =
  const msb_pos = BaseType.sizeof * 8 - 1
  bool(x shr msb_pos)

func double(a: var BigInt): bool =
  ## In-place multiprecision double
  ##   a -> 2a
  for i in 0 ..< a.limbs.len:
    var z = BaseType(a.limbs[i]) * 2 + BaseType(result)
    result = z.isMsbSet()
    a.limbs[i] = Word(z) and MaxWord

func sub(a: var BigInt, b: BigInt, ctl: bool): bool =
  ## In-place optional substraction
  for i in 0 ..< a.limbs.len:
    let new_a = BaseType(a.limbs[i]) - BaseType(b.limbs[i]) - BaseType(result)
    result = new_a.isMsbSet()
    a.limbs[i] = if ctl: new_a.Word and MaxWord
                 else: a.limbs[i]

func doubleMod(a: var BigInt, M: BigInt) =
  ## In-place modular double
  ##   a -> 2a (mod M)
  ##
  ## It is NOT constant-time and is intended
  ## only for compile-time precomputation
  ## of non-secret data.
  var ctl = double(a)
  ctl = ctl or not sub(a, M, false)
  discard sub(a, M, ctl)

# ############################################################
#
#          Montgomery Magic Constants precomputation
#
# ############################################################

func checkOddModulus(M: BigInt) =
  doAssert bool(BaseType(M.limbs[0]) and 1), "Internal Error: the modulus must be odd to use the Montgomery representation."

import strutils

func checkValidModulus(M: BigInt) =
  const expectedMsb = M.bits-1 - WordBitSize * (M.limbs.len - 1)
  let msb = log2(BaseType(M.limbs[^1]))

  doAssert msb == expectedMsb, "Internal Error: the modulus must use all declared bits and only those"

func negInvModWord*(M: BigInt): BaseType =
  ## Returns the Montgomery domain magic constant for the input modulus:
  ##
  ##   µ ≡ -1/M[0] (mod Word)
  ##
  ## M[0] is the least significant limb of M
  ## M must be odd and greater than 2.
  ##
  ## Assuming 63-bit words:
  ##
  ## µ ≡ -1/M[0] (mod 2^63)

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
  # where a = M and m = 2^WordBitsize.
  # For a and m to be coprimes, a must be odd.

  # We have the following relation
  # ax ≡ 1 (mod 2^k) <=> ax(2 - ax) ≡ 1 (mod 2^(2k))
  #
  # To get  -1/M0 mod LimbSize
  # we can either negate the resulting x of `ax(2 - ax) ≡ 1 (mod 2^(2k))`
  # or do ax(2 + ax) ≡ 1 (mod 2^(2k))
  #
  # To get the the modular inverse of 2^k' with arbitrary k' (like k=63 in our case)
  # we can do modInv(a, 2^64) mod 2^63 as mentionned in Koc paper.

  checkOddModulus(M)
  checkValidModulus(M)

  let
    M0 = BaseType(M.limbs[0])
    k = log2(WordPhysBitSize)

  result = M0                 # Start from an inverse of M0 modulo 2, M0 is odd and it's own inverse
  for _ in 0 ..< k:           # at each iteration we get the inverse mod(2^2k)
    result *= 2 + M0 * result # x' = x(2 + ax) (`+` to avoid negating at the end)

  # Our actual word size is 2^63 not 2^64
  result = result and BaseType(MaxWord)

func r2mod*(M: BigInt): BigInt =
  ## Returns the Montgomery domain magic constant for the input modulus:
  ##
  ##   R² ≡ R² (mod M) with R = (2^WordBitSize)^numWords
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

  result.setInternalBitLength()

  const
    w = M.limbs.len
    msb = M.bits-1 - WordBitSize * (w - 1)
    start = (w-1)*WordBitSize + msb
    stop = 2*WordBitSize*w

  result.limbs[^1] = Word(1 shl msb) # C0 = 2^(wn-1), the power of 2 immediatly less than the modulus
  for _ in start ..< stop:
    result.doubleMod(M)
