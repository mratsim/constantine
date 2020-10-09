# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  ../config/[curves, type_bigint],
  ../io/io_bigints,
  ../towers,
  ../pairing/cyclotomic_fp12

# Slow generic implementation
# ------------------------------------------------------------

# The bit count must be exact for the Miller loop
const BLS12_381_pairing_ate_param* = block:
  # BLS12 Miller loop is parametrized by u
  # +2 to bitlength so that we can mul by 3 for NAF encoding
  BigInt[64+2].fromHex"0xd201000000010000"

const BLS12_381_pairing_ate_param_isNeg* = true

const BLS12_381_pairing_finalexponent* = block:
  # (p^12 - 1) / r * 3
  BigInt[4316].fromHex"0x8ca592196587127a538fd40dc3e541f9dca04bb7dc671be77cf17715a2b2fe3bea73dfb468d8f473094aecb7315a664019fbd84913caba6579c08fd42009fe1bd6fcbce15eacb2cf3218a165958cb8bfdae2d2d54207282314fc0dea9d6ff3a07dbd34efb77b732ba5f994816e296a72928cfee133bdc3ca9412b984b9783d9c6aa81297ab1cd294a502304773528bbae8706979f28efa0d355b0224e2513d6e4a5d3bb4dde0523678105d9167ff1323d6e99ac312d8a7d762336370c4347bb5a7e405d6f3496b2dd38e722d4c1f3ac25e3167ec2cb543d69430c37c2f98fcdd0dd36caa9f5aa7994cec31b24ed5e515911037b376e521070d29c9d56cfa8c3574363efb20f28c19e4105ab99edd44084bd23725017931d6740bda71e5f07600ce6b407e543c4bc40bcd4c0b600e6c98003bf8548986b14d9098746dc89d154af91ad54f337b31c79222145dd3ed254fdeda0300c49ebcd2352765f533883a3513435f3ee452496f5166c25bf503bd6ec0a0679efda3b46ebf86211d458de749460d4a2a19abe6ea2accb451ab9a096b98465d044dc2a7f86c253a4ee57b6df108eff598a8dbc483bf8b74c2789939db85ffd7e0fd55b32bc26877f5be26fa7d750500ce2fab93c0cbe7336b126a5693d0c16484f37addccc7642590dbe98538990b88637e374d545d9b34b67448d0357e60280bbd8542f1f4e813caa8e8db57364b4e0cc14f35af381dd9b71ec9292b3a3f16e42362d2019e05f30"

# Addition chain
# ------------------------------------------------------------

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
