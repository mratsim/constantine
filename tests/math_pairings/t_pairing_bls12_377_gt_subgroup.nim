# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  constantine/math/pairings/pairings_bls12,
  # Test utilities
  ./t_pairing_template

runGTsubgroupTests(
  Iters = 4,
  GT = Fp12[BLS12_377],
  finalExpHard_BLS12)
