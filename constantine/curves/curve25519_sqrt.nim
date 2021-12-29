# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  ../config/[curves, type_bigint, type_ff],
  ../io/[io_bigints, io_fields],
  ../arithmetic/finite_fields

# p ≡ 5 (mod 8), hence 𝑖 ∈ Fp with 𝑖² ≡ −1 (mod p)
# Hence if α is a square
# with β ≡ α^((p+3)/8) (mod p)
# - either β² ≡ α (mod p), hence √α ≡ ±β (mod p)
# - or β² ≡ -α (mod p), hence √α ≡ ±𝑖β (mod p)

# Sage:
#   p = Integer('0x7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffed')
#   Fp = GF(p)
#   sqrt_minus1 = Fp(-1).sqrt()
#   print(Integer(sqrt_minus1).hex())
const Curve25519_sqrt_minus_one* = Fp[Curve25519].fromHex(
    "0x2b8324804fc1df0b2b4d00993dfbd7a72f431806ad2fe478c4ee1b274a0ea0b0"
)