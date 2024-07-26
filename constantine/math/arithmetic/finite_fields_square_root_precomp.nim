# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

# The following code are based on the original implementation by @GottfriedHerold for Bandersnatch
# https://github.com/GottfriedHerold/Bandersnatch/blob/f665f90b64892b9c4c89cff3219e70456bb431e5/bandersnatch/fieldElements/field_element_square_root.go

import
  std/tables,
  constantine/platforms/abstractions,
  constantine/named/zoo_square_roots,
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
func sqrtAlg_NegDlogInSmallDyadicSubgroup_vartime(x: Fp): int {.tags:[VarTime], raises: [].} =
  let key = cast[int](x.mres.limbs[0] and SecretWord 0xFFFF)
  return Fp.Name.sqrtDlog(dlogLUT).getOrDefault(key, 0)

# sqrtAlg_GetPrecomputedRootOfUnity sets target to g^(multiplier << (order * sqrtParam_BlockSize)), where g is the fixed primitive 2^32th root of unity.
#
# We assume that order 0 <= order*sqrtParam_BlockSize <= 32 and that multiplier is in [0, 1 <<sqrtParam_BlockSize)
func sqrtAlg_GetPrecomputedRootOfUnity(target: var Fp, multiplier: int, order: uint) =
  target = Fp.Name.sqrtDlog(PrecomputedBlocks)[order][multiplier]

func invSqrtEqDyadic_vartime*(a: var Fp) =
  ## The algorithm works by essentially computing the dlog of a and then halving it.
  ## negExponent is intended to hold the negative of the dlog of a.
  ## We determine this 32-bit value (usually) _sqrtBlockSize many bits at a time, starting with the least-significant bits.
  ##
  ## If _sqrtBlockSize does not divide 32, the *first* iteration will determine fewer bits.

  var negExponent: int
  var temp, temp2: Fp

  # set powers[i] to a^(1<< (i*blocksize))
  var powers: array[4, Fp]
  powers[0] = a
  for i in 1 ..< Fp.Name.sqrtDlog(Blocks):
    powers[i] = powers[i - 1]
    for j in 0 ..< Fp.Name.sqrtDlog(BlockSize):
      powers[i].square(powers[i])

  ## looking at the dlogs, powers[i] is essentially the wanted exponent, left-shifted by i*_sqrtBlockSize and taken mod 1<<32
  ## dlogHighDyadicRootNeg essentially (up to sign) reads off the _sqrtBlockSize many most significant bits. (returned as low-order bits)
  ##
  ## first iteration may be slightly special if BlockSize does not divide 32
  negExponent = sqrtAlg_NegDlogInSmallDyadicSubgroup_vartime(powers[Fp.Name.sqrtDlog(Blocks) - 1])
  negExponent = negExponent shr Fp.Name.sqrtDlog(FirstBlockUnusedBits)

  # if the exponent we just got is odd, there is no square root, no point in determining the other bits
  # if (negExponent and 1) == 1:
  #   return false

  # result = SecretBool((negExponent and 1) != 1)

  for i in 1 ..< Fp.Name.sqrtDlog(Blocks):
    temp2 = powers[Fp.Name.sqrtDlog(Blocks) - 1 - i]
    for j in 0 ..< i:
      sqrtAlg_GetPrecomputedRootOfUnity(temp, int( (negExponent shr (j*Fp.Name.sqrtDlog(BlockSize))) and Fp.Name.sqrtDlog(BitMask) ), uint(j + Fp.Name.sqrtDlog(Blocks) - 1 - i))
      temp2.prod(temp2, temp)

    var newBits = sqrtAlg_NegDlogInSmallDyadicSubgroup_vartime(temp2)
    negExponent = negExponent or (newBits shl ((i*Fp.Name.sqrtDlog(BlockSize)) - Fp.Name.sqrtDlog(FirstBlockUnusedBits)))

  negExponent = negExponent shr 1
  a.setOne()

  for i in 0 ..< Fp.Name.sqrtDlog(Blocks):
    sqrtAlg_GetPrecomputedRootOfUnity(temp, int((negExponent shr (i*Fp.Name.sqrtDlog(BlockSize))) and Fp.Name.sqrtDlog(BitMask)), uint(i))
    a.prod(a, temp)

func inv_sqrt_precomp_vartime*(r: var Fp, a: Fp) =
  var candidate, powLargestPowerOfTwo {.noInit.}: Fp
  # Compute
  #  candidate = a^((q-1-2^e)/(2*2^e))
  # with
  #  s and e, precomputed values
  #  such as q == s * 2^e + 1 the field modulus
  #  e is the 2-adicity of the field (the 2^e is the largest power of two that divides q-1)
  candidate.precompute_tonelli_shanks_addchain(a)
  powLargestPowerOfTwo.square(candidate)
  powLargestPowerOfTwo *= a
  invSqrtEqDyadic_vartime(powLargestPowerOfTwo)
  r.prod(candidate, powLargestPowerOfTwo)
