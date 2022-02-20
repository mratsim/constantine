# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  ../../constantine/backend/config/common,
  ../../constantine/backend/config/curves,
  ../../constantine/backend/pairing/pairing_bw6_761,
  # Test utilities
  ./t_pairing_template

runGTsubgroupTests(
  Iters = 4,
  GT = Fp6[BW6_761],
  finalExpHard_BW6_761)
