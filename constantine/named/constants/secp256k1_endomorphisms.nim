# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  constantine/named/algebras,
  constantine/math/io/[io_bigints, io_fields]

# Secp256k1 G1
# ------------------------------------------------------------

const Secp256k1_cubicRootOfUnity_mod_p* =
  Fp[Secp256k1].fromHex"0x851695d49a83f8ef919bb86153cbcb16630fb68aed0a766a3ec693d68e6afa40"

const Secp256k1_Lattice_G1* = (
  # (BigInt, isNeg)
  ((BigInt[128].fromHex"0xe4437ed6010e88286f547fa90abfe4c3", false),
   (BigInt[126].fromHex"0x3086d221a7d46bcde86c90e49284eb15", true)),
  ((BigInt[126].fromHex"0x3086d221a7d46bcde86c90e49284eb15", false),
   (BigInt[129].fromHex"0x114ca50f7a8e2f3f657c1108d9d44cfd8", false))
)

const Secp256k1_Babai_G1* = (
  # (BigInt, isNeg)
  (BigInt[129].fromHex"0x114ca50f7a8e2f3f657c1108d9d44cfd9", false),
  (BigInt[126].fromHex"0x3086d221a7d46bcde86c90e49284eb15", false)
)
