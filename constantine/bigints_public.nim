# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  ./bigints_raw,
  ./primitives

# ############################################################
#
#                   BigInts Public API
#
# ############################################################

# The "public" API, exported for finite field computations
# enforced compile-time checking of BigInt bitsize
#
# The "raw" compute API, uses views to avoid code duplication due to generic/static monomorphization.

# No exceptions allowed
{.push raises: [].}
{.push inline.}

func isZero*(a: BigInt): CTBool[Word] =
  ## Returns true if a big int is equal to zero
  a.view.isZero

func add*[bits](a: var BigInt[bits], b: BigInt[bits], ctl: CTBool[Word]): CTBool[Word] =
  ## Constant-time big integer in-place optional addition
  ## The addition is only performed if ctl is "true"
  ## The result carry is always computed.
  add(a.view, b.view, ctl)

func sub*[bits](a: var BigInt[bits], b: BigInt[bits], ctl: CTBool[Word]): CTBool[Word] =
  ## Constant-time big integer in-place optional addition
  ## The addition is only performed if ctl is "true"
  ## The result carry is always computed.
  sub(a.view, b.view, ctl)

func reduce*[aBits, mBits](r: var BigInt[mBits], a: BigInt[aBits], M: BigInt[mBits]) =
  ## Reduce `a` modulo `M` and store the result in `r`
  ##
  ## The modulus `M` **must** use `mBits` bits (bits at position mBits-1 must be set)
  ##
  ## CT: Depends only on the length of the modulus `M`

  # Note: for all cryptographic intents and purposes the modulus is known at compile-time
  # but we don't want to inline it as it would increase codesize, better have Nim
  # pass a pointer+length to a fixed session of the BSS.
  reduce(r.view, a.view, M.view)
