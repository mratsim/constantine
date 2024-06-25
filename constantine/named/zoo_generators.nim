# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  std/macros,
  ./algebras,
  ./constants/bls12_381_generators,
  ./constants/bn254_snarks_generators,
  ./constants/bandersnatch_generators,
  ./constants/banderwagon_generators

{.experimental: "dynamicbindsym".}

macro getGenerator*(Name: static Algebra, subgroup: static string = ""): untyped =
  ## Returns the curve subgroup generator.
  ## Pairing-friendly curves expect G1 or G2
  if subgroup == "":
    return bindSym($Name & "_generator")
  else:
    return bindSym($Name & "_generator_" & subgroup)
