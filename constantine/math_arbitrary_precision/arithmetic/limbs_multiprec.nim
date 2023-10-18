# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  # Internal
  ../../platforms/abstractions

# ############################################################
#
#               Multi-precision arithmetic
#
# ############################################################
#
# This file implements multi-precision primitives
# with unbalanced number of limbs.

# Logical Shift Right
# --------------------------------------------------------

func shrSmall(r {.noalias.}: var openArray[SecretWord], a: openArray[SecretWord], k: SomeInteger) =
  ## Shift right by k.
  ##
  ## k MUST be less than the base word size (2^32 or 2^64)
  # Note: for speed, loading a[i] and a[i+1]
  #       instead of a[i-1] and a[i]
  #       is probably easier to parallelize for the compiler
  #       (antidependence WAR vs loop-carried dependence RAW)
  for i in 0 ..< a.len-1:
    r[i] = (a[i] shr k) or (a[i+1] shl (WordBitWidth - k))
  if a.len-1 < r.len:
    r[a.len-1] = a[a.len-1] shr k

  for i in a.len ..< r.len:
    r[i] = Zero

func shrLarge(r {.noalias.}: var openArray[SecretWord], a: openArray[SecretWord], w, shift: SomeInteger) =
  ## Shift right by `w` words + `shift` bits
  if w >= a.len:
    r.setZero()
    return

  for i in w ..< a.len-1:
    r[i-w] = (a[i] shr shift) or (a[i+1] shl (WordBitWidth - shift))
  if a.len-1-w < r.len:
    r[a.len-1-w] = a[a.len-1] shr shift

  for i in a.len-w ..< r.len:
    r[i] = Zero

func shrWords(r {.noalias.}: var openArray[SecretWord], a: openArray[SecretWord], w: SomeInteger) =
  ## Shift right by w word
  if w >= a.len:
    r.setZero()
    return

  for i in 0 ..< a.len-w:
    r[i] = a[i+w]

  for i in a.len-w ..< r.len:
    r[i] = Zero

func shiftRight_vartime*(r {.noalias.}: var openArray[SecretWord], a: openArray[SecretWord], k: SomeInteger) {.meter.} =
  ## Shift `a` right by k bits and store in `r`
  if k == 0:
    let min = min(a.len, r.len)
    for i in 0 ..< min:
      r[i] = a[i]
    for i in min ..< r.len:
      r[i] = Zero
    return

  if k < WordBitWidth:
    r.shrSmall(a, k)
    return

  # w = k div WordBitWidth, shift = k mod WordBitWidth
  let w     = k shr static(log2_vartime(uint32(WordBitWidth)))
  let shift = k and (WordBitWidth - 1)

  if shift == 0:
    r.shrWords(a, w)
  else:
    r.shrLarge(a, w, shift)

func shlSmall(r: var openArray[SecretWord], a: openArray[SecretWord], k: SomeInteger) =
  ## Compute the `shift left` operation of x and k
  ##
  ## k MUST be less than the base word size (2^32 or 2^64)
  r[0] = a[0] shl k
  for i in 1 ..< a.len:
    r[i] = (a[i] shl k) or (a[i-1] shr (WordBitWidth - k))

  for i in a.len ..< r.len:
    r[i] = Zero

func shlLarge(r: var openArray[SecretWord], a: openArray[SecretWord], w, shift: SomeInteger) =
  ## Shift left by `w` words + `shift` bits
  ## Assumes `r` is 0 initialized
  if w >= a.len:
    return

  r[w] = a[0] shl shift
  for i in 1+w ..< r.len:
    r[i] = (a[i-w] shl shift) or (a[i-w-1] shr (WordBitWidth - shift))

  for i in a.len-w ..< r.len:
    r[i] = Zero

func shlWords(r: var openArray[SecretWord], a: openArray[SecretWord], w: SomeInteger) =
  ## Shift left by w word
  if w >= r.len:
    r.setZero()
    return

  for i in 0 ..< w:
    r[i] = Zero

  for i in w ..< a.len+w:
    r[i] = a[i-w]

  for i in a.len+w ..< r.len:
    r[i] = Zero

func shiftLeft_vartime*(r: var openArray[SecretWord], a: openArray[SecretWord], k: SomeInteger) {.meter.} =
  ## Shift `a` left by k bits and store in `r`
  if k == 0:
    let min = min(a.len, r.len)
    for i in 0 ..< min:
      r[i] = a[i]
    for i in min ..< r.len:
      r[i] = Zero
    return

  if k < WordBitWidth:
    r.shlSmall(a, k)
    return

  # w = k div WordBitWidth, shift = k mod WordBitWidth
  let w     = k shr static(log2_vartime(uint32(WordBitWidth)))
  let shift = k and (WordBitWidth - 1)

  if shift == 0:
    r.shlWords(a, w)
  else:
    r.shlLarge(a, w, shift)

# Arithmetic
# --------------------------------------------------------

func neg*(a: var openArray[SecretWord]) {.meter.} =
  ## Computes the additive inverse -a
  ## in 2-complement representation

  # Algorithm: -a = not(a) + 1
  var carry = Carry(0)
  addC(carry, a[0], not(a[0]), One, carry)
  for i in 1 ..< a.len:
    addC(carry, a[i], not(a[i]), Zero, carry)

func addMP*(r {.noAlias.}: var openArray[SecretWord], a, b: openArray[SecretWord]): bool {.meter.} =
  ## r <- a + b
  ##   and
  ## returns the carry
  ##
  ## Requirements:
  ## - r.len >= a.len
  ## - r.len >= b.len

  debug:
    doAssert r.len >= a.len
    doAssert r.len >= b.len

  if a.len < b.len:
    return r.addMP(b, a)

  let minLen = b.len
  let maxLen = a.len

  var carry = Carry(0)
  for i in 0 ..< minLen:
    addC(carry, r[i], a[i], b[i], carry)
  for i in minLen ..< maxLen:
    addC(carry, r[i], a[i], Zero, carry)

  if maxLen < r.len:
    r[maxLen] = SecretWord(carry)
    for i in maxLen+1 ..< r.len:
      r[i] = Zero
    return false # the rest cannot carry
  else:
    return bool carry

func subMP*(r {.noAlias.}: var openArray[SecretWord], a, b: openArray[SecretWord]): bool {.meter.} =
  ## r <- a - b
  ##   and
  ## returns false if a >= b
  ## returns true if  a < b
  ##   (in that case the 2-complement is stored)
  ##
  ## Requirements:
  ## - r.len >= a.len
  ## - a.len >= b.len

  debug:
    doAssert r.len >= a.len
    doAssert a.len >= b.len

  let minLen = b.len
  let maxLen = a.len

  var borrow = Borrow(0)
  for i in 0 ..< minLen:
    subB(borrow, r[i], a[i], b[i], borrow)
  for i in minLen ..< maxLen:
    subB(borrow, r[i], a[i], Zero, borrow)

  result = bool borrow

  # if a >= b, no borrow, mask = 0
  # if a < b, borrow, we store the 2-complement, mask = -1
  let mask = Zero - SecretWord(borrow)
  for i in maxLen ..< r.len:
    r[i] = mask