# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  # Internal
  ../../platforms/abstractions,
  ../../math/arithmetic/limbs_exgcd,
  ./limbs_views,
  ./limbs_extmul,
  ./limbs_multiprec

# No exceptions allowed
{.push raises: [], checks: off.}

func mod2k_vartime*(a: var openArray[SecretWord], k: uint) {.meter.} =
  ## a <- a (mod 2ᵏ)
  const SlotShift = log2_vartime(WordBitWidth.uint32)
  const SelectMask = WordBitWidth - 1

  let hiIndex = k.int shr SlotShift

  if a.len <= hiIndex:
    return

  let bitPos = k and SelectMask

  if bitPos != 0:
    let mask = (One shl bitPos) - One
    a[hiIndex] = a[hiIndex] and mask
  else:
    a[hiIndex] = Zero

  for i in hiIndex+1 ..< a.len:
    a[i] = Zero

func submod2k_vartime*(r{.noAlias.}: var openArray[SecretWord], a, b: openArray[SecretWord], k: uint) {.meter.} =
  ## r <- a - b (mod 2ᵏ)
  debug:
    const SlotShift = log2_vartime(WordBitWidth.uint32)
    doAssert r.len >= k.int shr SlotShift, block:
      "\n" &
      "  r.len: " & $r.len & "\n" &
      "  k: " & $k & "\n" &
      "  k/WordBitWidth: " & $(k.int shr SlotShift) &
      "\n" # [AssertionDefect]

  # We can compute (mod 2ʷ) with w >= k
  # Hence we truncate the substraction to the next multiple of the word size
  template trunc(x: openArray[SecretWord]): openArray[SecretWord] =
    let truncHi =  min(x.len, k.int.wordsRequired()) - 1
    x.toOpenArray(0, truncHi)

  if a.len >= b.len:
    let underflow {.used.} = r.subMP(a.trunc(), b.trunc())
  else:
    let underflow {.used.} = r.subMP(b.trunc(), a.trunc())
    r.neg()

  r.mod2k_vartime(k)

func mulmod2k_vartime*(r: var openArray[SecretWord], a, b: openArray[SecretWord], k: uint) {.inline, meter.} =
  ## r <- a*b (mod 2ᵏ)
  r.prod_vartime(a, b)
  r.mod2k_vartime(k)

func sqrmod2k_vartime*(r: var openArray[SecretWord], a: openArray[SecretWord], k: uint) {.inline, meter.} =
  ## r <- a² (mod 2ᵏ)
  r.square_vartime(a)
  r.mod2k_vartime(k)

iterator unpackLE(scalarByte: byte): bool =
  for i in 0 ..< 8:
    yield bool((scalarByte shr i) and 1)

func powMod2k_vartime*(
       r{.noAlias.}: var openArray[SecretWord],
       a{.noAlias.}: openArray[SecretWord],
       exponent: openArray[byte], k: uint) {.noInline, tags: [Alloca], meter.} =
  ## r <- a^exponent (mod 2ᵏ)
  ##
  ## Requires:
  ## - r.len > 0
  ## - r.len <= a.len
  ## - r.len >= ceilDiv(k, WordBitWidth) = (k+63)/64
  ## - r and a don't alias

  # Fast special cases:
  # 1. if a is even, it can be represented as a = 2b
  #    if exponent e is greater than k, e = k+n
  #    we have r ≡ aᵉ (mod 2ᵏ) ≡ (2b)ᵏ⁺ⁿ (mod 2ᵏ)
  #                            ≡ 2ᵏ.2ⁿ.bᵏ⁺ⁿ (mod 2ᵏ)
  #                            ≡ 0 (mod 2ᵏ)
  # 2. if a is odd, a and 2ᵏ are coprime
  #    we can apply the Euler's totient theorem (https://en.wikipedia.org/wiki/Euler%27s_theorem
  #    i.e. aᵠ⁽²^ᵏ⁾ ≡ 1 (mod 2ᵏ)
  #    with
  #    - ψ(n), the Euler's totient function, the count of coprimes in [0, n)
  #      ψ(2ᵏ) = 2ᵏ⁻¹ as half the number (i.e. the odd numbers) are coprimes
  #      with a power of 2.
  #    - e' = e (mod ψ(2ᵏ))
  #      aᵉ (mod 2ᵏ) ≡ aᵉ' (mod 2ᵏ)
  #
  # The remaining case is when a is even
  # and exponent < 2ᵏ⁻¹
  #
  # We use LSB to MSB square-and-multiply algorithm
  # with early stopping when we reach ψ(2ᵏ) if a is odd

  for i in 0 ..< r.len:
    r[i] = Zero

  let msb = getMSB_BE_vartime(exponent)

  if msb == -1: # exponent is 0
    r[0] = One  # x⁰ = 1, even for 0⁰
    return

  if msb == 0: # exponent is 1
    for i in 0 ..< min(r.len, a.len):
      # range [r.len, a.len) will be truncated (mod 2ᵏ)
      r[i] = a[i]
    r.mod2k_vartime(k)
    return

  if a.isEven().bool:
    let aTrailingZeroes = block:
      var i = 0
      while i < a.len-1:
        if bool(a[i] != Zero):
          break
        i += 1
      int(countTrailingZeroBits_vartime(BaseType a[i])) +
              WordBitWidth*i
                                     # if a is even, a = 2b and if e > k then there exists n such that e = k+n
    if aTrailingZeroes+msb >= k.int: # r ≡ aᵉ (mod 2ᵏ) ≡ (2b)ᵏ⁺ⁿ (mod 2ᵏ) ≡ 2ᵏ.2ⁿ.bᵏ⁺ⁿ (mod 2ᵏ) ≡ 0 (mod 2ᵏ)
      return                         # we can generalize to a = 2ᵗᶻb with tz the number of trailing zeros.

  var bitsLeft = msb+1
  if a.isOdd().bool and   # if a is odd
     int(k-1) < bitsLeft:
    bitsLeft = int(k-1)   # Euler's totient acceleration

  r[0] = One

  var sBuf = allocStackArray(SecretWord, r.len)
  template s: untyped = sBuf.toOpenArray(0, r.len-1)

  let truncLen = min(r.len, a.len)
  for i in 0 ..< truncLen:
    # range [r.len, a.len) will be truncated (mod 2ᵏ)
    sBuf[i] = a[i]
  for i in truncLen ..< r.len:
    sBuf[i] = Zero

  # TODO: sliding/fixed window exponentiation
  for i in countdown(exponent.len-1, 0): # Little-endian exponentiation
    for bit in unpackLE(exponent[i]):
      if bit:
        r.mulmod2k_vartime(r, s, k)
      s.sqrmod2k_vartime(s, k)
      bitsLeft -= 1
      if bitsLeft == 0:
        return

func invModBitwidth(a: SecretWord): SecretWord {.borrow.}
  ## Inversion a⁻¹ (mod 2³²) or a⁻¹ (mod 2⁶⁴)

func invMod2k_vartime*(r: var openArray[SecretWord], a: openArray[SecretWord], k: uint) {.noInline, tags: [Alloca], meter.} =
  ## Inversion a⁻¹ (mod 2ᵏ)
  ## with 2ᵏ a multi-precision integer.
  #
  # Algorithm:
  # - Dumas iteration based on Newton-Raphson (see litterature in invModBitwidth)
  #   ax ≡ 1 (mod 2ᵏ) <=> ax(2 - ax) ≡ 1 (mod 2²ᵏ)
  #   which grows in O(log(log(a)))
  # - start with a seed inverse a'⁻¹ (mod 2ⁿ)
  #   we can start with 2³² or 2⁶⁴
  # - Double the number of correct bits at each Dumas iteration
  # - once n >= k, reduce mod 2ᵏ

  debug:
    const SlotShift = log2_vartime(WordBitWidth.uint32)
    doAssert r.len >= k.int shr SlotShift, block:
      "\n" &
      "  r.len: " & $r.len & "\n" &
      "  k: " & $k & "\n" &
      "  k/WordBitWidth: " & $(k.int shr SlotShift) &
      "\n" # [AssertionDefect]

  var x = allocStackArray(SecretWord, r.len)
  var t = allocStackArray(SecretWord, r.len)
  var u = allocStackArray(SecretWord, r.len)

  x[0] = a[0].invModBitwidth()
  for i in 1 ..< r.len:
    x[i] = Zero

  var correctWords = 1

  while correctWords.uint*WordBitWidth < k:
    # x *= 2-ax
    let words = min(r.len, 2*correctWords)
    t.toOpenArray(0, words-1)
     .mulmod2k_vartime(
       x.toOpenArray(0, correctWords-1),
       a.toOpenArray(0, a.len-1),
       words.uint*WordBitWidth)

    u.toOpenArray(0, words-1)
     .submod2k_vartime(
       [SecretWord 2],
       t.toOpenArray(0, words-1),
       words.uint*WordBitWidth)

    x.toOpenArray(0, words-1)
     .mulmod2k_vartime(
       x.toOpenArray(0, correctWords-1),
       u.toOpenArray(0, words-1),
       words.uint*WordBitWidth)

    correctWords = words

  x.toOpenArray(0, r.len-1).mod2k_vartime(k)
  for i in 0 ..< r.len:
    r[i] = x[i]