# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
    constantine/math/io/io_bigints

# Banderwagon
# ------------------------------------------------------------

const Banderwagon_Lattice_G1* = (
  # (BigInt, isNeg)
  ((BigInt[127].fromHex"0x555fe2004be6928e4b02f94a9789181f", true),
   (BigInt[124].fromHex"0x814b3eee55e8f5df8e2591a23d61f44", true)),
  ((BigInt[125].fromHex"0x102967ddcabd1ebbf1c4b23447ac3e88", false),
   (BigInt[127].fromHex"0x555fe2004be6928e4b02f94a9789181f", true))
)

const Banderwagon_Babai_G1* = (
  # (BigInt, isNeg)
  (BigInt[4].fromHex"0xc", false),
  (BigInt[1].fromHex"0x0", false)
)
