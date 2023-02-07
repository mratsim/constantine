# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  # Internals
  ../../../constantine/math/arithmetic,
  ../../../constantine/math/io/io_bigints

# Support files for testing Elliptic Curve arithmetic
# ------------------------------------------------------------------------------

iterator unpack(scalarByte: byte): bool =
  yield bool((scalarByte and 0b10000000) shr 7)
  yield bool((scalarByte and 0b01000000) shr 6)
  yield bool((scalarByte and 0b00100000) shr 5)
  yield bool((scalarByte and 0b00010000) shr 4)
  yield bool((scalarByte and 0b00001000) shr 3)
  yield bool((scalarByte and 0b00000100) shr 2)
  yield bool((scalarByte and 0b00000010) shr 1)
  yield bool( scalarByte and 0b00000001)

func unsafe_ECmul_double_add*[EC](
       P: var EC,
       scalar: BigInt,
     ) =
  ## **Unsafe** Elliptic Curve Scalar Multiplication
  ##
  ##   P <- [k] P
  ##
  ## This uses the double-and-add algorithm to verify the constant-time production implementation
  ## This is UNSAFE to use in production and only intended for testing purposes.
  ##
  ## This is highly VULNERABLE to timing attacks and power analysis attacks
  var scalarCanonical: array[(scalar.bits+7) div 8, byte]
  scalarCanonical.marshal(scalar, bigEndian)

  var t0: typeof(P)
  t0.setInf()
  for scalarByte in scalarCanonical:
    for bit in unpack(scalarByte):
      t0.double()
      if bit:
        t0 += P
  P = t0

func unsafe_ECmul_minHammingWeight*[EC](
       P: var EC,
       scalar: BigInt) =
  ## **Unsafe** Elliptic Curve Scalar Multiplication
  ##
  ##   P <- [k] P
  ##
  ## This uses an online recoding with minimum Hamming Weight
  ## (which is not NAF, NAF is least-significant bit to most)
  ## This is UNSAFE to use in production and only intended for testing purposes.
  ##
  ## This is highly VULNERABLE to timing attacks and power analysis attacks
  var t0{.noInit.}: typeof(P)
  t0.setInf()
  for bit in recoding_l2r_vartime(scalar):
    t0.double()
    if bit == 1:
      t0 += P
    elif bit == -1:
      t0 -= P
  P = t0