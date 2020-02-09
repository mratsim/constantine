# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.


# ############################################################
#
#                    BigInt representation
#
# ############################################################

# To avoid carry issues we don't use the
# most significant bit of each word.
# i.e. for a uint64 base we only use 63-bit.
# More info: https://github.com/status-im/nim-constantine/wiki/Constant-time-arithmetics#guidelines
# Especially:
#    - https://bearssl.org/bigint.html
#    - https://cryptojedi.org/peter/data/pairing-20131122.pdf
#    - http://docs.milagro.io/en/amcl/milagro-crypto-library-white-paper.html
#
# Note that this might also be beneficial in terms of performance.
# Due to opcode latency, on Nehalem ADC is 6x times slower than ADD
# if it has dependencies (i.e the ADC depends on a previous ADC result)

# Control flow should only depends on the static maximum number of bits
# This number is defined per Finite Field/Prime/Elliptic Curve
#
# For efficiency, our limbs will use a word size of 63-bit
# Warning ⚠️ : This assumes that u64 + u64 and u64 * u64
#              are constant-time even on 32-bit platforms
#
# We internally order the limbs in little-endian
# So the least significant limb is limb[0]
# This is independent from the base type endianness.

import ./word_types

type Word* = Ct[uint64]
type BaseType* = uint64 # Exported type for conversion in "normal integers"

const WordBitSize* = sizeof(Word) * 8 - 1
  ## Limbs are 63-bit by default

func wordsRequired(bits: int): int {.compileTime.}=
  (bits + WordBitSize - 1) div WordBitSize

# TODO: Currently the library is instantiation primitives like "add"
#       for each "bits" size supported. This will lead to duplication
#       if many sizes (for example for scp256k1, bn254 and BLS12-381)
#       are required.
#       It could be avoided by having the bitsize be a runtime field
#       of the bigint. However the tradeoff would be:
#       - overhead of this additional field
#       - limbs have to be stored in an UncheckedArray instead of an array
#         introducing memory management issues

type
  BigInt*[bits: static int] = object
    ## Fixed-precision big integer
    ##
    ## "limbs" is an internal field that holds the internal representation
    ## of the big integer. This internal representation can be changed
    ## without notice and should not be used by external applications or libraries.
    # Constantine BigInt have a word-size chosen to minimize bigint memory usage
    # while allowing carry-less operations in a machine-efficient type like uint32
    # uint64 or uint128 if available.
    # In practice the word size is 63-bit.
    #
    # "Limb-endianess" is little-endian (least significant limb at BigInt.limbs[0])
    limbs*: array[bits.wordsRequired, Word]

const MaxWord* = (not Ct[uint64](0)) shr 1
  ## This represents 0x7F_FF_FF_FF__FF_FF_FF_FF
  ## also 0b0111...1111
  ## This biggest representable number in our limbs.
  ## i.e. The most significant bit is never set at the end of each function

template `[]`*(a: Bigint, idx: int): Word =
  a.limbs[idx]

template `[]=`*(a: var Bigint, idx: int, w: Word) =
  a.limbs[idx] = w

# ############################################################
#
#                    BigInt primitives
#
# ############################################################

# No exceptions allowed
{.push raises: [].}
# TODO: {.inline.} analysis

func isZero*(a: BigInt): CTBool[Word] =
  ## Returns if a big int is equal to zero
  var accum: Word
  for i in static(0 ..< a.limbs.len):
    accum = accum or a.limbs[i]
  result = accum.isZero()

func `==`*(a, b: BigInt): CTBool[Word] =
  ## Returns true if 2 big ints are equal
  var accum: Word
  for i in static(0 ..< a.limbs.len):
    accum = accum or (a.limbs[i] xor b.limbs[i])
  result = accum.isZero

# The arithmetic primitives all accept a control input that indicates
# if it is a placebo operation. It stills performs the
# same memory accesses to be side-channel attack resistant.

func add*[bits](a: var BigInt[bits], b: BigInt[bits], ctl: CTBool[Word]): CTBool[Word] {.raises: [].}=
  ## Constant-time big integer in-place optional addition
  ## The addition is only performed if ctl is "true"
  ## The result carry is always computed.
  for i in static(0 ..< a.limbs.len):
    let new_a = a.limbs[i] + b.limbs[i] + Word(result)
    result = new_a.isMsbSet()
    a[i] = ctl.mux(new_a and MaxWord, a[i])

func sub*[bits](a: var BigInt[bits], b: BigInt[bits], ctl: CTBool[Word]): CTBool[Word] {.raises: [].}=
  ## Constant-time big integer in-place optional substraction
  ## The substraction is only performed if ctl is "true"
  ## The result carry is always computed.
  for i in static(0 ..< a.limbs.len):
    let new_a = a.limbs[i] - b.limbs[i] - Word(result)
    result = new_a.isMsbSet()
    a[i] = ctl.mux(new_a and MaxWord, a[i])
