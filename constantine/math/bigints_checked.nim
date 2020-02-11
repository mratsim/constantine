# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  ./bigints_raw,
  ../primitives/constant_time,
  ../config/common

# ############################################################
#
#                BigInts type-checked API
#
# ############################################################

# The "checked" API is exported as a building blocks
# with enforced compile-time checking of BigInt bitsize
# and memory ownership.
#
# The "raw" compute API uses views to avoid code duplication
# due to generic/static monomorphization.
#
# The "checked" API is a thin wrapper above the "raw" API to get the best of both world:
# - small code footprint
# - compiler enforced checks: types, bitsizes (dependant types)
# - compiler enforced memory: stack allocation and buffer ownership

func wordsRequired(bits: int): int {.compileTime.} =
  ## Compute the number of limbs required
  # from the **announced** bit length
  (bits + WordBitSize - 1) div WordBitSize

type
  BigInt*[bits: static int] = object
    ## Fixed-precision big integer
    ##
    ## - "bits" is the announced bit-length of the BigInt
    ##   This is public data, usually equal to the curve prime bitlength.
    ##
    ## - "bitLength" is the internal bitlength of the integer
    ##   This differs from the canonical bit-length as
    ##   Constantine word-size is smaller than a machine word.
    ##   This value should never be used as-is to prevent leaking secret data.
    ##   Computing this value requires constant-time operations.
    ##   Using this value requires converting it to the # of limbs in constant-time
    ##
    ## - "limbs" is an internal field that holds the internal representation
    ##   of the big integer. Least-significant limb first. Within limbs words are native-endian.
    ##
    ## This internal representation can be changed
    ## without notice and should not be used by external applications or libraries.
    bitLength: uint32
    limbs*: array[bits.wordsRequired, Word]

template view*(a: BigInt): BigIntViewConst =
  ## Returns a borrowed type-erased immutable view to a bigint
  BigIntViewConst(cast[BigIntView](a.unsafeAddr))

template view*(a: var BigInt): BigIntViewMut =
  ## Returns a borrowed type-erased mutable view to a mutable bigint
  BigIntViewMut(cast[BigIntView](a.addr))

debug:
  func `==`*(a, b: BigInt): CTBool[Word] =
    ## Returns true if 2 big ints are equal
    var accum: Word
    for i in static(0 ..< a.limbs.len):
      accum = accum or (a.limbs[i] xor b.limbs[i])
    result = accum.isZero

# No exceptions allowed
{.push raises: [].}
{.push inline.}

func setInternalBitLength*(a: var BigInt) {.inline.} =
  ## Derive the actual bitsize used internally of a BigInt
  ## from the announced BigInt bitsize
  ## and set the bitLength field of that BigInt
  ## to that computed value.
  a.bitLength = static(a.bits + a.bits div WordBitSize)

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
