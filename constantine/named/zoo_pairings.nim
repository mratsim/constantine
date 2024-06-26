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
  ./constants/bls12_377_pairings,
  ./constants/bls12_381_pairings,
  ./constants/bn254_nogami_pairings,
  ./constants/bn254_snarks_pairings,
  ./constants/bw6_761_pairings

{.experimental: "dynamicBindSym".}

macro pairing*(Name: static Algebra, value: untyped): untyped =
  ## Get pairing related constants
  return bindSym($Name & "_pairing_" & $value)

export cycl_exp_by_curve_param, cycl_exp_by_curve_param_div2, millerLoopAddchain, isInPairingSubgroup
