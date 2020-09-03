# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  # Internal
  ../primitives,
  ../config/[common, curves, type_bigint],
  ../arithmetic,
  ../io/io_bigints,
  ../towers,
  ./ec_weierstrass_projective

# ############################################################
#
#      Endomorphism acceleration decomposition parameters
#               for Scalar Multiplication
#
# ############################################################
#
# TODO: cleanup, those should be derived in the config folder
#       and stored in a constant
#       or generated from sage into a config file read at compile-time

type
  MultiScalar*[M, LengthInBits: static int] = array[M, BigInt[LengthInBits]]
    ## Decomposition of a secret scalar in multiple scalars

# BN254 Snarks G1
# ----------------------------------------------------------------------------------------

# Chapter 6.3.1 - Guide to Pairing-based Cryptography
const Lattice_BN254_Snarks_G1 = (
  # Curve of order 254 -> mini scalars of size 127
  # u = 0x44E992B44A6909F1
  # (BigInt, isNeg)
  ((BigInt[64].fromHex"0x89d3256894d213e3", false),                   # 2u + 1
   (BigInt[127].fromHex"0x6f4d8248eeb859fd0be4e1541221250b", false)), # 6u² + 4u + 1
  ((BigInt[127].fromHex"0x6f4d8248eeb859fc8211bbeb7d4f1128", false),  # 6u² + 2u
   (BigInt[64].fromHex"0x89d3256894d213e3", true))                    # -2u - 1
)

const Babai_BN254_Snarks_G1 = (
  # Vector for Babai rounding
  # (BigInt, isNeg)
  (BigInt[66].fromHex"0x2d91d232ec7e0b3d7", false),                    # (2u + 1)       << 2^256 // r
  (BigInt[130].fromHex"0x24ccef014a773d2d25398fd0300ff6565", false)    # (6u² + 4u + 1) << 2^256 // r
)

func decomposeScalar_BN254_Snarks_G1*[M, scalBits, L: static int](
       scalar: BigInt[scalBits],
       miniScalars: var MultiScalar[M, L]
     ) =
  ## Decompose a secret scalar into mini-scalar exploiting
  ## BN254_Snarks specificities.

  # Equal when no window or no negative handling, greater otherwise
  static: doAssert L >= (scalBits + M - 1) div M + 1
  const
    w = BN254_Snarks.getCurveOrderBitwidth().wordsRequired()

  var alphas{.noInit.}: (
    BigInt[scalBits + Babai_BN254_Snarks_G1[0][0].bits],
    BigInt[scalBits + Babai_BN254_Snarks_G1[1][0].bits]
  )

  staticFor i, 0, M:
    alphas[i].prod_high_words(Babai_BN254_Snarks_G1[i][0], scalar, w)
    when Babai_BN254_Snarks_G1[i][1]:
      # prod_high_words works like shift right
      # When negative, we should add 1 to properly round toward -infinity
      alphas[i] += SecretWord(1)

  # We have k0 = s - 𝛼0 b00 - 𝛼1 b10 ... - 𝛼m bm0
  # and     kj = 0 - 𝛼j b0j - 𝛼1 b1j ... - 𝛼m bmj
  var k: array[M, BigInt[scalBits]]
  k[0] = scalar
  staticFor miniScalarIdx, 0, M:
    staticFor basisIdx, 0, M:
      var alphaB {.noInit.}: BigInt[scalBits]
      alphaB.prod(alphas[basisIdx], Lattice_BN254_Snarks_G1[basisIdx][miniScalarIdx][0])
      when Lattice_BN254_Snarks_G1[basisIdx][miniScalarIdx][1] xor Babai_BN254_Snarks_G1[basisIdx][1]:
        k[miniScalarIdx] += alphaB
      else:
        k[miniScalarIdx] -= alphaB

    miniScalars[miniScalarIdx].copyTruncatedFrom(k[miniScalarIdx])

# BLS12-381 G1
# ----------------------------------------------------------------------------------------

const Lattice_BLS12_381_G1 = (
  # (BigInt, isNeg)
  ((BigInt[128].fromHex"0xac45a4010001a40200000000ffffffff", false), # u² - 1
   (BigInt[1].fromHex"0x1", true)),                                  # -1
  ((BigInt[1].fromHex"0x1", false),                                  # 1
   (BigInt[128].fromHex"0xac45a4010001a4020000000100000000", false)) # u²
)

const Babai_BLS12_381_G1 = (
  # Vector for Babai rounding
  # (BigInt, isNeg)
  (BigInt[129].fromHex"0x17c6becf1e01faadd63f6e522f6cfee30", false),
  (BigInt[2].fromHex"0x2", false)
)

func decomposeScalar_BLS12_381_G1*[M, scalBits, L: static int](
       scalar: BigInt[scalBits],
       miniScalars: var MultiScalar[M, L]
     ) =
  ## Decompose a secret scalar into mini-scalar exploiting
  ## BLS12_381 specificities.

  # Equal when no window or no negative handling, greater otherwise
  static: doAssert L >= (scalBits + M - 1) div M + 1
  const
    w = BLS12_381.getCurveOrderBitwidth().wordsRequired()

  var alphas{.noInit.}: (
    BigInt[scalBits + Babai_BLS12_381_G1[0][0].bits],
    BigInt[scalBits + Babai_BLS12_381_G1[1][0].bits]
  )

  staticFor i, 0, M:
    alphas[i].prod_high_words(Babai_BLS12_381_G1[i][0], scalar, w)
    when Babai_BLS12_381_G1[i][1]:
      # prod_high_words works like shift right
      # When negative, we should add 1 to properly round toward -infinity
      alphas[i] += SecretWord(1)

  # We have k0 = s - 𝛼0 b00 - 𝛼1 b10
  # and kj = 0 - 𝛼j b0j - 𝛼1 b1j
  var k: array[M, BigInt[scalBits]]
  k[0] = scalar
  staticFor miniScalarIdx, 0, M:
    staticFor basisIdx, 0, M:
      var alphaB {.noInit.}: BigInt[scalBits]
      alphaB.prod(alphas[basisIdx], Lattice_BLS12_381_G1[basisIdx][miniScalarIdx][0])
      when Lattice_BLS12_381_G1[basisIdx][miniScalarIdx][1] xor Babai_BLS12_381_G1[basisIdx][1]:
        k[miniScalarIdx] += alphaB
      else:
        k[miniScalarIdx] -= alphaB

    miniScalars[miniScalarIdx].copyTruncatedFrom(k[miniScalarIdx])

# BN254 Snarks G2
# ----------------------------------------------------------------------------------------

const Lattice_BN254_Snarks_G2 = (
  # Curve of order 254 -> mini scalars of size 65
  # x = 0x44E992B44A6909F1
  # Value, isNeg
  ((BigInt[63].fromHex"0x44e992b44a6909f2", false),  # x+1
   (BigInt[63].fromHex"0x44e992b44a6909f1", false),  # x
   (BigInt[63].fromHex"0x44e992b44a6909f1", false),  # x
   (BigInt[64].fromHex"0x89d3256894d213e2", true)),  # -2x

  ((BigInt[64].fromHex"0x89d3256894d213e3", false),  # 2x+1
   (BigInt[63].fromHex"0x44e992b44a6909f1", true),   # -x
   (BigInt[63].fromHex"0x44e992b44a6909f2", true),   # -x-1
   (BigInt[63].fromHex"0x44e992b44a6909f1", true)),  # -x

  ((BigInt[64].fromHex"0x89d3256894d213e2", false),  # 2x
   (BigInt[64].fromHex"0x89d3256894d213e3", false),  # 2x+1
   (BigInt[64].fromHex"0x89d3256894d213e3", false),  # 2x+1
   (BigInt[64].fromHex"0x89d3256894d213e3", false)),  # 2x+1

  ((BigInt[63].fromHex"0x44e992b44a6909f0", false),  # x-1
   (BigInt[65].fromHex"0x113a64ad129a427c6", false), # 4x+2
   (BigInt[64].fromHex"0x89d3256894d213e1", true),   # -2x+1
   (BigInt[63].fromHex"0x44e992b44a6909f0", false)), # x-1
  )

const Babai_BN254_Snarks_G2 = (
  # Vector for Babai rounding
  # Value, isNeg
  (BigInt[128].fromHex"0xc444fab18d269b9dd0cb46fd51906254", false),                  # 2x²+3x+1  << 2^256 // r
  (BigInt[193].fromHex"0x13d00631561b2572922df9f942d7d77c7001378f5ee78976d", false), # 3x³+8x²+x << 2^256 // r
  (BigInt[192].fromhex"0x9e80318ab0d92b94916fcfca16bebbe436510546a93478ab", false),  # 6x³+4x²+x << 2^256 // r
  (BigInt[128].fromhex"0xc444fab18d269b9af7ae23ce89afae7d", true)                    # -2x²-x    << 2^256 // r
)

func decomposeScalar_BN254_Snarks_G2*[M, scalBits, L: static int](
       scalar: BigInt[scalBits],
       miniScalars: var MultiScalar[M, L]
     ) =
  ## Decompose a secret scalar into mini-scalar exploiting
  ## BN254_Snarks specificities.

  # Equal when no window or no negative handling, greater otherwise
  static: doAssert L >= (scalBits + M - 1) div M + 1
  const
    w = BN254_Snarks.getCurveOrderBitwidth().wordsRequired()

  var alphas{.noInit.}: (
    BigInt[scalBits + Babai_BN254_Snarks_G2[0][0].bits],
    BigInt[scalBits + Babai_BN254_Snarks_G2[1][0].bits],
    BigInt[scalBits + Babai_BN254_Snarks_G2[2][0].bits],
    BigInt[scalBits + Babai_BN254_Snarks_G2[3][0].bits],
  )

  staticFor i, 0, M:
    alphas[i].prod_high_words(Babai_BN254_Snarks_G2[i][0], scalar, w)
    when Babai_BN254_Snarks_G2[i][1]:
      # prod_high_words works like logical right shift
      # When negative, we should add 1 to properly round toward -infinity
      alphas[i] += SecretWord(1)

  # We have k0 = s - 𝛼0 b00 - 𝛼1 b10
  # and kj = 0 - 𝛼j b0j - 𝛼1 b1j
  var k: array[M, BigInt[scalBits]]
  k[0] = scalar
  staticFor miniScalarIdx, 0, M:
    staticFor basisIdx, 0, M:
      var alphaB {.noInit.}: BigInt[scalBits]
      alphaB.prod(alphas[basisIdx], Lattice_BN254_Snarks_G2[basisIdx][miniScalarIdx][0])
      when Lattice_BN254_Snarks_G2[basisIdx][miniScalarIdx][1] xor Babai_BN254_Snarks_G2[basisIdx][1]:
        k[miniScalarIdx] += alphaB
      else:
        k[miniScalarIdx] -= alphaB

    miniScalars[miniScalarIdx].copyTruncatedFrom(k[miniScalarIdx])

# BLS12-381 G2
# ----------------------------------------------------------------------------------------

const Lattice_BLS12_381_G2 = (
  # Curve of order 254 -> mini scalars of size 65
  # x = -0xd201000000010000
  # Value, isNeg
  ((BigInt[64].fromHex"0xd201000000010000", false), # -x
   (BigInt[1].fromHex"0x1", false),                 #  1
   (BigInt[1].fromHex"0x0", false),                 #  0
   (BigInt[1].fromHex"0x0", false)),                #  0

  ((BigInt[1].fromHex"0x0", false),                 #  0
   (BigInt[64].fromHex"0xd201000000010000", false), # -x
   (BigInt[1].fromHex"0x1", false),                 #  1
   (BigInt[1].fromHex"0x0", false)),                #  0

  ((BigInt[1].fromHex"0x0", false),                 #  0
   (BigInt[1].fromHex"0x0", false),                 #  0
   (BigInt[64].fromHex"0xd201000000010000", false), # -x
   (BigInt[1].fromHex"0x1", false)),                #  1

  ((BigInt[1].fromHex"0x1", false),                 #  1
   (BigInt[1].fromHex"0x0", false),                 #  0
   (BigInt[1].fromHex"0x1", true),                  # -1
   (BigInt[64].fromHex"0xd201000000010000", false)) # -x
)

const Babai_BLS12_381_G2 = (
  # Vector for Babai rounding
  # Value, isNeg
  (BigInt[193].fromHex"0x1381204ca56cd56b533cfcc0d3e76ec2892078a5e8573b29c", false),
  (BigInt[129].fromHex"0x17c6becf1e01faadd63f6e522f6cfee2f", true),
  (BigInt[65].fromhex"0x1cfbe4f7bd0027db0", false),
  (BigInt[1].fromhex"0x0", false)
)

func decomposeScalar_BLS12_381_G2*[M, scalBits, L: static int](
       scalar: BigInt[scalBits],
       miniScalars: var MultiScalar[M, L]
     ) =
  ## Decompose a secret scalar into mini-scalar exploiting
  ## BLS12_381 specificities.
  ##
  ## A scalar decomposition might lead to negative miniscalar.
  ## For proper handling it requires either:
  ## 1. Negating it and then negating the corresponding curve point P
  ## 2. Adding an extra bit to the recoding, which will do the right thing™
  ##
  ## For implementation solution 1 is faster:
  ##   - Double + Add is about 5000~8000 cycles on 6 64-bits limbs (BLS12-381)
  ##   - Conditional negate is about 10 cycles per Fp, on G2 projective we have 3 (coords) * 2 (Fp2) * 10 (cycles) ~= 60 cycles
  ##     We need to test the mini scalar, which is 65 bits so 2 Fp so about 2 cycles
  ##     and negate it as well.
  ##
  ## However solution 1 seems to cause issues (TODO)
  ## with some of the BLS12-381 test cases (6 and 9)
  ## - 0x5668a2332db27199dcfb7cbdfca6317c2ff128db26d7df68483e0a095ec8e88f
  ## - 0x644dc62869683f0c93f38eaef2ba6912569dc91ec2806e46b4a3dd6a4421dad1

  # Equal when no window or no negative handling, greater otherwise
  static: doAssert L >= (scalBits + M - 1) div M + 1
  const
    w = BLS12_381.getCurveOrderBitwidth().wordsRequired()

  var alphas{.noInit.}: (
    BigInt[scalBits + Babai_BLS12_381_G2[0][0].bits],
    BigInt[scalBits + Babai_BLS12_381_G2[1][0].bits],
    BigInt[scalBits + Babai_BLS12_381_G2[2][0].bits],
    BigInt[scalBits + Babai_BLS12_381_G2[3][0].bits],
  )

  staticFor i, 0, M:
    alphas[i].prod_high_words(Babai_BLS12_381_G2[i][0], scalar, w)
    when Babai_BLS12_381_G2[i][1]:
      # prod_high_words works like logical right shift
      # When negative, we should add 1 to properly round toward -infinity
      alphas[i] += SecretWord(1)

  # We have k0 = s - 𝛼0 b00 - 𝛼1 b10
  # and kj = 0 - 𝛼j b0j - 𝛼1 b1j
  var k: array[M, BigInt[scalBits]]
  k[0] = scalar
  staticFor miniScalarIdx, 0, M:
    staticFor basisIdx, 0, M:
      var alphaB {.noInit.}: BigInt[scalBits]
      alphaB.prod(alphas[basisIdx], Lattice_BLS12_381_G2[basisIdx][miniScalarIdx][0])
      when Lattice_BLS12_381_G2[basisIdx][miniScalarIdx][1] xor Babai_BLS12_381_G2[basisIdx][1]:
        k[miniScalarIdx] += alphaB
      else:
        k[miniScalarIdx] -= alphaB

    miniScalars[miniScalarIdx].copyTruncatedFrom(k[miniScalarIdx])
