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

# BW6_761 G1
# ------------------------------------------------------------

const BW6_761_cubicRootOfUnity_mod_p* =
  Fp[BW6_761].fromHex"0x531dc16c6ecd27aa846c61024e4cca6c1f31e53bd9603c2d17be416c5e4426ee4a737f73b6f952ab5e57926fa701848e0a235a0a398300c65759fc45183151f2f082d4dcb5e37cb6290012d96f8819c547ba8a4000002f962140000000002a"

const BW6_761_Lattice_G1* = (
  # (BigInt, isNeg)
  ((BigInt[188].fromHex"0xbf9b117dd04a4002e16ba885fffffffd3a7bfffffffffff", false),
   (BigInt[188].fromHex"0xbf9b117dd04a4002e16ba886000000058b0800000000001", true)),
  ((BigInt[188].fromHex"0xbf9b117dd04a4002e16ba886000000058b0800000000001", false),
   (BigInt[189].fromHex"0x17f3622fba0948005c2d7510c00000002c58400000000000", false))
)

const BW6_761_Babai_G1* = (
  # (BigInt, isNeg)
  (BigInt[196].fromHex"0xe4061751dd380c86085f6e7602b7a9d8c2289a5d86c78aa7a", false),
  (BigInt[195].fromHex"0x72030ba8ee9c0643042fb73b015bd4eeda5ba6bfab7176f0a", false)
)


# BW6_761 G2
# ------------------------------------------------------------

const BW6_761_Lattice_G2* = (
  # (BigInt, isNeg)
  ((BigInt[188].fromHex"0xbf9b117dd04a4002e16ba886000000058b0800000000001", true),
   (BigInt[188].fromHex"0xbf9b117dd04a4002e16ba885fffffffd3a7bfffffffffff", true)),
  ((BigInt[188].fromHex"0xbf9b117dd04a4002e16ba885fffffffd3a7bfffffffffff", false),
   (BigInt[189].fromHex"0x17f3622fba0948005c2d7510c00000002c58400000000000", true))
)

const BW6_761_Babai_G2* = (
  # (BigInt, isNeg)
  (BigInt[196].fromHex"0xe4061751dd380c86085f6e7602b7a9d8c2289a5d86c78aa7a", true),
  (BigInt[195].fromHex"0x72030ba8ee9c0643042fb73b015bd4e9e7ccf39ddb5613b6f", false)
)
