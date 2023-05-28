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
  ./limbs_extmul,
  ./limbs_multiprec

# No exceptions allowed
{.push raises: [], checks: off.}

func mod2k_vartime*(a: var openArray[SecretWord], k: uint) =
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

func submod2k_vartime*(r{.noAlias.}: var openArray[SecretWord], a, b: openArray[SecretWord], k: uint) =
  ## r <- a - b (mod 2ᵏ)
  debug:
    const SlotShift = log2_vartime(WordBitWidth.uint32)
    doAssert r.len > k.int shr SlotShift

  if a.len >= b.len:
    let underflow {.used.} = r.subMP(a, b)
  else:
    let underflow {.used.} = r.subMP(b, a)
    r.neg()

  r.mod2k_vartime(k)

func mulmod2k_vartime*(r: var openArray[SecretWord], a, b: openArray[SecretWord], k: uint) {.inline.} =
  ## r <- a*b (mod 2ᵏ)
  r.prod(a, b)
  r.mod2k_vartime(k)

iterator unpack(scalarByte: byte): bool =
  yield bool((scalarByte and 0b10000000) shr 7)
  yield bool((scalarByte and 0b01000000) shr 6)
  yield bool((scalarByte and 0b00100000) shr 5)
  yield bool((scalarByte and 0b00010000) shr 4)
  yield bool((scalarByte and 0b00001000) shr 3)
  yield bool((scalarByte and 0b00000100) shr 2)
  yield bool((scalarByte and 0b00000010) shr 1)
  yield bool( scalarByte and 0b00000001)

func powMod2k_vartime*(
       r{.noAlias.}: var openArray[SecretWord],
       a{.noAlias.}: openArray[SecretWord],
       exponent: openArray[byte], k: uint) =
  ## r <- a^exponent (mod 2ᵏ)
  ##
  ## Requires:
  ## - r.len > 0
  ## - r.len <= a.len
  ## - r.len >= ceilDiv(k, WordBitWidth) = (k+63)/64
  ## - r and a don't alias

  # TODO window method

  for i in 0 ..< r.len:
    r[i] = Zero
  r[0] = One

  for e in exponent:
    for bit in unpack(e):
      r.mulmod2k_vartime(r, r, k)
      if bit:
        r.mulmod2k_vartime(r, a, k)

func invModBitwidth(a: SecretWord): SecretWord {.borrow.}
  ## Inversion a⁻¹ (mod 2³²) or a⁻¹ (mod 2⁶⁴)

func invMod2k_vartime*(a: var openArray[SecretWord], k: uint) {.noInline, tags: [Alloca].} =
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

  var x = allocStackArray(SecretWord, a.len)
  var t = allocStackArray(SecretWord, a.len)
  var u = allocStackArray(SecretWord, a.len)

  x[0] = a[0].invModBitwidth()
  for i in 1 ..< a.len:
    x[i] = Zero

  var correctWords = 1

  while correctWords.uint*WordBitWidth < k:
    # x *= 2-ax
    let words = 2*correctWords
    t.toOpenArray(0, words-1)
     .mulmod2k_vartime(
       x.toOpenArray(0, correctWords-1),
       a.toOpenArray(0, words-1),
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

  x.toOpenArray(0, a.len-1).mod2k_vartime(k)
  for i in 0 ..< a.len:
    a[i] = x[i]