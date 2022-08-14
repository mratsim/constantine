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

# BN254_Snarks G1
# ------------------------------------------------------------

const BN254_Snarks_cubicRootOfUnity_mod_p* =
  Fp[BN254_Snarks].fromHex"0x30644e72e131a0295e6dd9e7e0acccb0c28f069fbb966e3de4bd44e5607cfd48"

const BN254_Snarks_Lattice_G1* = (
  # (BigInt, isNeg)
  ((BigInt[127].fromHex"0x6f4d8248eeb859fc8211bbeb7d4f1128", false),
   (BigInt[64].fromHex"0x89d3256894d213e3", true)),
  ((BigInt[64].fromHex"0x89d3256894d213e3", true),
   (BigInt[127].fromHex"0x6f4d8248eeb859fd0be4e1541221250b", true))
)

const BN254_Snarks_Babai_G1* = (
  # (BigInt, isNeg)
  (BigInt[130].fromHex"0x24ccef014a773d2d25398fd0300ff6565", false),
  (BigInt[66].fromHex"0x2d91d232ec7e0b3d7", true)
)


# BN254_Snarks G2
# ------------------------------------------------------------

const BN254_Snarks_Lattice_G2* = (
  # (BigInt, isNeg)
  ((BigInt[64].fromHex"0x89d3256894d213e2", false),
   (BigInt[63].fromHex"0x44e992b44a6909f2", false),
   (BigInt[63].fromHex"0x44e992b44a6909f1", true),
   (BigInt[63].fromHex"0x44e992b44a6909f1", false)),
  ((BigInt[63].fromHex"0x44e992b44a6909f1", true),
   (BigInt[63].fromHex"0x44e992b44a6909f1", false),
   (BigInt[63].fromHex"0x44e992b44a6909f1", true),
   (BigInt[64].fromHex"0x89d3256894d213e3", true)),
  ((BigInt[63].fromHex"0x44e992b44a6909f2", false),
   (BigInt[63].fromHex"0x44e992b44a6909f1", false),
   (BigInt[63].fromHex"0x44e992b44a6909f1", false),
   (BigInt[64].fromHex"0x89d3256894d213e2", true)),
  ((BigInt[64].fromHex"0x89d3256894d213e3", false),
   (BigInt[63].fromHex"0x44e992b44a6909f1", true),
   (BigInt[63].fromHex"0x44e992b44a6909f2", true),
   (BigInt[63].fromHex"0x44e992b44a6909f1", true))
)

const BN254_Snarks_Babai_G2* = (
  # (BigInt, isNeg)
  (BigInt[192].fromHex"0x9e80318ab0d92b9308e5da66fc7184ae46f4bda995d51bb1", false),
  (BigInt[192].fromHex"0x9e80318ab0d92b9555b4ca7ba3e5577f2dff291532e42728", true),
  (BigInt[192].fromHex"0x9e80318ab0d92b9555b4ca7ba3e55782071c4c43fac4daff", false),
  (BigInt[192].fromHex"0x9e80318ab0d92b9555b4ca7ba3e5577dc170977dcef3cd3f", false)
)
