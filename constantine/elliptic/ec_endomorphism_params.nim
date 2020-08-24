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

# Parameters for GLV endomorphisms acceleration
# ----------------------------------------------------------------------------------------
# TODO: cleanup, those should be derived in the config folder
#       and stored in a constant

type
  MultiScalar*[M, LengthInBits: static int] = array[M, BigInt[LengthInBits]]
    ## Decomposition of a secret scalar in multiple scalars

# Chapter 6.3.1 - Guide to Pairing-based Cryptography
const Lattice_BN254_Snarks_G1: array[2, array[2, tuple[b: BigInt[127], isNeg: bool]]] = [
  # Curve of order 254 -> mini scalars of size 127
  # u = 0x44E992B44A6909F1
  [(BigInt[127].fromHex"0x89d3256894d213e3", false),                  # 2u + 1
   (BigInt[127].fromHex"0x6f4d8248eeb859fd0be4e1541221250b", false)], # 6u² + 4u + 1
  [(BigInt[127].fromHex"0x6f4d8248eeb859fc8211bbeb7d4f1128", false),  # 6u² + 2u
   (BigInt[127].fromHex"0x89d3256894d213e3", true)]                   # -2u - 1
]

const Babai_BN254_Snarks_G1 = [
  # Vector for Babai rounding
  BigInt[127].fromHex"0x89d3256894d213e3",                            # 2u + 1
  BigInt[127].fromHex"0x6f4d8248eeb859fd0be4e1541221250b"             # 6u² + 4u + 1
]

func decomposeScalar_BN254_Snarks_G1*[M, scalBits, L: static int](
       scalar: BigInt[scalBits],
       miniScalars: var MultiScalar[M, L]
     ) =
  ## Decompose a secret scalar into mini-scalar exploiting
  ## BN254_Snarks specificities.
  ##
  ## TODO: Generalize to all BN curves
  ##       - needs a Lattice type
  ##       - needs to better support negative bigints, (extra bit for sign?)

  static: doAssert L == (scalBits + M - 1) div M + 1
  # 𝛼0 = (0x2d91d232ec7e0b3d7 * s) >> 256
  # 𝛼1 = (0x24ccef014a773d2d25398fd0300ff6565 * s) >> 256
  const
    w = BN254_Snarks.getCurveOrderBitwidth().wordsRequired()
    alphaHats = (BigInt[66].fromHex"0x2d91d232ec7e0b3d7",
                 BigInt[130].fromHex"0x24ccef014a773d2d25398fd0300ff6565")

  var alphas{.noInit.}: array[M, BigInt[scalBits]] # TODO size 66+254 and 130+254

  staticFor i, 0, M:
    alphas[i].prod_high_words(alphaHats[i], scalar, w)

  # We have k0 = s - 𝛼0 b00 - 𝛼1 b10
  # and kj = 0 - 𝛼j b0j - 𝛼1 b1j
  var k: array[M, BigInt[scalBits]]
  k[0] = scalar
  for miniScalarIdx in 0 ..< M:
    for basisIdx in 0 ..< M:
      var alphaB {.noInit.}: BigInt[scalBits]
      alphaB.prod(alphas[basisIdx], Lattice_BN254_Snarks_G1[basisIdx][miniScalarIdx].b) # TODO small lattice size
      if Lattice_BN254_Snarks_G1[basisIdx][miniScalarIdx].isNeg:
        k[miniScalarIdx] += alphaB
      else:
        k[miniScalarIdx] -= alphaB

    miniScalars[miniScalarIdx].copyTruncatedFrom(k[miniScalarIdx])

const Lattice_BLS12_381_G1: array[2, array[2, tuple[b: BigInt[128], isNeg: bool]]] = [
  # Curve of order 254 -> mini scalars of size 127
  # u = 0x44E992B44A6909F1
  [(BigInt[128].fromHex"0xac45a4010001a40200000000ffffffff", false),  # u² - 1
   (BigInt[128].fromHex"0x1", true)],                                 # -1
  [(BigInt[128].fromHex"0x1", false),                                 # 1
   (BigInt[128].fromHex"0xac45a4010001a4020000000100000000", false)]  # u²
]

const Babai_BLS12_381_G1 = [
  # Vector for Babai rounding
  BigInt[128].fromHex"0xac45a4010001a4020000000100000000",
  BigInt[128].fromHex"0x1"
]

func decomposeScalar_BLS12_381_G1*[M, scalBits, L: static int](
       scalar: BigInt[scalBits],
       miniScalars: var MultiScalar[M, L]
     ) =
  ## Decompose a secret scalar into mini-scalar exploiting
  ## BLS12_381 specificities.
  ##
  ## TODO: Generalize to all BLS curves
  ##       - needs a Lattice type
  ##       - needs to better support negative bigints, (extra bit for sign?)

  # Equal when no window, greater otherwise
  static: doAssert L >= (scalBits + M - 1) div M + 1

  # 𝛼0 = (0x2d91d232ec7e0b3d7 * s) >> 256
  # 𝛼1 = (0x24ccef014a773d2d25398fd0300ff6565 * s) >> 256
  const
    w = BLS12_381.getCurveOrderBitwidth().wordsRequired()
    alphaHats = (BigInt[129].fromHex"0x17c6becf1e01faadd63f6e522f6cfee30",
                 BigInt[2].fromHex"0x2")

  var alphas{.noInit.}: array[M, BigInt[scalBits]] # TODO size 256+255 and 132+255

  staticFor i, 0, M:
    alphas[i].prod_high_words(alphaHats[i], scalar, w)

  # We have k0 = s - 𝛼0 b00 - 𝛼1 b10
  # and kj = 0 - 𝛼j b0j - 𝛼1 b1j
  var k: array[M, BigInt[scalBits]]
  k[0] = scalar
  for miniScalarIdx in 0 ..< M:
    for basisIdx in 0 ..< M:
      var alphaB {.noInit.}: BigInt[scalBits]
      alphaB.prod(alphas[basisIdx], Lattice_BLS12_381_G1[basisIdx][miniScalarIdx].b) # TODO small lattice size
      if Lattice_BLS12_381_G1[basisIdx][miniScalarIdx].isNeg:
        k[miniScalarIdx] += alphaB
      else:
        k[miniScalarIdx] -= alphaB

    miniScalars[miniScalarIdx].copyTruncatedFrom(k[miniScalarIdx])
