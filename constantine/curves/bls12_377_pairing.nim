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
const BLS12_377_pairing_ate_param* = block:
  # BLS12 Miller loop is parametrized by u
  # +1 to bitlength so that we can mul by 3 for NAF encoding
  BigInt[64+1].fromHex"0x8508c00000000001"

const BLS12_377_pairing_ate_param_isNeg* = false

const BLS12_377_pairing_finalexponent* = block:
  # (p^12 - 1) / r * 3
  BigInt[4271].fromHex"0x518fe3a450394da01ed0ec73865aed18d4251c557c299312d07b5d31105598be5439b32fda943a26e8d85c306e6c1941dd3f9d646d87211c240f5489c67b1a8663c49da97a2880dc48213527e51d370acd05663ffda035ca31c4ba994c89d66c0c97066502f8ef19bb008e047c24cf96e02493f4683ffdc39075cc1c01df9fd0ec1dc0419176c010ac1a83b777201a77f8dab474e99c59ae840de7362f7c231d500aecc1eb52616067540d419f7f9fbfd22831919b4ac04960703d9753698941c95aa2d2a04f4bf26de9d191661a013cbb09227c09424595e2639ae94d35ce708bdec2c10628eb4f981945698ef049502d2a71994fab9898c028c73dd021f13208590be27e78f0f18a88f5ffe40157a9e9fef5aa229c0aa7fdb16a887af2c4a486258bf11fb1a5d945707a89d7bf8f67e5bb28f76a460d9a1e660cbbe91bfc456b8789d5bae1dba8cbef5b03bcd0ea30f6a7b45218292b2bf3b20ed5937cb5e2250eee395821805c6383d0286c7423beb42e79f85dab2a36df8fd154f2d89e5e9aaadaaa00e0a29ecc6e329195761d6063e0a2e136a3fb7671c9134c970a8588a7f3144642a10a5af77c105f5e90987f28c6604c5dcb604c02f7d642f7f819eea6fadb8aace7c4e146a17dab2c644d4372c6979845f261b4a20cd88a20325e0c0fc806bd9f60a8502fa8f466b6919311e232e06fd6a861cb5dc24d69274c7e631cac6b93e0254460d445a0000012b53b000000000000"

# Addition chain
# ------------------------------------------------------------

func pow_x*(r: var Fp12[BLS12_377], a: Fp12[BLS12_377], invert = BLS12_377_pairing_ate_param_isNeg) =
  ## f^x with x the curve parameter
  ## For BLS12_377 f^-0x8508c00000000001
  ## Warning: The parameter is odd and needs a correction
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
