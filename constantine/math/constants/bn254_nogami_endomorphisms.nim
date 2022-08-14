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

# BN254_Nogami G1
# ------------------------------------------------------------

const BN254_Nogami_cubicRootOfUnity_mod_p* =
  Fp[BN254_Nogami].fromHex"0x25236482400000017080eb4000000006181800000000000cd98000000000000b"

const BN254_Nogami_Lattice_G1* = (
  # (BigInt, isNeg)
  ((BigInt[127].fromHex"0x61818000000000020400000000000003", true),
   (BigInt[64].fromHex"0x8100000000000001", false)),
  ((BigInt[64].fromHex"0x8100000000000001", false),
   (BigInt[127].fromHex"0x61818000000000028500000000000004", false))
)

const BN254_Nogami_Babai_G1* = (
  # (BigInt, isNeg)
  (BigInt[130].fromHex"0x2a01fab7e04a017bd3a22fc67c12a7c5c", true),
  (BigInt[66].fromHex"0x37937ca688a6b4904", false)
)


# BN254_Nogami G2
# ------------------------------------------------------------

const BN254_Nogami_Lattice_G2* = (
  # (BigInt, isNeg)
  ((BigInt[64].fromHex"0x8100000000000001", false),
   (BigInt[63].fromHex"0x4080000000000001", true),
   (BigInt[63].fromHex"0x4080000000000000", true),
   (BigInt[63].fromHex"0x4080000000000001", true)),
  ((BigInt[63].fromHex"0x4080000000000000", false),
   (BigInt[63].fromHex"0x4080000000000001", false),
   (BigInt[63].fromHex"0x4080000000000001", false),
   (BigInt[64].fromHex"0x8100000000000002", true)),
  ((BigInt[63].fromHex"0x4080000000000001", true),
   (BigInt[63].fromHex"0x4080000000000001", false),
   (BigInt[63].fromHex"0x4080000000000001", true),
   (BigInt[64].fromHex"0x8100000000000001", true)),
  ((BigInt[64].fromHex"0x8100000000000002", false),
   (BigInt[63].fromHex"0x4080000000000000", false),
   (BigInt[63].fromHex"0x4080000000000001", true),
   (BigInt[63].fromHex"0x4080000000000001", false))
)

const BN254_Nogami_Babai_G2* = (
  # (BigInt, isNeg)
  (BigInt[192].fromHex"0xa957fab5402a55fc0d305f177b0b3c3e78cd599c2aa84979", false),
  (BigInt[192].fromHex"0xa957fab5402a55fc0d305f177b0b3c43aea10938fa493703", false),
  (BigInt[192].fromHex"0xa957fab5402a55fc0d305f177b0b3c4035693ed06fddedfe", true),
  (BigInt[192].fromHex"0xa957fab5402a55fead500a957fab53fbb2f05603ebd2c5d5", false)
)
