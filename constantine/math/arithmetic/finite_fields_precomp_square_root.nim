# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  std/tables,
  ../../platforms/abstractions,
  ../constants/zoo_square_roots,
  ./bigints, ./finite_fields

# ############################################################
#
#            Only For Bandersnatch/Banderwagon for now
#
# ############################################################

# sqrtAlg_NegDlogInSmallDyadicSubgroup takes a (not necessarily primitive) root of unity x of order 2^sqrtParam_BlockSize.
# x has the form sqrtPrecomp_ReconstructionDyadicRoot^a and returns its negative dlog -a.
#
# The returned value is only meaningful modulo 1<<sqrtParam_BlockSize and is fully reduced, i.e. in [0, 1<<sqrtParam_BlockSize )
#
# NOTE: If x is not a root of unity as asserted, the behaviour is undefined.
func sqrtAlg_NegDlogInSmallDyadicSubgroup*(x: Fp): int =
  let key = cast[int](x.mres.limbs[0] and SecretWord 0xFFFF)
  if key in Fp.C.tonelliShanks(sqrtPrecomp_dlogLUT):
    return Fp.C.tonelliShanks(sqrtPrecomp_dlogLUT)[key]
  return 0
  
# sqrtAlg_GetPrecomputedRootOfUnity sets target to g^(multiplier << (order * sqrtParam_BlockSize)), where g is the fixed primitive 2^32th root of unity.
#
# We assume that order 0 <= order*sqrtParam_BlockSize <= 32 and that multiplier is in [0, 1 <<sqrtParam_BlockSize)
func sqrtAlg_GetPrecomputedRootOfUnity*(target: var Fp, multiplier: int, order: uint) =
  target = Fp.C.tonelliShanks(sqrtPrecomp_PrecomputedBlocks)[order][multiplier]


func sqrtAlg_ComputerRelevantPowers*(z: var Fp, squareRootCandidate: var Fp, rootOfUnity: var Fp) =
  ## sliding window-type algorithm with window-size 5
  ## Note that we precompute and use z^255 multiple times (even though it's not size 5)
  ## and some windows actually overlap
  var z2, z3, z7, z6, z9, z11, z13, z19, z21, z25, z27, z29, z31, z255 {.noInit.} : Fp
  var acc: Fp
  z2.square(z)
  z3.prod(z2, z)
  z6.prod(z3, z3)
  z7.prod(z6, z)
  z9.prod(z7, z2)
  z11.prod(z9, z2)
  z13.prod(z11, z2)
  z19.prod(z13, z6)
  z21.prod(z19, z2)
  z25.prod(z19, z6)
  z27.prod(z25, z2)
  z29.prod(z27, z2)
  z31.prod(z29, z2)
  acc.prod(z27, z29)
  acc.prod(acc, acc)
  acc.prod(acc, acc)
  z255.prod(acc, z31)
  acc.prod(acc, acc)
  acc.prod(acc, acc)
  acc.prod(acc, z31)
  square_repeated(acc, 6)
  acc.prod(acc, z27)
  square_repeated(acc, 6)
  acc.prod(acc, z19)
  square_repeated(acc, 5)
  acc.prod(acc, z21)
  square_repeated(acc, 7)
  acc.prod(acc, z25)
  square_repeated(acc, 6)
  acc.prod(acc, z19)
  square_repeated(acc, 5)
  acc.prod(acc, z7)
  square_repeated(acc, 5)
  acc.prod(acc, z11)
  square_repeated(acc, 5)
  acc.prod(acc, z29)
  square_repeated(acc, 5)
  acc.prod(acc, z9)
  square_repeated(acc, 7)
  acc.prod(acc, z3)
  square_repeated(acc, 7)
  acc.prod(acc, z25)
  square_repeated(acc, 5)
  acc.prod(acc, z25)
  square_repeated(acc, 5)
  acc.prod(acc, z27)
  square_repeated(acc, 8)
  acc.prod(acc, z)
  square_repeated(acc, 8)
  acc.prod(acc, z)
  square_repeated(acc, 6)
  acc.prod(acc, z13)
  square_repeated(acc, 7)
  acc.prod(acc, z7)
  square_repeated(acc, 3)
  acc.prod(acc, z3)
  square_repeated(acc, 13)
  acc.prod(acc, z21)
  square_repeated(acc, 5)
  acc.prod(acc, z9)
  square_repeated(acc, 5)
  acc.prod(acc, z27)
  square_repeated(acc, 5)
  acc.prod(acc, z27)
  square_repeated(acc, 5)
  acc.prod(acc, z9)
  square_repeated(acc, 10)
  acc.prod(acc, z)
  square_repeated(acc, 7)
  acc.prod(acc, z255)
  square_repeated(acc, 8)
  acc.prod(acc, z255)
  square_repeated(acc, 6)
  acc.prod(acc, z11)
  square_repeated(acc, 9)
  acc.prod(acc, z255)
  square_repeated(acc, 2)
  acc.prod(acc, z)
  square_repeated(acc, 7)
  acc.prod(acc, z255)
  square_repeated(acc, 8)
  acc.prod(acc, z255)
  square_repeated(acc, 8)
  acc.prod(acc, z255)
  square_repeated(acc, 8)
  acc.prod(acc, z255)
  # acc is now z^((BaseFieldMultiplicativeOddOrder - 1)/2)
  rootOfUnity.square(acc)
  rootOfUnity.prod(rootOfUnity ,z)
  squareRootCandidate.prod(acc, z)


func invSqrtEqDyadic*(z: var Fp): bool =
  ## The algorithm works by essentially computing the dlog of z and then halving it.
  ## negExponent is intended to hold the negative of the dlog of z.
  ## We determine this 32-bit value (usually) _sqrtBlockSize many bits at a time, starting with the least-significant bits.
  ##
  ## If _sqrtBlockSize does not divide 32, the *first* iteration will determine fewer bits.

  var negExponent: int
  var temp, temp2: Fp

  # set powers[i] to z^(1<< (i*blocksize))
  var powers: array[4, Fp]
  powers[0] = z
  for i in 1..<Fp.C.tonelliShanks(sqrtParam_Blocks):
    powers[i] = powers[i - 1]
    for j in 0..<Fp.C.tonelliShanks(sqrtParam_BlockSize):
      powers[i].square(powers[i])

  ## looking at the dlogs, powers[i] is essentially the wanted exponent, left-shifted by i*_sqrtBlockSize and taken mod 1<<32
  ## dlogHighDyadicRootNeg essentially (up to sign) reads off the _sqrtBlockSize many most significant bits. (returned as low-order bits)
  ## 
  ## first iteration may be slightly special if BlockSize does not divide 32
  negExponent = sqrtAlg_NegDlogInSmallDyadicSubgroup(powers[Fp.C.tonelliShanks(sqrtParam_Blocks) - 1])
  negExponent = negExponent shr Fp.C.tonelliShanks(sqrtParam_FirstBlockUnusedBits)

  # if the exponent we just got is odd, there is no square root, no point in determining the other bits
  if (negExponent and 1) == 1:
    return false

  for i in 1..<Fp.C.tonelliShanks(sqrtParam_Blocks):
    temp2 = powers[Fp.C.tonelliShanks(sqrtParam_Blocks) - 1 - i]
    for j in 0..<i:
      sqrtAlg_GetPrecomputedRootOfUnity(temp, int( (negExponent shr (j*Fp.C.tonelliShanks(sqrtParam_BlockSize))) and Fp.C.tonelliShanks(sqrtParam_BitMask) ), uint(j + Fp.C.tonelliShanks(sqrtParam_Blocks) - 1 - i))
      temp2.prod(temp2, temp)
    
    var newBits = sqrtAlg_NegDlogInSmallDyadicSubgroup(temp2)
    negExponent = negExponent or (newBits shl ((i*Fp.C.tonelliShanks(sqrtParam_BlockSize)) - Fp.C.tonelliShanks(sqrtParam_FirstBlockUnusedBits)))

  negExponent = negExponent shr 1
  z.setOne()

  for i in 0..<Fp.C.tonelliShanks(sqrtParam_Blocks):
    sqrtAlg_GetPrecomputedRootOfUnity(temp, int((negExponent shr (i*Fp.C.tonelliShanks(sqrtParam_BlockSize))) and Fp.C.tonelliShanks(sqrtParam_BitMask)), uint(i))
    z.prod(z, temp)

  return true

func sqrtPrecomp*(dst: var Fp, x: Fp): SecretBool {.inline.} =
  dst.setZero()
  if x.isZero().bool():
    return SecretBool(true)
  
  var xCopy: Fp = x
  var candidate, rootOfUnity: Fp
  sqrtAlg_ComputerRelevantPowers(xCopy, candidate, rootOfUnity)
  if not invSqrtEqDyadic(rootOfUnity):
    return SecretBool(false)

  dst.prod(candidate, rootOfUnity)
  return SecretBool(true)
