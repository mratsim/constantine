# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  ../config/curves,
  ../io/[io_bigints, io_fields]

{.used.}

# Pallas G1
# ------------------------------------------------------------

const Pallas_cubicRootOfUnity_mod_p* =
  Fp[Pallas].fromHex"0x2d33357cb532458ed3552a23a8554e5005270d29d19fc7d27b7fd22f0201b547"

const Pallas_Lattice_G1* = (
  # (BigInt, isNeg)
  ((BigInt[127].fromHex"0x49e69d1640a899538cb1279300000000", true),
   (BigInt[127].fromHex"0x49e69d1640f049157fcae1c700000001", false)),
  ((BigInt[128].fromHex"0x93cd3a2c8198e2690c7c095a00000001", false),
   (BigInt[127].fromHex"0x49e69d1640a899538cb1279300000000", false))
)

const Pallas_Babai_G1* = (
  # (BigInt, isNeg)
  (BigInt[129].fromHex"0x1279a745902a2654e32c49e4bffffffff", true),
  (BigInt[129].fromHex"0x1279a745903c12455ff2b871c00000003", false)
)


