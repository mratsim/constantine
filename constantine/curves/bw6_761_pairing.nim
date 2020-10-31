# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  ../config/[curves, type_bigint],
  ../io/io_bigints

# Slow generic implementation
# ------------------------------------------------------------

# 1st part: fu,Q(P)
const BW6_761_pairing_ate_param_1* = block:
  # BW6 Miller loop first part is parametrized by u
  # +1 to bitlength so that we can mul by 3 for NAF encoding
  BigInt[64+1].fromHex"0x8508c00000000001"

const BW6_761_pairing_ate_param_isNeg* = false


# 2nd part: f(u²-u-1),Q(P)
const BW6_761_pairing_ate_param_2* = block:
  # BW6 Miller loop second part is parametrized by u²-u-1
  # +1 to bitlength so that we can mul by 3 for NAF encoding
  BigInt[127+1].fromHex"0x452217cc900000008508bfffffffffff"

const BW6_761_pairing_ate_param_2_isNeg* = false


const BW6_761_pairing_finalexponent* = block:
  # (p^6 - 1) / r
  BigInt[4185].fromHex"0x147fe546f00083377e9fbf6a033031c7b3bcd091704b16560d93a4388a54ed259b6dde22664d830a4a2bf0cead97e54990018ad199a375b8669e863e1e623778150e7d6485ea546b25966013c2a43b6cd6d44630e70730955a7583ce9c5dc0b6be101610c672471296249743f64217723fb8f9c3dc4223fd7634e5627884e9f63b1994f35769e747c3c195cfff160602031810ff73d4ec6f22f65ba73fe0cfd7f8b981c7d9f6e01f062bf0158de06a4aede6f53a6b077333b1aa94a06a90215ca0d86c9fa849739e3230f1596de77c7b2ee2d771c5e5998c42d3e90ea4458daf3ad76841e9d27ab1e4c5119b34223e74a14ddb89f929f5b28353c0558af093f274393b9c632878699ba64293e7d0075cb5167b63be5e10fbefb1af502a62b5dbed3f1d14017a13b27d1ebfaad3b935c23da9b6bc20195a6353c7a4a8809bd39c41064148e0d106e5c4904596f0103749d215d88a22ca543df15d308d6f9c1a523da7a821b64fb7a2151bcdbf531d025406218acba869c3345495666cc8c80e8254abb89005e17121aca99bae35a034a96972a96e34dc6179c46c5db2043cad82b851ad64e95d27006422cd6c0a4d65f2dd5394d9f8654a1cc668784d9461ff0199990f310fd22bc5a2e5a3a3e98e676dbd576af55f393832e4cec581e06defb193ae651771309d686632e64143a5ebae2c32011e1eaaed662965a7f09c961a56377529bf03c068f4d721928"

# Addition chain
# ------------------------------------------------------------