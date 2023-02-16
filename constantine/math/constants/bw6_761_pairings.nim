# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  ../../platforms/abstractions,
  ../config/curves,
  ../io/io_bigints,
  ../extension_fields,
  ../pairings/cyclotomic_subgroups,
  ../isogenies/frobenius

# Slow generic implementation
# ------------------------------------------------------------

# 1st part: f_{u+1,Q}(P)
const BW6_761_pairing_ate_param_1_unopt* = block:
  # BW6-761 unoptimized Miller loop first part is parametrized by u+1
  BigInt[64].fromHex"0x8508c00000000002"

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

const BW6_761_pairing_finalexponent_hard* = block:
  # (p^2 - p + 1) / r * 3*(u^3-u^2+1)
  BigInt[1335].fromHex"0x52d03a3bd1dd9aa185df830823e31f28dd2231c308bd86210eefcc7623b1c28d6b1e42eabf464f9161e52f11542cbacc962137fe3971d52652188b8ef74af13b0a049a4806e46f50f0c6eda7965e4275a966ebba028d346efe221daebfbbd9ca698a0ed763e9b1b0945bd554b2b8511e18bd7338b3355d3b2419c6fa6d71346b955d466ea17d418f7e444b5c67cd440c20be53ff99df9b79934de2c001a91809a300000000e0cd"


# Addition chain
# ------------------------------------------------------------

func cycl_exp_by_curve_param*(r: var Fp6[BW6_761], a: Fp6[BW6_761], invert = false) =
  ## f^u with u the curve parameter
  ## For BLS12_377/BW6_761 f^0x8508c00000000001
  r.cyclotomic_square(a)
  r *= a
  r.cyclotomic_square()
  r *= a
  let t111 = r

  r.cycl_sqr_repeated(2)
  let t111000 = r

  r *= t111
  let t100011 = r

  r.cyclotomic_square()
  r *= t100011
  r *= t111000

  r.cycl_sqr_repeated(10)
  r *= t100011

  r.cycl_sqr_repeated(46) # TODO: Karabina's compressed squarings
  r *= a

  if invert:
    r.cyclotomic_inv()

func isInPairingSubgroup*(a: Fp6[BW6_761]): SecretBool =
  ## Returns true if a is in GT subgroup, i.e. a is an element of order r
  ## Warning ⚠: Assumes that a is in the cyclotomic subgroup
  # Implementation: Scott, https://eprint.iacr.org/2021/1130.pdf
  #   A note on group membership tests for G1, G2 and GT
  #   on BLS pairing-friendly curves
  #   a is in the GT subgroup iff a^(p) == a^(t-1)
  #   with t the trace of the curve

  var u0{.noInit.}, u1{.noInit.}, u3{.noInit.}: Fp6[BW6_761]
  var u4{.noInit.}, u5{.noInit.}, u6{.noInit.}: Fp6[BW6_761]

  # t-1 = (13u⁶ - 23u⁵ - 9u⁴ + 35u³ + 10u + 19)/3
  u0.cyclotomic_square(a)    # u0 = 2
  u0.cycl_sqr_repeated(2)    # u0 = 8
  u0 *= a                    # u0 = 9
  u0.cyclotomic_square()     # u0 = 18
  u0 *= a                    # u0 = 19

  u1.cycl_exp_by_curve_param(a)  # u1 = u
  u4.cycl_exp_by_curve_param(u1) # u4 = u²

  u3.cyclotomic_square(u1)   # u3 = 2u
  u3.cyclotomic_square()     # u3 = 4u
  u1 *= u3                   # u1 = 5u
  u1.cyclotomic_square()     # u1 = 10u

  u0 *= u1                   # u0 = 10u + 19

  u1.cycl_exp_by_curve_param(u4) # u1 = u³
  u3.cyclotomic_square(u1)   # u3 = 2u³
  u3.cycl_sqr_repeated(3)    # u3 = 16u³
  u3 *= u1                   # u3 = 17u³
  u3.cyclotomic_square()     # u3 = 34u³
  u3 *= u1                   # u3 = 35u³

  u0 *= u3                   # u0 = 35u³ + 10u + 19
  u4.cycl_exp_by_curve_param(u1) # u4 = u⁴
  u5.cycl_exp_by_curve_param(u4) # u5 = u⁵
  u6.cycl_exp_by_curve_param(u5) # u6 = u⁶

  u1.cyclotomic_square(u4)   # u1 = 2u⁴
  u1.cycl_sqr_repeated(2)    # u1 = 8u⁴
  u4 *= u1                   # u4 = 9u⁴
  u4.cyclotomic_inv()        # u4 = -9u⁴

  u0 *= u4                   # u0 = -9u⁴ + 35u³ + 10u + 19

  u1.cyclotomic_inv(u5)      # u1 = -u⁵
  u1.cycl_sqr_repeated(3)    # u1 = -8u⁵
  u5 *= u1                   # u5 = -7u⁵
  u1.cyclotomic_square()     # u1 = -16u⁵
  u5 *= u1                   # u5 = -23u⁵

  u0 *= u5                   # u0 = -23u⁵ - 9u⁴ + 35u³ + 10u + 19

  u1.cyclotomic_square(u6)   # u1 = 2u⁶
  u1 *= u6                   # u1 = 3u⁶
  u1.cycl_sqr_repeated(2)    # u1 = 12u⁶
  u6 *= u1                   # u6 = 13u⁶

  u0 *= u6                   # u0 = 3(t-1) = 13u⁶ - 23u⁵ - 9u⁴ + 35u³ + 10u + 19

  u1.frobenius_map(a)        # u1 = p
  u3.cyclotomic_square(u1)   # u3 = 2p
  u3 *= u1                   # u3 = 3p

  return u0 == u3