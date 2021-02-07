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

# 1st part: f_{u+1,Q}(P)
const BW6_761_pairing_ate_param_1_unopt* = block:
  # BW6-761 unoptimized Miller loop first part is parametrized by u+1
  # +1 to bitlength so that we can mul by 3 for NAF encoding
  BigInt[64+1].fromHex"0x8508c00000000002"

const BW6_761_pairing_ate_param_1_unopt_isNeg* = false


# 2nd part: f_{u*(u²-u-1),Q}(P) followed by Frobenius application
const BW6_761_pairing_ate_param_2_unopt* = block:
  # BW6 unoptimized Miller loop second part is parametrized by u*(u²-u-1)
  # +1 to bitlength so that we can mul by 3 for NAF encoding
  BigInt[190+1].fromHex"0x23ed1347970dec008a442f991fffffffffffffffffffffff"

const BW6_761_pairing_ate_param_2_unopt_isNeg* = false


# 1st part: f_{u,Q}(P)
const BW6_761_pairing_ate_param_1_opt* = block:
  # BW6 Miller loop first part is parametrized by u
  # no NAF for the optimized first Miller loop
  BigInt[64].fromHex"0x8508c00000000001"

const BW6_761_pairing_ate_param_1_opt_isNeg* = false


# 2nd part: f_{u²-u-1,Q}(P) followed by Frobenius application
const BW6_761_pairing_ate_param_opt_2* = block:
  # BW6 Miller loop second part is parametrized by u²-u-1
  # +1 to bitlength so that we can mul by 3 for NAF encoding
  BigInt[127+1].fromHex"0x452217cc900000008508bfffffffffff"

const BW6_761_pairing_ate_param_2_opt_isNeg* = false


const BW6_761_pairing_finalexponent* = block:
  # (p^6 - 1) / r * 3
  BigInt[4186].fromHex"0x3d7fafd4d00189a67bdf3e3e099095571b3671b450e1430228baeca99efec770d2499a6732e8891ede83d26c08c7afdcb004a074ccea612933db92ba5b26a6683f2b782d91befd4170c3203b47ecb246847cd292b51591c00f608b6bd51942243a3042325356d537c26dc5cbe2c64656bf2aed4b94c66bf8629eb027698ebde2b14cbeda063db5d74b44c16ffd421206094832fe5b7ec54d68e312f5bfa26f87ea2c85578de4a05d1283d040a9a13ee0c9b4dfaf4116599b14ffbde13fb06415e28945def8dc5ada9692d40c49b675718ca8865551b0cca4c87bbb2becd0a90db08638c5bd777015ae4f34d19c66bb5de3e9929deb7de11789fb4100a0d1bbd75cabb2d52979693cd2f2c7bbb77016161f43722b3b1a32f3cf150df07f282193c7bd573c046e3b17775c3f007b2ba146b8fd2434604c0f29fb56edf981d37ad4c312c3daa27314b14db0d0c4d030a5dd7641899e685efcb9d41791a84ed44ef6b8f6f86522ef26e63f53693df95706fc1264a062f93d499cfdc033465a582b86fe0329b011a4536505fcd30aa0e09dfc3c57fc4a9e95246d4d4519160cb6088828f5082ebc1775012c6868441ee831d897fabe8de92fde56533968e8bd25fd04cccb2d932f768350e8b0eaebbcab3649380640e01daba898ae6c5085a149cf14bb0b2f465391d8393298b2c3caf1c30a8496035a5c00c8327c30f7d1d5c24f02a65f7d3d0b413ade8564b78"

# Addition chain
# ------------------------------------------------------------