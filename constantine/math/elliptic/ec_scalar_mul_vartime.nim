# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  # Internals
  ../arithmetic,
  ../ec_shortweierstrass,
  ../io/io_bigints,
  ../../platforms/abstractions

{.push raises: [].} # No exceptions allowed in core cryptographic operations
{.push checks: off.} # No defects due to array bound checking or signed integer overflow allowed

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

func scalarMul_doubleAdd_vartime*[EC](P: var EC, scalar: BigInt) {.tags:[VarTime].} =
  ## **Variable-time** Elliptic Curve Scalar Multiplication
  ##
  ##   P <- [k] P
  ##
  ## This uses the double-and-add algorithm
  ## This MUST NOT be used with secret data.
  ##
  ## This is highly VULNERABLE to timing attacks and power analysis attacks.
  var scalarCanonical: array[(scalar.bits+7) div 8, byte]
  scalarCanonical.marshal(scalar, bigEndian)

  var Paff {.noinit.}: affine(EC)
  Paff.affine(P)

  P.setInf()
  for scalarByte in scalarCanonical:
    for bit in unpack(scalarByte):
      P.double()
      if bit:
        P += Paff

func scalarMul_minHammingWeight_vartime*[EC](P: var EC, scalar: BigInt) {.tags:[VarTime].}  =
  ## **Variable-time** Elliptic Curve Scalar Multiplication
  ##
  ##   P <- [k] P
  ##
  ## This uses an online recoding with minimum Hamming Weight
  ## (which is not NAF, NAF is least-significant bit to most)
  ## This MUST NOT be used with secret data.
  ##
  ## This is highly VULNERABLE to timing attacks and power analysis attacks
  var Paff {.noinit.}: affine(EC)
  Paff.affine(P)

  P.setInf()
  for bit in recoding_l2r_vartime(scalar):
    P.double()
    if bit == 1:
      P += Paff
    elif bit == -1:
      P -= Paff

func scalarMul_minHammingWeight_windowed_vartime*[EC](P: var EC, scalar: BigInt, window: static int) {.tags:[VarTime].} =
  ## **Variable-time** Elliptic Curve Scalar Multiplication
  ##
  ##   P <- [k] P
  ##
  ## This uses windowed-NAF (wNAF)
  ## This MUST NOT be used with secret data.
  ##
  ## This is highly VULNERABLE to timing attacks and power analysis attacks

  # Signed digits divides precomputation table size by 2
  # Odd-only divides precomputation table size by another 2
  const precompSize = 1 shl (window - 2)

  when window <= 8:
    type I = int8
  elif window <= 16:
    type I = int16
  elif window <= 32:
    type I = int32
  else:
    type I = int64

  var naf {.noInit.}: array[BigInt.bits+1, I]
  naf.recodeWindowed_r2l_vartime(scalar, window)

  var P2{.noInit.}: EC
  P2.double(P)

  var tabEC {.noinit.}: array[precompSize, EC]
  tabEC[0] = P
  for i in 1 ..< tabEC.len:
    tabEC[i].sum(tabEC[i-1], P2)

  var tab {.noinit.}: array[precompSize, affine(EC)]
  tab.batchAffine(tabEC)

  # init
  if naf[naf.len-1] > 0:
    P.fromAffine(tab[naf[naf.len-1] shr 1])
  elif naf[naf.len-1] < 0:
    P.fromAffine(tab[-naf[naf.len-1] shr 1])
    P.neg()
  else:
    P.setInf()

  # steady state
  for i in 1 ..< naf.len:
    P.double()
    let digit = naf[naf.len-1-i]
    if digit > 0:
      P += tab[digit shr 1]
    elif digit < 0:
      P -= tab[-digit shr 1]
