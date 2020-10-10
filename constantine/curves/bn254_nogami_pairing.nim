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
const BN254_Nogami_pairing_ate_param* = block:
  # BN Miller loop is parametrized by 6u+2
  # +2 to bitlength so that we can mul by 3 for NAF encoding
  BigInt[65+2].fromHex"0x18300000000000004"

const BN254_Nogami_pairing_ate_param_isNeg* = true

const BN254_Nogami_pairing_finalexponent* = block:
  # (p^12 - 1) / r
  BigInt[2786].fromHex"0x2928fbb36b391596ee3fe4cbe857330da83e46fedf04d235a4a8daf5ff9f6eabcb4e3f20aa06f0a0d96b24f9af0cbbce750d61627dcbf5fec9139b8f1c46c86b49b4f8a202af26e4504f2c0f56570e9bd5b94c403f385d1908556486e24b396ddc2cdf13d06542f84fe8e82ccbad7b7423fc1ef4e8cc73d605e3e867c0a75f45ea7f6356d9846ce35d5a34f30396938818ad41914b97b99c289a7259b5d2e09477a77bd3c409b19f19e893f8ade90b0aed1b5fc8a07a3cebb41d4e9eee96b21a832ddb1e93e113edfb704fa532848c18593cd0ee90444a1b3499a800177ea38bdec62ec5191f2b6bbee449722f98d2173ad33077545c2ad10347e125a56fb40f086e9a4e62ad336a72c8b202ac3c1473d73b93d93dc0795ca0ca39226e7b4c1bb92f99248ec0806e0ad70744e9f2238736790f5185ea4c70808442a7d530c6ccd56b55a6973867ec6c73599bbd020bbe105da9c6b5c009ad8946cd6f0"

# Addition chain
# ------------------------------------------------------------

func pow_u*(r: var Fp12[BN254_Nogami], a: Fp12[BN254_Nogami], invert = BN254_Nogami_pairing_ate_param_isNeg) =
  ## f^u with u the curve parameter
  ## For BN254_Nogami f^-0x4080000000000001
  r = a
  r.cycl_sqr_repeated(7)
  r *= a
  r.cycl_sqr_repeated(55)
  r *= a

  if invert:
    r.cyclotomic_inv()
