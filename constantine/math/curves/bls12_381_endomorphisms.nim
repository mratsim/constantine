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

# BLS12_381 G1
# ------------------------------------------------------------

const BLS12_381_cubicRootOfUnity_mod_p* =
  Fp[BLS12_381].fromHex"0x5f19672fdf76ce51ba69c6076a0f77eaddb3a93be6f89688de17d813620a00022e01fffffffefffe"

const BLS12_381_Lattice_G1* = (
  # (BigInt, isNeg)
  ((BigInt[128].fromHex"0xac45a4010001a4020000000100000000", false),
   (BigInt[1].fromHex"0x1", false)),
  ((BigInt[1].fromHex"0x1", false),
   (BigInt[128].fromHex"0xac45a4010001a40200000000ffffffff", true))
)

const BLS12_381_Babai_G1* = (
  # (BigInt, isNeg)
  (BigInt[129].fromHex"0x17c6becf1e01faadd63f6e522f6cfee2e", false),
  (BigInt[2].fromHex"0x2", false)
)


# BLS12_381 G2
# ------------------------------------------------------------

const BLS12_381_Lattice_G2* = (
  # (BigInt, isNeg)
  ((BigInt[64].fromHex"0xd201000000010000", false),
   (BigInt[1].fromHex"0x1", false),
   (BigInt[1].fromHex"0x0", false),
   (BigInt[1].fromHex"0x0", false)),
  ((BigInt[1].fromHex"0x0", false),
   (BigInt[64].fromHex"0xd201000000010000", false),
   (BigInt[1].fromHex"0x1", false),
   (BigInt[1].fromHex"0x0", false)),
  ((BigInt[1].fromHex"0x0", false),
   (BigInt[1].fromHex"0x0", false),
   (BigInt[64].fromHex"0xd201000000010000", false),
   (BigInt[1].fromHex"0x1", false)),
  ((BigInt[1].fromHex"0x1", false),
   (BigInt[1].fromHex"0x0", false),
   (BigInt[1].fromHex"0x1", true),
   (BigInt[64].fromHex"0xd201000000010000", true))
)

const BLS12_381_Babai_G2* = (
  # (BigInt, isNeg)
  (BigInt[193].fromHex"0x1381204ca56cd56b533cfcc0d3e76ec2892078a5e8573b29c", false),
  (BigInt[129].fromHex"0x17c6becf1e01faadd63f6e522f6cfee2e", true),
  (BigInt[65].fromHex"0x1cfbe4f7bd0027db2", false),
  (BigInt[2].fromHex"0x2", false)
)
