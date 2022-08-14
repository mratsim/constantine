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

# Vesta G1
# ------------------------------------------------------------

const Vesta_cubicRootOfUnity_mod_p* =
  Fp[Vesta].fromHex"0x397e65a7d7c1ad71aee24b27e308f0a61259527ec1d4752e619d1840af55f1b1"

const Vesta_Lattice_G1* = (
  # (BigInt, isNeg)
  ((BigInt[127].fromHex"0x49e69d1640a899538cb1279300000001", true),
   (BigInt[127].fromHex"0x49e69d1640f049157fcae1c700000000", false)),
  ((BigInt[128].fromHex"0x93cd3a2c8198e2690c7c095a00000001", false),
   (BigInt[127].fromHex"0x49e69d1640a899538cb1279300000001", false))
)

const Vesta_Babai_G1* = (
  # (BigInt, isNeg)
  (BigInt[129].fromHex"0x1279a745902a2654e32c49e4c00000003", true),
  (BigInt[129].fromHex"0x1279a745903c12455ff2b871bffffffff", false)
)


