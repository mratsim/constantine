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
    # BN254_Nogami
    BN254_Snarks,
    BLS12_377,
    BLS12_381,
    # BN446
    # FKM12_447
    # BLS12_461
    # BN462
  ]

runTowerTests(
  ExtDegree = 2,
  Iters = 128,
  TestCurves = TestCurves,
  moduleName = "test_fp2",
  testSuiteDesc = "𝔽p2 = 𝔽p[u] (irreducible polynomial u²-β = 0) -> 𝔽p2 point (a, b) with coordinate a + bu and β quadratic non-residue in 𝔽p"
)
