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
  ./limbs_multiprec

# ############################################################
#
#               Multi-precision modular arithmetic
#
# ############################################################

func addmod_vartime*(r: var openArray[SecretWord], a, b, M: openArray[SecretWord]) {.meter.} =
  ## r <- a+b (mod M)
  ## assumes a and b are in the range [0, M)

  debug:
    doAssert r.len == M.len

  var tBuf = allocStackArray(SecretWord, r.len)
  template t: untyped = tBuf.toOpenArray(0, r.len-1)

  let overflow = t.addMP(a, b)

  if overflow:
    # t <- a+b overflowed so it is greater than M.
    discard r.subMP(t, M)
    return

  # Operation didn't overflow in an extra limb but r can still be greater than M
  let underflow = r.subMP(t, M)
  # r <- t-M
  # If there is an underflow t < M, t has the correct result
  # if there isn't an underflow, t >= M, r has the correct result
  if underflow:
    for i in 0 ..< r.len:
      r[i] = t[i]

func doublemod_vartime*(r: var openArray[SecretWord], a, M: openArray[SecretWord]) {.inline, meter.} =
  ## r <- 2a (mod M)
  r.addmod_vartime(a, a, M)