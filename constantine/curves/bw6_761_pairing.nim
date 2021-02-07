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
const BW6_761_pairing_ate_param_2_opt* = block:
  # BW6 Miller loop second part is parametrized by u²-u-1
  # +1 to bitlength so that we can mul by 3 for NAF encoding
  BigInt[127+1].fromHex"0x452217cc900000008508bfffffffffff"

const BW6_761_pairing_ate_param_2_opt_isNeg* = false


const BW6_761_pairing_finalexponent* = block:
  # (p^6 - 1) / r * 3*(u^3-u^2+1)
  BigInt[4376].fromHex"0x8a168e18d34ff984b8399b649a12265bcdd3023623c45b9a1d38314c4fdd4547f8a0c18b88468482c0ff74c94606e4e5734c43d4e9fa977c1196361496699ea26e4d912e4918fff3cbe177b5d47cd9ba63103cb2a7a1699ef2a48dd77d1f939ca33d35dadabf0aab681703a3340126ab78a2a76c2147cc4f5897f610596fed83ccdcab13b919d48f9365b50ad005a6fbcf41412c73ad8d03f465568acbb86d9b97d5216af6a67fe6d16f12c069cdc44035adc99b54e9e68095349af476057b5bc94bca6e4e23b8de4afd24d6fc655448269a02123b8c4d25115d8d09fc4b2774042d2c744568b132b11cb1fae68e025a6d8c7e405ce52092154a56523f2abeb3ec693419f8402799b08ae023360be4468046e81033e3e1d172d19d5ce5e3441140c26e710015f97bdbbddce57396c565d1a9d4f81d571415dacf2686171f2679797d97a35c59c372cca29eeb8556e2576912edb846235fb723a75a0cc5acc8ace1e5628f8e14c931f0a0d58372a44d0eba074e4fefff61efaf4bde1adf999e6194cf12c73cba39732fe059618901d4c0924b8a5d15ad9bea271be5f6679b6f0148f15d36a9269c4b6a07d08b2aa9b9365ab295a8c6a7eb4088e86fb5e30843798bf1bf426f07c2c39f4b8beef71b3da9c1d656ba3c23bbc8d3b54399d0e6fd1ec64616566ee1471934d0763fe360fb9a02bc3a5d4ccdf6fcaf52be7b67955a89b522a5e0a45e935f1794a038aeca4b9a6d8ae28da00178304c7dfc3d0e13ade8564b78"

# Addition chain
# ------------------------------------------------------------