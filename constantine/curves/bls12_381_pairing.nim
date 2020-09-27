# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  ../config/[curves, type_bigint],
  ../towers,
  ../io/io_bigints,
  ../pairing/cyclotomic_fp12

# The bit count must be exact for the Miller loop
const BLS12_381_pairing_ate_param* = block:
  # BLS Miller loop is parametrized by u
  BigInt[64+2].fromHex("0xd201000000010000") # +2 so that we can take *3 and NAF encode it

const BLS12_381_pairing_ate_param_isNeg* = true

const BLS12_381_pairing_finalexponent* = block:
  # (p^12 - 1) / r
  # BigInt[4314].fromHex"0x2ee1db5dcc825b7e1bda9c0496a1c0a89ee0193d4977b3f7d4507d07363baa13f8d14a917848517badc3a43d1073776ab353f2c30698e8cc7deada9c0aadff5e9cfee9a074e43b9a660835cc872ee83ff3a0f0f1c0ad0d6106feaf4e347aa68ad49466fa927e7bb9375331807a0dce2630d9aa4b113f414386b0e8819328148978e2b0dd39099b86e1ab656d2670d93e4d7acdd350da5359bc73ab61a0c5bf24c374693c49f570bcd2b01f3077ffb10bf24dde41064837f27611212596bc293c8d4c01f25118790f4684d0b9c40a68eb74bb22a40ee7169cdc1041296532fef459f12438dfc8e2886ef965e61a474c5c85b0129127a1b5ad0463434724538411d1676a53b5a62eb34c05739334f46c02c3f0bd0c55d3109cd15948d0a1fad20044ce6ad4c6bec3ec03ef19592004cedd556952c6d8823b19dadd7c2498345c6e5308f1c511291097db60b1749bf9b71a9f9e0100418a3ef0bc627751bbd81367066bca6a4c1b6dcfc5cceb73fc56947a403577dfa9e13c24ea820b09c1d9f7c31759c3635de3f7a3639991708e88adce88177456c49637fd7961be1a4c7e79fb02faa732e2f3ec2bea83d196283313492caa9d4aff1c910e9622d2a73f62537f2701aaef6539314043f7bbce5b78c7869aeb2181a67e49eeed2161daf3f881bd88592d767f67c4717489119226c2f011d4cab803e9d71650a6f80698e2f8491d12191a04406fbc8fbd5f48925f98630e68bfb24c0bcb9b55df57510"
  # (p^12 - 1) / r * 3
  BigInt[4316].fromHex"0x8ca592196587127a538fd40dc3e541f9dca04bb7dc671be77cf17715a2b2fe3bea73dfb468d8f473094aecb7315a664019fbd84913caba6579c08fd42009fe1bd6fcbce15eacb2cf3218a165958cb8bfdae2d2d54207282314fc0dea9d6ff3a07dbd34efb77b732ba5f994816e296a72928cfee133bdc3ca9412b984b9783d9c6aa81297ab1cd294a502304773528bbae8706979f28efa0d355b0224e2513d6e4a5d3bb4dde0523678105d9167ff1323d6e99ac312d8a7d762336370c4347bb5a7e405d6f3496b2dd38e722d4c1f3ac25e3167ec2cb543d69430c37c2f98fcdd0dd36caa9f5aa7994cec31b24ed5e515911037b376e521070d29c9d56cfa8c3574363efb20f28c19e4105ab99edd44084bd23725017931d6740bda71e5f07600ce6b407e543c4bc40bcd4c0b600e6c98003bf8548986b14d9098746dc89d154af91ad54f337b31c79222145dd3ed254fdeda0300c49ebcd2352765f533883a3513435f3ee452496f5166c25bf503bd6ec0a0679efda3b46ebf86211d458de749460d4a2a19abe6ea2accb451ab9a096b98465d044dc2a7f86c253a4ee57b6df108eff598a8dbc483bf8b74c2789939db85ffd7e0fd55b32bc26877f5be26fa7d750500ce2fab93c0cbe7336b126a5693d0c16484f37addccc7642590dbe98538990b88637e374d545d9b34b67448d0357e60280bbd8542f1f4e813caa8e8db57364b4e0cc14f35af381dd9b71ec9292b3a3f16e42362d2019e05f30"

func pow_xdiv2*(r: var Fp12[BLS12_381], a: Fp12[BLS12_381], invert = BLS12_381_pairing_ate_param_isNeg) =
  ## f^(x/2) with x the curve parameter
  ## For BLS12_381 f^-0xd201000000010000

  r.cyclotomic_square(a)
  r *= a
  r.cycl_sqr_repeated(2)
  r *= a
  r.cycl_sqr_repeated(3)
  r *= a
  r.cycl_sqr_repeated(9)
  r *= a
  r.cycl_sqr_repeated(32)   # TODO: use Karabina?
  r *= a
  r.cycl_sqr_repeated(16-1) # Don't do the last iteration

  if invert:
    r.cyclotomic_inv()

func pow_x*(r: var Fp12[BLS12_381], a: Fp12[BLS12_381], invert = BLS12_381_pairing_ate_param_isNeg) =
  ## f^x with x the curve parameter
  ## For BLS12_381 f^-0xd201000000010000
  r.pow_xdiv2(a, invert)
  r.cyclotomic_square()
