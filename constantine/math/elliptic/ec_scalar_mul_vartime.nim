# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  # Internals
  ./ec_endomorphism_accel,
  ../arithmetic,
  ../extension_fields,
  ../ec_shortweierstrass,
  ../io/io_bigints,
  ../constants/zoo_endomorphisms,
  ../../platforms/abstractions,
  ../../math_arbitrary_precision/arithmetic/limbs_views

{.push raises: [].} # No exceptions allowed in core cryptographic operations
{.push checks: off.} # No defects due to array bound checking or signed integer overflow allowed

# Bit operations
# ------------------------------------------------------------------------------

iterator unpackBE(scalarByte: byte): bool =
  for i in countdown(7, 0):
    yield bool((scalarByte shr i) and 1)

# Variable-time scalar multiplication
# ------------------------------------------------------------------------------

func scalarMul_doubleAdd_vartime*[EC](P: var EC, scalar: BigInt) {.tags:[VarTime].} =
  ## **Variable-time** Elliptic Curve Scalar Multiplication
  ##
  ##   P <- [k] P
  ##
  ## This uses the double-and-add algorithm
  ## This MUST NOT be used with secret data.
  ##
  ## This is highly VULNERABLE to timing attacks and power analysis attacks.
  var scalarCanonical: array[scalar.bits.ceilDiv_vartime(8), byte]
  scalarCanonical.marshal(scalar, bigEndian)

  var Paff {.noinit.}: affine(EC)
  Paff.affine(P)

  P.setInf()
  var isInf = true

  for scalarByte in scalarCanonical:
    for bit in unpackBE(scalarByte):
      if not isInf:
        P.double()
      if bit:
        if isInf:
          P.fromAffine(Paff)
        else:
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
  for bit in recoding_l2r_signed_vartime(scalar):
    P.double()
    if bit == 1:
      P += Paff
    elif bit == -1:
      P -= Paff

func scalarMul_minHammingWeight_windowed_vartime*[EC](P: var EC, scalar: BigInt, window: static int) {.tags:[VarTime, Alloca].} =
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
  let nafLen = naf.recode_r2l_signed_window_vartime(scalar, window)

  var P2{.noInit.}: EC
  P2.double(P)

  var tabEC {.noinit.}: array[precompSize, EC]
  tabEC[0] = P
  for i in 1 ..< tabEC.len:
    tabEC[i].sum(tabEC[i-1], P2)

  var tab {.noinit.}: array[precompSize, affine(EC)]
  tab.batchAffine(tabEC)

  # init
  if naf[nafLen-1] > 0:
    P.fromAffine(tab[naf[nafLen-1] shr 1])
  elif naf[nafLen-1] < 0:
    P.fromAffine(tab[-naf[nafLen-1] shr 1])
    P.neg()
  else:
    P.setInf()

  # steady state
  for i in 1 ..< nafLen:
    P.double()
    let digit = naf[nafLen-1-i]
    if digit > 0:
      P += tab[digit shr 1]
    elif digit < 0:
      P -= tab[-digit shr 1]

func scalarMul_vartime*[scalBits; EC](
       P: var EC,
       scalar: BigInt[scalBits]
     ) {.inline.} =
  ## Elliptic Curve Scalar Multiplication
  ##
  ##   P <- [k] P
  ##
  ## This select the best algorithm depending on heuristics
  ## and the scalar being multiplied.
  ## The scalar MUST NOT be a secret as this does not use side-channel countermeasures
  ##
  ## This may use endomorphism acceleration.
  ## As endomorphism acceleration requires:
  ## - Cofactor to be cleared
  ## - 0 <= scalar < curve order
  ## Those conditions will be assumed.

  when P.F is Fp:
    const M = 2
  elif P.F is Fp2:
    const M = 4
  else:
    {.error: "Unconfigured".}

  const L = scalBits.ceilDiv_vartime(M) + 1

  let usedBits = scalar.limbs.getBits_vartime()

  when scalBits == EC.F.C.getCurveOrderBitwidth and
       EC.F.C.hasEndomorphismAcceleration():
    if usedBits >= L:
      # The constant-time implementation is extremely efficient
      when EC.F is Fp:
        P.scalarMulGLV_m2w2(scalar)
      elif EC.F is Fp2:
        P.scalarMulEndo(scalar)
      else: # Curves defined on Fp^m with m > 2
        {.error: "Unreachable".}
      return

  if 64 < usedBits:
    # With a window of 5, we precompute 2^3 = 8 points
    P.scalarMul_minHammingWeight_windowed_vartime(scalar, window = 5)
  elif 8 <= usedBits and usedBits <= 64:
    # With a window of 3, we precompute 2^1 = 2 points
    P.scalarMul_minHammingWeight_windowed_vartime(scalar, window = 3)
  elif usedBits == 1:
    discard
  elif usedBits == 0:
    P.setInf()
  else:
    P.scalarMul_doubleAdd_vartime(scalar)