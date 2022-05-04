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
  ./bls12_381_generators,
  ./bn254_snarks_generators

{.experimental: "dynamicbindsym".}

macro getGenerator*(C: static Curve, subgroup: static string = ""): untyped =
  ## Returns the curve subgroup generator.
  ## Pairing-friendly curves expect G1 or G2
  
  if subgroup == "":
    return bindSym($C & "_generator")
  else:
    return bindSym($C & "_generator_" & subgroup)