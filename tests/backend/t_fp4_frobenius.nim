# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  # Internals
  ../../constantine/backend/towers,
  ../../constantine/backend/config/curves,
  # Test utilities
  ./t_fp_tower_frobenius_template

const TestCurves = [
    BN254_Nogami,
    BN254_Snarks,
    BLS12_377,
    BLS12_381,
  ]

runFrobeniusTowerTests(
  ExtDegree = 4,
  Iters = 8,
  TestCurves = TestCurves,
  moduleName = "test_fp4_frobenius",
  testSuiteDesc = "𝔽p4 Frobenius map: Frobenius(a, k) = a^(pᵏ) (mod p⁴)"
)
