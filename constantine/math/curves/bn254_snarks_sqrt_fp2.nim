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

# Square Root Fp2 constants
# -----------------------------------------------------------------
const BN254_Snarks_sqrt_fp2_QNR* = Fp2[BN254_Snarks].fromHex(
  "0x0",
  "0x1"
)
const BN254_Snarks_sqrt_fp2_sqrt_QNR* = Fp2[BN254_Snarks].fromHex(
  "0x4636956ffd65e421c784f990c3a7533717e614fc6e7f616577d10f6464b5204",
  "0x4636956ffd65e421c784f990c3a7533717e614fc6e7f616577d10f6464b5204"
)
const BN254_Snarks_sqrt_fp2_minus_sqrt_QNR* = Fp2[BN254_Snarks].fromHex(
  "0x2c00e51be15b41e79bd7f61d7546e32a26030941a189d476e4a37b209231ab43",
  "0x4636956ffd65e421c784f990c3a7533717e614fc6e7f616577d10f6464b5204"
)
