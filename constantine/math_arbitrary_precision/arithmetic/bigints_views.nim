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
  ./limbs_division

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

func powOddMod_vartime*(
       r: var openArray[SecretWord],
       a: openArray[SecretWord],
       exponent: openArray[byte],
       M: openArray[SecretWord],
       window: int) {.noInline, tags:[Alloca, VarTime].} =
  ## r <- a^exponent (mod M) with M odd
  ## assumes a < M
  ##
  ## At least (2^window + 4) * sizeof(M) stack space will be allocated.

  debug:
    doAssert bool(M.isOdd())

  let aBits  = a.getBits_LE_vartime()
  let mBits  = M.getBits_LE_vartime()
  let L      = wordsRequired(mBits)
  let m0ninv = M[0].negInvModWord()
  var rMont  = allocStackArray(SecretWord, L)

  block:
    var r2Buf = allocStackArray(SecretWord, L)
    template r2: untyped = r2Buf.toOpenArray(0, L-1)
    r2.r2_vartime(M.toOpenArray(0, L-1))

    # Conversion to Montgomery can auto-reduced by up to M*R
    # if we use redc2xMont (a/R) and montgomery multiplication by R³
    # For now, we call explicit reduction as it can handle all sizes.
    # TODO: explicit reduction uses constant-time division which is **very** expensive
    if a.len != M.len:
      let t = allocStackArray(SecretWord, L)
      t.LimbsViewMut.reduce(a.view(), aBits, M.view(), mBits)
      rMont.LimbsViewMut.getMont(LimbsViewConst t, M.view(), LimbsViewConst r2.view(), m0ninv, mBits)
    else:
      rMont.LimbsViewMut.getMont(a.view(), M.view(), LimbsViewConst r2.view(), m0ninv, mBits)

  block:
    var oneMontBuf = allocStackArray(SecretWord, L)
    template oneMont: untyped = oneMontBuf.toOpenArray(0, L-1)
    oneMont.oneMont_vartime(M.toOpenArray(0, L-1))

    let scratchLen = L * ((1 shl window) + 1)
    var scratchSpace = allocStackArray(SecretWord, scratchLen)

    rMont.LimbsViewMut.powMont_vartime(
      exponent, M.view(), LimbsViewConst oneMontBuf,
      m0ninv, LimbsViewMut scratchSpace, scratchLen, mBits)

  r.view().fromMont(LimbsViewConst rMont, M.view(), m0ninv, mBits)


func powMod_vartime*(
       r: var openArray[SecretWord],
       a: openArray[SecretWord],
       exponent: openArray[byte],
       M: openArray[SecretWord],
       window: int) {.noInline, tags:[Alloca, VarTime].} =
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
  let pBits = 1+ctz
  let qWords = qBits.wordsRequired()
  let pWords = pBits.wordsRequired()

  var qBuf  = allocStackArray(SecretWord, qWords)
  var a1Buf = allocStackArray(SecretWord, qWords)
  var a2Buf = allocStackArray(SecretWord, pWords)
  var yBuf =  allocStackArray(SecretWord, pWords)
  var qInv2kBuf = allocStackArray(SecretWord, pWords)

  template q: untyped = qBuf.toOpenArray(0, qWords-1)
  template a1: untyped = a1Buf.toOpenArray(0, qWords-1)
  template a2: untyped = a2Buf.toOpenArray(0, pWords-1)
  template y: untyped = yBuf.toOpenArray(0, pWords-1)
  template qInv2k: untyped = qInv2kBuf.toOpenArray(0, pWords-1)

  q.shiftRight_vartime(M, ctz)

  a1.powOddMod_vartime(a, exponent, q, window)
  a2.powMod2k_vartime(a, exponent, k = uint ctz)

  qInv2k.invMod2k_vartime(qBuf.toOpenArray(0, qWords-1), uint ctz)
  y.submod2k_vartime(a2, a1, uint ctz)
  y.mulmod2k_vartime(y, qInv2k, uint ctz)

  var qyBuf = allocStackArray(SecretWord, M.len)
  template qy: untyped = qyBuf.toOpenArray(0, M.len-1)
  qy.prod(q, y)
  discard r.addMP(qy, a1)
