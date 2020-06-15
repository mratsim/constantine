# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  # Internals
  ../constantine/towers,
  ../constantine/config/curves,
  # Test utilities
  ./t_fp_tower_template

const TestCurves = [
    BLS12_381
  ]

runTowerTests(
  ExtDegree = 6,
  Iters = 128,
  TestCurves = TestCurves,
  moduleName = "test_fp6_" & $BLS12_381,
  testSuiteDesc = "𝔽p6 = 𝔽p2[v] " & $BLS12_381
)
