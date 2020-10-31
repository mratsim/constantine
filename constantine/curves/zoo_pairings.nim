# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  std/macros,
  ../config/curves,
  ./bls12_377_pairing,
  ./bls12_381_pairing,
  ./bn254_nogami_pairing,
  ./bn254_snarks_pairing,
  ./bw6_761_pairing

{.experimental: "dynamicBindSym".}

macro pairing*(C: static Curve, value: untyped): untyped =
  ## Get pairing related constants
  return bindSym($C & "_pairing_" & $value)

export pow_x, pow_xdiv2, pow_u
