# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  ../../platforms/abstractions,
  ../../platforms/intrinsics/extended_precision_vartime,
  ./limbs_views

# No exceptions allowed
{.push raises: [], checks: off.}

# ############################################################
#
#              Division and Modular Reduction
#                    (variable-time)
#
# ############################################################

func shlAddMod_multiprec_vartime(
       a: var openArray[SecretWord], c: SecretWord,
       M: openArray[SecretWord], mBits: int): SecretWord {.meter.} =
  ## Fused modular left-shift + add
  ## Computes: a <- a shl 2ʷ + c (mod M)
  ## Returns: (a shl 2ʷ + c) / M
  ##
  ## with w the base word width, usually 32 on 32-bit platforms and 64 on 64-bit platforms
  ##
  ## The modulus `M` most-significant bit at `mBits` MUST be set.
  ##
  ## Specialized for M being a multi-precision integer.
                                        # Assuming 64-bit words
  let hi = a[^1]                        # Save the high word to detect carries
  let R = mBits and (WordBitWidth - 1)  # R = mBits mod 64

  var a0, a1, m0: SecretWord
  if R == 0:                            # If the number of mBits is a multiple of 64
    a0 = a[^1]                          #
    copyWords(a.view(), 1,              # we can just shift words
              a.view(), 0, a.len-1)     #
    a[0] = c                            # and replace the first one by c
    a1 = a[^1]
    m0 = M[^1]
  else:                                 # Else: need to deal with partial word shifts at the edge.
    let clz = WordBitWidth-R
    a0 = (a[^1] shl clz) or (a[^2] shr R)
    copyWords(a.view(), 1,
              a.view(), 0, a.len-1)
    a[0] = c
    a1 = (a[^1] shl clz) or (a[^2] shr R)
    m0 = (M[^1] shl clz) or (M[^2] shr R)

  # m0 has its high bit set. (a0, a1)/m0 fits in a limb.
  # Get a quotient q, at most we will be 2 iterations off
  # from the true quotient
  var q: SecretWord                     # Estimate quotient
  if bool(a0 == m0):                    # if a_hi == divisor
    q = MaxWord                         # quotient = MaxWord (0b1111...1111)
  elif bool(a0.isZero()) and
       bool(a1 < m0):                   # elif q == 0, true quotient = 0
    q = Zero
    return q
  else:
    var r: SecretWord
    div2n1n_vartime(q, r, a0, a1, m0)   # else instead of being of by 0, 1 or 2
    q -= One                            # we return q-1 to be off by -1, 0 or 1

  # Now substract a*2^64 - q*m
  var carry = Zero
  var overM = true                      # Track if quotient greater than the modulus

  for i in 0 ..< M.len:
    var qm_lo: SecretWord
    block:                              # q*m
      # q * m + carry (doubleword) carry from previous limb
      muladd1(carry, qm_lo, q, M[i], carry)

    block:                              # a*2^64 - q*m
      var borrow: Borrow
      subB(borrow, a[i], a[i], qm_lo, Borrow(0))
      carry += SecretWord(borrow) # Adjust if borrow

    if bool(a[i] != M[i]):
      overM = bool(a[i] > M[i])

  # Fix quotient, the true quotient is either q-1, q or q+1
  #
  # if carry < q or carry == q and overM we must do "a -= M"
  # if carry > hi (negative result) we must do "a += M"
  if bool(carry > hi):
    var c = Carry(0)
    for i in 0 ..< a.len:
      addC(c, a[i], a[i], M[i], c)
    q -= One
  elif overM or bool(carry < hi):
    var b = Borrow(0)
    for i in 0 ..< a.len:
      subB(b, a[i], a[i], M[i], b)
    q += One

  return q

func shortDiv_vartime*(remainder: var SecretWord, n_hi, n_lo, d: SecretWord, normFactor: int): SecretWord =
  # We normalize d with clz so that the MSB is set
  # And normalize (n_hi * 2^64 + n_lo) by normFactor as well to maintain the result
  # This ensures that (n_hi, n_hi)/d fits in a limb.
  if normFactor == 0:
    div2n1n_vartime(result, remainder, n_hi, n_lo, d)
  else:
    let clz = WordBitWidth-normFactor
    let hi = (n_hi shl clz) or (n_lo shr normFactor)
    let lo = n_lo shl clz
    let d = d shl clz

    div2n1n_vartime(result, remainder, hi, lo, d)
    remainder = remainder shr clz

func shlAddMod_vartime(a: var openArray[SecretWord], c: SecretWord,
                       M: openArray[SecretWord], mBits: int): SecretWord {.meter.} =
  ## Fused modular left-shift + add
  ## Computes: a <- a shl 2ʷ + c (mod M)
  ## Returns: (a shl 2ʷ + c) / M
  ##
  ## with w the base word width, usually 32 on 32-bit platforms and 64 on 64-bit platforms
  ##
  ## The modulus `M` most-significant bit at `mBits` MUST be set.
  if mBits <= WordBitWidth:
    # If M fits in a single limb

    # We normalize M with clz so that the MSB is set
    # And normalize (a * 2^64 + c) by R as well to maintain the result
    # This ensures that (a0, a1)/m0 fits in a limb.
    let R = mBits and (WordBitWidth - 1)

    # (hi, lo) = a * 2^64 + c
    return shortDiv_vartime(remainder = a[0], n_hi = a[0], n_lo = c, d = M[0], normFactor = R)
  else:
    return shlAddMod_multiprec_vartime(a, c, M, mBits)

func divRem_vartime*(
       q, r: var openArray[SecretWord],
       a, b: openArray[SecretWord]): bool {.meter.} =
  # q = a div b
  # r = a mod b
  #
  # Requirements:
  # b != 0
  # q.len > a.len - b.len
  # r.len >= b.len

  let aBits = getBits_LE_vartime(a)
  let bBits = getBits_LE_vartime(b)
  let aLen = wordsRequired(aBits)
  let bLen = wordsRequired(bBits)
  let rLen = bLen

  let aOffset = a.len - b.len

  # Note: don't confuse a.len and aLen (actually used words)

  if unlikely(bool(r.len < bLen)):
    # remainder buffer cannot store up to modulus size
    return false

  if unlikely(bool(q.len < aOffset+1)):
    # quotient buffer cannot store up to quotient size
    return false

  if unlikely(bBits == 0):
    # Divide by zero
    return false

  if aBits < bBits:
    # if a uses less bits than b,
    # a < b, so q = 0 and r = a
    copyWords(r.view(), 0, a.view(), 0, aLen)
    for i in aLen ..< r.len:
      r[i] = Zero
    for i in 0 ..< q.len:
      q[i] = Zero
  else:
    # The length of a is at least the divisor
    # We can copy bLen-1 words
    # and modular shift-left-add the rest

    copyWords(r.view(), 0, a.view(), aOffset+1, b.len-1)
    r[rLen-1] = Zero
    # Now shift-left the copied words while adding the new word mod b

    for i in countdown(aOffset, 0):
      q[i] = shlAddMod_vartime(
              r.toOpenArray(0, rLen-1),
              a[i],
              b.toOpenArray(0, bLen-1),
              bBits)

    # Clean up extra words
    for i in aOffset+1 ..< q.len:
      q[i] = Zero
    for i in rLen ..< r.len:
      r[i] = Zero

  return true

func reduce_vartime*(r: var openArray[SecretWord],
                     a, b: openArray[SecretWord]): bool {.noInline, meter.} =
  let aOffset = max(a.len - b.len, 0)
  var qBuf = allocStackArray(SecretWord, aOffset+1)
  template q: untyped = qBuf.toOpenArray(0, aOffset)
  result = divRem_vartime(q, r, a, b)

# ############################################################
#
#                    Barrett Reduction
#
# ############################################################

# - https://en.wikipedia.org/wiki/Barrett_reduction
# - Handbook of Applied Cryptography
#   Alfred J. Menezes, Paul C. van Oorschot and Scott A. Vanstone
#   https://cacr.uwaterloo.ca/hac/about/chap14.pdf
# - Modern Computer Arithmetic
#   Richard P. Brent and Paul Zimmermann
#   https://members.loria.fr/PZimmermann/mca/mca-cup-0.5.9.pdf
