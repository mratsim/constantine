# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  # Internal
  ../../platforms/[abstractions, allocs],
  ../../math/config/precompute,
  ./limbs_views,
  ./limbs_montgomery,
  ./limbs_mod2k,
  ./limbs_multiprec,
  ./limbs_extmul,
  ./limbs_divmod_vartime

# No exceptions allowed
{.push raises: [], checks: off.}

# ############################################################
#
#                 Arbitrary-precision integers
#
# ############################################################
#
# We only implement algorithms that work on views allocated by the caller
# as providing a full-blown arbitrary-precision library is not the goal.
# As the bigint sizes are relatively constrained
# in protocols we implement (4096 bits for RSA, 8192 bit s for the Ethereum EVM),
# this allows us to avoid heap allocations, which simplifies reentrancy and thread-safety.

# TODO: choose between:
# - openArray + countLeadingZeros
# - bits + wordsRequired
# for parameter passing
# This also impacts ergonomics of allocStackArray
#
# Also need to take into account constant-time for RSA
# i.e. countLeadingZeros can only be done on public moduli.

iterator unpackBE(scalarByte: byte): bool =
  for i in countdown(7, 0):
    yield bool((scalarByte shr i) and 1)

func pow_vartime(
       r: var openArray[SecretWord],
       a: openArray[SecretWord],
       exponent: openArray[byte]) {.tags:[VarTime, Alloca], meter.} =
  ## r <- a^exponent

  r.setOne()
  var isOne = true

  for e in exponent:
    for bit in unpackBE(e):
      if not isOne:
        r.square_vartime(r)
      if bit:
        if isOne:
          for i in 0 ..< a.len:
            r[i] = a[i]
          for i in a.len ..< r.len:
            r[i] = Zero
          isOne = false
        else:
          r.prod_vartime(r, a)

func powOddMod_vartime(
       r: var openArray[SecretWord],
       a: openArray[SecretWord],
       exponent: openArray[byte],
       M: openArray[SecretWord],
       window: int) {.noInline, tags:[Alloca, VarTime], meter.} =
  ## r <- a^exponent (mod M) with M odd
  ## assumes a < M
  ##
  ## At least (2^window + 4) * sizeof(M) stack space will be allocated.

  debug:
    doAssert bool(M.isOdd())

  let mBits  = M.getBits_LE_vartime()
  let eBits  = exponent.getBits_BE_vartime()

  if eBits == 1:
    discard r.reduce_vartime(a, M)
    return

  let L      = wordsRequired(mBits)
  let m0ninv = M[0].negInvModWord()

  var aMont_buf = allocStackArray(SecretWord, L)
  template aMont: untyped = aMont_buf.toOpenArray(0, L-1)

  aMont.getMont_vartime(a, M)

  block:
    var oneMontBuf = allocStackArray(SecretWord, L)
    template oneMont: untyped = oneMontBuf.toOpenArray(0, L-1)
    oneMont.oneMont_vartime(M.toOpenArray(0, L-1))

    let scratchLen = L * ((1 shl window) + 1)
    var scratchSpace = allocStackArray(SecretWord, scratchLen)

    aMont_buf.LimbsViewMut.powMont_vartime(
      exponent, M.view(), LimbsViewConst oneMontBuf,
      m0ninv, LimbsViewMut scratchSpace, scratchLen, mBits)

  r.view().fromMont(LimbsViewConst aMont_buf, M.view(), m0ninv, mBits)

func powMod_vartime*(
       r: var openArray[SecretWord],
       a: openArray[SecretWord],
       exponent: openArray[byte],
       M: openArray[SecretWord],
       window: int) {.noInline, tags:[Alloca, VarTime], meter.} =
  ## r <- a^exponent (mod M) with M odd
  ## assumes a < exponent
  ##
  ## At least (2^window + 4) * sizeof(M) stack space will be allocated.

  # Special cases: early returns
  # -------------------------------------------------------------------
  let mBits = M.getBits_LE_vartime()
  if mBits < 2: # Check if modulus = 0 or 1
    r.setZero()
    return

  let eBits = exponent.getBits_BE_vartime()
  if eBits == 0: # Check if exponent == 0
    r.setOne()   # a⁰ = 1 and 0⁰ = 1
    return

  let aBits = a.getBits_LE_vartime()
  if aBits < 2:  # Check if a == 0 or a == 1
    r[0] = a[0]
    for i in 1 ..< r.len:
      r[i] = Zero
    return

  # No modular reduction needed
  # -------------------------------------------------------------------
  if eBits < WordBitWidth and
     aBits.uint shr (WordBitWidth - eBits) == 0 and # handle overflow of uint128 [0, aBits] << eBits
     aBits.uint shl eBits < mBits.uint:
    r.pow_vartime(a, exponent)
    return

  # Odd modulus
  # -------------------------------------------------------------------
  if M.isOdd().bool:
    r.powOddMod_vartime(a, exponent, M, window)
    return

  # Even modulus
  # -------------------------------------------------------------------

  let ctz = block:
    var i = 0

    # Find the first non-zero word from right-to-left. (a != 0)
    while i < M.len-1:
      if bool(M[i] != Zero):
        break
      i += 1

    int(countTrailingZeroBits_vartime(BaseType M[i])) +
            WordBitWidth*i

  # Even modulus: power of two (mod 2ᵏ)
  # -------------------------------------------------------------------

  if mBits-ctz == 1: # The modulus is a power of 2
    r.powMod2k_vartime(a, exponent, k = uint ctz)
    return

  # Even modulus: general case
  # -------------------------------------------------------------------
  #
  # We split exponentiation aᵉ (mod M)
  # into a₁ = aᵉ (mod q)
  #  and a₂ = aᵉ (mod 2ᵏ)
  # with M = q.2ᵏ
  # and we recombine the results using the Chinese Remainder Theorem.
  # following
  #   Montgomery reduction with even modulus
  #   Çetin Kaya Koç, 1994
  #   https://cetinkayakoc.net/docs/j34.pdf

  let qBits = mBits-ctz
  let kBits = 1+ctz
  let qWords = qBits.wordsRequired()
  let kWords = kBits.wordsRequired()

  var qBuf  = allocStackArray(SecretWord, qWords)
  var a1Buf = allocStackArray(SecretWord, qWords)
  var a2Buf = allocStackArray(SecretWord, kWords)
  var yBuf =  allocStackArray(SecretWord, kWords)
  var qInv2kBuf = allocStackArray(SecretWord, kWords)

  template q: untyped = qBuf.toOpenArray(0, qWords-1)
  template a1: untyped = a1Buf.toOpenArray(0, qWords-1)
  template a2: untyped = a2Buf.toOpenArray(0, kWords-1)
  template y: untyped = yBuf.toOpenArray(0, kWords-1)
  template qInv2k: untyped = qInv2kBuf.toOpenArray(0, kWords-1)

  q.shiftRight_vartime(M, ctz)

  a1.powOddMod_vartime(a, exponent, q, window)
  a2.powMod2k_vartime(a, exponent, k = uint ctz)

  qInv2k.invMod2k_vartime(q, uint ctz)
  y.submod2k_vartime(a2, a1, uint ctz)
  y.mulmod2k_vartime(y, qInv2k, uint ctz)

  var qyBuf = allocStackArray(SecretWord, M.len)
  template qy: untyped = qyBuf.toOpenArray(0, M.len-1)
  qy.prod_vartime(q, y)
  discard r.addMP(qy, a1)
