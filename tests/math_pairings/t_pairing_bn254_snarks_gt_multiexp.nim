# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  # Test utilities
  ./t_pairing_template

const numPoints = [1, 2, 8, 16, 128, 256, 1024]

runGTmultiexpTests(
  # Torus-based cryptography requires quadratic extension
  # but by default cubic extensions are faster
  # GT = Fp12[BN254_Snarks],
  GT = QuadraticExt[Fp6[BN254_Snarks]],
  numPoints,
  iters = 4)
