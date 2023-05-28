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

func neg*(a: var openArray[SecretWord]) =
  ## Computes the additive inverse -a
  ## in 2-complement representation

  # Algorithm: -a = not(a) + 1
  var carry = Carry(0)
  addC(carry, a[0], not(a[0]), One, carry)
  for i in 1 ..< a.len:
    addC(carry, a[i], not(a[i]), Zero, carry)

func addMP*(r {.noAlias.}: var openArray[SecretWord], a, b: openArray[SecretWord]): bool =
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

func subMP*(r {.noAlias.}: var openArray[SecretWord], a, b: openArray[SecretWord]): bool =
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