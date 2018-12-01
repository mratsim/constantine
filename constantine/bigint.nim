# Constantine
# Copyright (c) 2018 Status Research & Development GmbH
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

# Big int internal representation.
#
# To avoid carry issues we don't use the
# most significant bit of each word.
# i.e. for a uint64 base we only use 63-bit.
# More info: https://github.com/status-im/nim-constantine/wiki/Constant-time-arithmetics#guidelines
# Especially:
#    - https://bearssl.org/bigint.html
#    - https://cryptojedi.org/peter/data/pairing-20131122.pdf
#    - http://docs.milagro.io/en/amcl/milagro-crypto-library-white-paper.html
#
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
# TODO: hexdumps

import ./word_types

type Limb* = Ct[uint64]

func limbBitSize*(): static int =
  sizeof(Limb) * 8 - 1

func words_required(bits: static int): static int =
  (bits + limbBitSize() - 1) div limbBitSize()

type
  BigInt*[bits: static int] = object
    limbs*: array[bits.words_required, Limb]

const highLimb* = (not Ct[uint64](0)) shr 1
  ## This represents 0x7F_FF_FF_FF__FF_FF_FF_FF
  ## also 0b0111...1111
  ## This biggest representable number in our limbs.
  ## i.e. The most significant bit is never set at the end of each function

# ############################################################
#
#                    BigInt primitives
#
# ############################################################

# The primitives all accept a control input that indicates
# if it is a placebo operation. It stills performs the
# same memory accesses to be side-channel attack resistant

# For efficiency we define templates and will create functions
# specialized for runtime and compile-time inputs

template maddImpl[bits](result: CTBool[Limb], a: var BigInt[bits], b: BigInt[bits], ctl: CTBool[Limb]) =
  ## Constant-time big integer in-place addition
  ## Returns if addition carried
  for i in a.limbs.len:
    let new_a = a.limbs[i] + b.limbs[i] + Limb(result)
    result = new_a.isMsbSet()
    a[i] = ctl.mux(new_a and highLimb, a)

func madd*[bits](a: var BigInt[bits], b: BigInt[bits], ctl: CTBool[Limb]): CTBool[Limb] =
  ## Constant-time big integer in-place addition
  ## Returns the "carry flag"
  result.maddImpl(a, b, ctl)

func madd*[bits](a: var BigInt[bits], b: static BigInt[bits], ctl: CTBool[Limb]): CTBool[Limb] =
  ## Constant-time big integer in-place addition
  ## Returns the "carry flag". Specialization for B being a compile-time constant (usually a modulus).
  result.maddImpl(a, b, ctl)

template msubImpl[bits](result: CTBool[Limb], a: var BigInt[bits], b: BigInt[bits], ctl: CTBool[Limb]) =
  ## Constant-time big integer in-place substraction
  ## Returns the "borrow flag"
  for i in a.limbs.len:
    let new_a = a.limbs[i] - b.limbs[i] - Limb(result)
    result = new_a.isMsbSet()
    a[i] = ctl.mux(new_a and highLimb, a)

func msub*[bits](a: var BigInt[bits], b: BigInt[bits], ctl: CTBool[Limb]): CTBool[Limb] =
  ## Constant-time big integer in-place addition
  ## Returns the "carry flag"
  result.msubImpl(a, b, ctl)

func msub*[bits](a: var BigInt[bits], b: static BigInt[bits], ctl: CTBool[Limb]): CTBool[Limb] =
  ## Constant-time big integer in-place addition
  ## Returns the "carry flag". Specialization for B being a compile-time constant (usually a modulus).
  result.msubImpl(a, b, ctl)
