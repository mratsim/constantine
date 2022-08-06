# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  ../config/curves,
  ../io/[io_bigints, io_fields]

{.used.}

# BLS12_377 G1
# ------------------------------------------------------------

const BLS12_377_cubicRootOfUnity_mod_p* =
  Fp[BLS12_377].fromHex"0x1ae3a4617c510eabc8756ba8f8c524eb8882a75cc9bc8e359064ee822fb5bffd1e945779fffffffffffffffffffffff"

const BLS12_377_Lattice_G1* = (
  # (BigInt, isNeg)
  ((BigInt[127].fromHex"0x452217cc900000010a11800000000001", false),
   (BigInt[1].fromHex"0x1", false)),
  ((BigInt[1].fromHex"0x1", false),
   (BigInt[127].fromHex"0x452217cc900000010a11800000000000", true))
)

const BLS12_377_Babai_G1* = (
  # (BigInt, isNeg)
  (BigInt[130].fromHex"0x3b3f7aa969fd371607f72ed32af90181e", false),
  (BigInt[4].fromHex"0xd", false)
)


# BLS12_377 G2
# ------------------------------------------------------------

const BLS12_377_Lattice_G2* = (
  # (BigInt, isNeg)
  ((BigInt[64].fromHex"0x8508c00000000001", true),
   (BigInt[1].fromHex"0x1", false),
   (BigInt[1].fromHex"0x0", false),
   (BigInt[1].fromHex"0x0", false)),
  ((BigInt[1].fromHex"0x0", false),
   (BigInt[64].fromHex"0x8508c00000000001", true),
   (BigInt[1].fromHex"0x1", false),
   (BigInt[1].fromHex"0x0", false)),
  ((BigInt[1].fromHex"0x0", false),
   (BigInt[1].fromHex"0x0", false),
   (BigInt[64].fromHex"0x8508c00000000001", true),
   (BigInt[1].fromHex"0x1", false)),
  ((BigInt[1].fromHex"0x1", false),
   (BigInt[1].fromHex"0x0", false),
   (BigInt[1].fromHex"0x1", true),
   (BigInt[64].fromHex"0x8508c00000000001", false))
)

const BLS12_377_Babai_G2* = (
  # (BigInt, isNeg)
  (BigInt[193].fromHex"0x1eca0125755aed064f63abaff9084ce152979759b442f60d0", true),
  (BigInt[130].fromHex"0x3b3f7aa969fd371607f72ed32af90181e", true),
  (BigInt[67].fromHex"0x72030ba8ee9c06422", true),
  (BigInt[4].fromHex"0xd", false)
)
