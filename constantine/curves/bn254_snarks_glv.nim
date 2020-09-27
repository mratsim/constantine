# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  ../config/[curves, type_bigint, type_fp],
  ../io/[io_bigints, io_fields]

# BN254 Snarks G1
# ----------------------------------------------------------------------------------------

const BN254_Snarks_cubicRootofUnity_mod_p* =
  Fp[BN254_Snarks].fromHex"0x30644e72e131a0295e6dd9e7e0acccb0c28f069fbb966e3de4bd44e5607cfd48"

# Chapter 6.3.1 - Guide to Pairing-based Cryptography
const BN254_Snarks_Lattice_G1* = (
  # Curve of order 254 -> mini scalars of size 127
  # u = 0x44E992B44A6909F1
  # (BigInt, isNeg)
  ((BigInt[64].fromHex"0x89d3256894d213e3", false),                   # 2u + 1
   (BigInt[127].fromHex"0x6f4d8248eeb859fd0be4e1541221250b", false)), # 6u² + 4u + 1
  ((BigInt[127].fromHex"0x6f4d8248eeb859fc8211bbeb7d4f1128", false),  # 6u² + 2u
   (BigInt[64].fromHex"0x89d3256894d213e3", true))                    # -2u - 1
)

const BN254_Snarks_Babai_G1* = (
  # Vector for Babai rounding
  # (BigInt, isNeg)
  (BigInt[66].fromHex"0x2d91d232ec7e0b3d7", false),                    # (2u + 1)       << 2^256 // r
  (BigInt[130].fromHex"0x24ccef014a773d2d25398fd0300ff6565", false)    # (6u² + 4u + 1) << 2^256 // r
)

# BN254 Snarks G2
# ----------------------------------------------------------------------------------------

const BN254_Snarks_Lattice_G2* = (
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

const BN254_Snarks_Babai_G2* = (
  # Vector for Babai rounding
  # Value, isNeg
  (BigInt[128].fromHex"0xc444fab18d269b9dd0cb46fd51906254", false),                  # 2x²+3x+1  << 2^256 // r
  (BigInt[193].fromHex"0x13d00631561b2572922df9f942d7d77c7001378f5ee78976d", false), # 3x³+8x²+x << 2^256 // r
  (BigInt[192].fromhex"0x9e80318ab0d92b94916fcfca16bebbe436510546a93478ab", false),  # 6x³+4x²+x << 2^256 // r
  (BigInt[128].fromhex"0xc444fab18d269b9af7ae23ce89afae7d", true)                    # -2x²-x    << 2^256 // r
)
