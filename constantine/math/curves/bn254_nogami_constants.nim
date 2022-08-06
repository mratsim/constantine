# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  ../config/curves,
  ../io/io_extfields

{.used.}

# Curve precomputed parameters
# -----------------------------------------------------------------
const BN254_Nogami_coefB_G2* = Fp2[BN254_Nogami].fromHex( 
  "0x1",
  "0x2523648240000001ba344d80000000086121000000000013a700000000000012"
)
const BN254_Nogami_coefB_G2_times_3* = Fp2[BN254_Nogami].fromHex( 
  "0x3",
  "0x2523648240000001ba344d80000000086121000000000013a700000000000010"
)
