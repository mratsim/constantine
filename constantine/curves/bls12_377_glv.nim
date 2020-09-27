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

# BLS12-377 G1
# ----------------------------------------------------------------------------------------

const BLS12_377_cubicRootofUnity_mod_p* =
  Fp[BLS12_377].fromHex"0x9b3af05dd14f6ec619aaf7d34594aabc5ed1347970dec00452217cc900000008508c00000000001"

const BLS12_377_Lattice_G1* = (
  # (BigInt, isNeg)
  ((BigInt[127].fromHex"0x452217cc900000010a11800000000000", false), # u² - 1
   (BigInt[1].fromHex"0x1", true)),                                  # -1
  ((BigInt[1].fromHex"0x1", false),                                  # 1
   (BigInt[127].fromHex"0x452217cc900000010a11800000000001", false)) # u²
)

const BLS12_377_Babai_G1* = (
  # Vector for Babai rounding
  # (BigInt, isNeg)
  (BigInt[130].fromHex"0x3b3f7aa969fd371607f72ed32af90182c", false),
  (BigInt[4].fromHex"0xd", false)
)

# BLS12-377 G2
# ----------------------------------------------------------------------------------------

const BLS12_377_Lattice_G2* = (
  # Curve of order 254 -> mini scalars of size 65
  # x = -0xd201000000010000
  # Value, isNeg
  ((BigInt[64].fromHex"0x8508c00000000001", true),  # -x
   (BigInt[1].fromHex"0x1", false),                 #  1
   (BigInt[1].fromHex"0x0", false),                 #  0
   (BigInt[1].fromHex"0x0", false)),                #  0

  ((BigInt[1].fromHex"0x0", false),                 #  0
   (BigInt[64].fromHex"0x8508c00000000001", true),  # -x
   (BigInt[1].fromHex"0x1", false),                 #  1
   (BigInt[1].fromHex"0x0", false)),                #  0

  ((BigInt[1].fromHex"0x0", false),                 #  0
   (BigInt[1].fromHex"0x0", false),                 #  0
   (BigInt[64].fromHex"0x8508c00000000001", true),  # -x
   (BigInt[1].fromHex"0x1", false)),                #  1

  ((BigInt[1].fromHex"0x1", false),                 #  1
   (BigInt[1].fromHex"0x0", false),                 #  0
   (BigInt[1].fromHex"0x1", true),                  # -1
   (BigInt[64].fromHex"0x8508c00000000001", true))  # -x
)

const BLS12_377_Babai_G2* = (
  # Vector for Babai rounding
  # Value, isNeg
  (BigInt[193].fromHex"0x1eca0125755aed064f63abaff9084ce152979759b442f60d1", true),
  (BigInt[130].fromHex"0x3b3f7aa969fd371607f72ed32af90181f", true),
  (BigInt[67].fromhex"0x72030ba8ee9c06415", true),
  (BigInt[1].fromhex"0x0", false)
)
