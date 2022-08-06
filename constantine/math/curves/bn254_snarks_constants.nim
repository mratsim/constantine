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
const BN254_Snarks_coefB_G2* = Fp2[BN254_Snarks].fromHex( 
  "0x2b149d40ceb8aaae81be18991be06ac3b5b4c5e559dbefa33267e6dc24a138e5",
  "0x9713b03af0fed4cd2cafadeed8fdf4a74fa084e52d1852e4a2bd0685c315d2"
)
const BN254_Snarks_coefB_G2_times_3* = Fp2[BN254_Snarks].fromHex( 
  "0x20753adca9c6bfb81499be5e509e8f8ff21b7c8d3cb039cf1ef69c66bce9b021",
  "0x1c53b10b0d2fc7e67860f09cc8af9ddf5eee18eaf8748f8ade8371391494176"
)
