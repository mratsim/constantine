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
  ./constants/bls12_381_sqrt_fp2,
  ./constants/bn254_nogami_sqrt_fp2,
  ./constants/bn254_snarks_sqrt_fp2

{.experimental: "dynamicBindSym".}
macro sqrt_fp2*(Name: static Algebra, value: untyped): untyped =
  ## Get square_root constants
  return bindSym($Name & "_sqrt_fp2_" & $value)
