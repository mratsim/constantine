# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  constantine/named/algebras,
  constantine/math/elliptic/ec_shortweierstrass_affine,
  constantine/math/io/[io_fields, io_extfields]

{.used.}

# Generators
# -----------------------------------------------------------------
# https://www.secg.org/sec2-v2.pdf page 9 (13 of PDF), sec. 2.4.1

# The group G_1 (== G) is defined on the curve Y^2 = X^3 + 7 over the field F_p
# with p = 2^256 - 2^32 - 2^9 - 2^8 - 2^7 - 2^6 - 2^4 - 1
# with generator:
const Secp256k1_generator_G1* = EC_ShortW_Aff[Fp[Secp256k1], G1](
  x: Fp[Secp256k1].fromHex"0x79BE667EF9DCBBAC55A06295CE870B07029BFCDB2DCE28D959F2815B16F81798",
  y: Fp[Secp256k1].fromHex"0x483ADA7726A3C4655DA4FBFC0E1108A8FD17B448A68554199C47D08FFB10D4B8"
)
