# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  ../constantine/config/common,
  ../constantine/config/curves,
  ../constantine/pairing/pairing_bn,
  # Test utilities
  ./t_pairing_template

runPairingTests(
  4, BN254_Nogami,
  G1 = ECP_ShortW_Proj[Fp[BN254_Nogami], NotOnTwist],
  G2 = ECP_ShortW_Proj[Fp2[BN254_Nogami], OnTwist],
  GT = Fp12[BN254_Nogami],
  pairing_bn)
