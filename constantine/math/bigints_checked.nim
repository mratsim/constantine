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
    bitLength*: uint32
    limbs*: array[bits.wordsRequired, Word]

template view*(a: BigInt): BigIntViewConst =
  ## Returns a borrowed type-erased immutable view to a bigint
  BigIntViewConst(cast[BigIntView](a.unsafeAddr))

template view*(a: var BigInt): BigIntViewMut =
  ## Returns a borrowed type-erased mutable view to a mutable bigint
  BigIntViewMut(cast[BigIntView](a.addr))

debug:
  import strutils

  func `==`*(a, b: BigInt): CTBool[Word] =
    ## Returns true if 2 big ints are equal
    var accum: Word
    for i in static(0 ..< a.limbs.len):
      accum = accum or (a.limbs[i] xor b.limbs[i])
    result = accum.isZero

  func `$`*(a: BigInt): string =
    result = "BigInt["
    result.add $BigInt.bits
    result.add "](bitLength: "
    result.add $a.bitLength
    result.add ", limbs: ["
    result.add $BaseType(a.limbs[0]) & " (0x" & toHex(BaseType(a.limbs[0])) & ')'
    for i in 1 ..< a.limbs.len:
      result.add ", "
      result.add $BaseType(a.limbs[i]) & " (0x" & toHex(BaseType(a.limbs[i])) & ')'
    result.add "])"

# No exceptions allowed
{.push raises: [].}
{.push inline.}

func setInternalBitLength*(a: var BigInt) {.inline.} =
  ## Derive the actual bitsize used internally of a BigInt
  ## from the announced BigInt bitsize
  ## and set the bitLength field of that BigInt
  ## to that computed value.
  a.bitLength = uint32 static(a.bits + a.bits div WordBitSize)

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

func montyResidue*[mBits](mres: var BigInt[mBits], a, N, r2modN: BigInt[mBits], negInvModWord: static BaseType) =
  ## Convert a BigInt from its natural representation
  ## to the Montgomery n-residue form
  ##
  ## `mres` is overwritten. It's bitlength must be properly set before calling this procedure.
  ##
  ## Caller must take care of properly switching between
  ## the natural and montgomery domain.
  ## Nesting Montgomery form is possible by applying this function twice.
  montyResidue(mres.view, a.view, N.view, r2modN.view, Word(negInvModWord))

func redc*[mBits](r: var BigInt[mBits], a, N: BigInt[mBits], negInvModWord: static BaseType) =
  ## Convert a BigInt from its Montgomery n-residue form
  ## to the natural representation
  ##
  ## `mres` is modified in-place
  ##
  ## Caller must take care of properly switching between
  ## the natural and montgomery domain.
  let one = block:
    var one: BigInt[mBits]
    one.setInternalBitLength()
    one.limbs[0] = Word(1)
    one
  redc(r.view, a.view, one.view, N.view, Word(negInvModWord))

func montyMul*[mBits](r: var BigInt[mBits], a, b, M: BigInt[mBits], negInvModWord: static BaseType) =
  ## Compute r <- a*b (mod M) in the Montgomery domain
  ##
  ## This resets r to zero before processing. Use {.noInit.}
  ## to avoid duplicating with Nim zero-init policy
  montyMul(r.view, a.view, b.view, M.view, Word(negInvModWord))

import stew/byteutils

func montyPow*[mBits, eBits: static int](
       a: var BigInt[mBits], exponent: BigInt[eBits],
       M, one: BigInt[mBits], negInvModWord: static BaseType, windowSize: static int) =
  ## Compute a <- a^exponent (mod M)
  ## ``a`` in the Montgomery domain
  ## ``exponent`` is any BigInt, in the canonical domain
  ##
  ## This uses fixed window optimization
  ## A window size in the range [1, 5] must be chosen
  ##
  ## This is constant-time: the window optimization does
  ## not reveal the exponent bits or hamming weight
  mixin exportRawUint # exported in io_bigints which depends on this module ...

  var expBE {.noInit.}: array[(ebits + 7) div 8, byte]
  expBE.exportRawUint(exponent, bigEndian)

  const scratchLen = if windowSize == 1: 2
                     else: (1 shl windowSize) + 1
  var scratchSpace {.noInit.}: array[scratchLen, BigInt[mBits]]
  var scratchPtrs {.noInit.}: array[scratchLen, BigIntViewMut]
  for i in 0 ..< scratchLen:
    scratchPtrs[i] = scratchSpace[i].view()

  montyPow(a.view, expBE, M.view, one.view, Word(negInvModWord), scratchPtrs)
