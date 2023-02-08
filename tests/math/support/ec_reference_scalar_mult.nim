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

func unsafe_ECmul_signed_windowed*[EC](
       P: var EC,
       scalar: BigInt, window: static int) =
  ## **Unsafe** Elliptic Curve Scalar Multiplication
  ##
  ##   P <- [k] P
  ##
  ## This uses windowed-NAF (wNAF)

  # Signed digits divides precomputation table size by 2
  # Odd-only divides precomputation table size by another 2
  const precompSize = 1 shl (window - 2)

  var naf {.noInit.}: array[BigInt.bits+1, int8]
  naf.recodeWindowed_r2l_vartime(scalar, window)

  var P2{.noInit.}: EC
  P2.double(P)

  var tab {.noinit.}: array[precompSize, EC]
  tab[0] = P
  for i in 1 ..< tab.len:
    tab[i].sum(tab[i-1], P2)

  # init
  if naf[naf.len-1] > 0:
    P = tab[(naf[naf.len-1] - 1) shr 1]
  elif naf[naf.len-1] < 0:
    P.neg(tab[(-naf[naf.len-1] - 1) shr 1])
  else:
    P.setInf()

  # steady state
  for i in 1 ..< naf.len:
    P.double()
    let digit = naf[naf.len-1-i]
    if digit > 0:
      P += tab[(digit - 1) shr 1]
    elif digit < 0:
      P -= tab[(-digit - 1) shr 1]
