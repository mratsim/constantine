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

# BLS12-381 G1
# ----------------------------------------------------------------------------------------

const BLS12_381_cubicRootOfUnity_mod_p* =
  Fp[BLS12_381].fromHex"0x1a0111ea397fe699ec02408663d4de85aa0d857d89759ad4897d29650fb85f9b409427eb4f49fffd8bfd00000000aaac"

const Lattice_BLS12_381_G1* = (
  # (BigInt, isNeg)
  ((BigInt[128].fromHex"0xac45a4010001a40200000000ffffffff", false), # u² - 1
   (BigInt[1].fromHex"0x1", true)),                                  # -1
  ((BigInt[1].fromHex"0x1", false),                                  # 1
   (BigInt[128].fromHex"0xac45a4010001a4020000000100000000", false)) # u²
)

const Babai_BLS12_381_G1* = (
  # Vector for Babai rounding
  # (BigInt, isNeg)
  (BigInt[129].fromHex"0x17c6becf1e01faadd63f6e522f6cfee30", false),
  (BigInt[2].fromHex"0x2", false)
)

# BLS12-381 G2
# ----------------------------------------------------------------------------------------

const Lattice_BLS12_381_G2* = (
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

const Babai_BLS12_381_G2* = (
  # Vector for Babai rounding
  # Value, isNeg
  (BigInt[193].fromHex"0x1381204ca56cd56b533cfcc0d3e76ec2892078a5e8573b29c", false),
  (BigInt[129].fromHex"0x17c6becf1e01faadd63f6e522f6cfee2f", true),
  (BigInt[65].fromhex"0x1cfbe4f7bd0027db0", false),
  (BigInt[1].fromhex"0x0", false)
)
