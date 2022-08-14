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
const BN254_Nogami_sqrt_fp2_QNR* = Fp2[BN254_Nogami].fromHex(
  "0x0",
  "0x1"
)
const BN254_Nogami_sqrt_fp2_sqrt_QNR* = Fp2[BN254_Nogami].fromHex(
  "0x1439ab09c60b248f398c5d77b755f92b9edc5f19d2873545be471151a747e4e",
  "0x23dfc9d1a39f4db8c69b87a8848aa075a7333a0e62d78cbf4b1b8eeae58b81c5"
)
const BN254_Nogami_sqrt_fp2_minus_sqrt_QNR* = Fp2[BN254_Nogami].fromHex(
  "0x23dfc9d1a39f4db8c69b87a8848aa075a7333a0e62d78cbf4b1b8eeae58b81c5",
  "0x23dfc9d1a39f4db8c69b87a8848aa075a7333a0e62d78cbf4b1b8eeae58b81c5"
)
