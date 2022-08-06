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
const BLS12_377_coefB_G2* = Fp2[BLS12_377].fromHex( 
  "0x0",
  "0x10222f6db0fd6f343bd03737460c589dc7b4f91cd5fd889129207b63c6bf8000dd39e5c1ccccccd1c9ed9999999999a"
)
const BLS12_377_coefB_G2_times_3* = Fp2[BLS12_377].fromHex( 
  "0x0",
  "0x1582e9e796a73ef04fc0499f08107627b4f14c2672a760c18c2b4f2fb3aa000126f7dd026666666d0d3cccccccccccd"
)
