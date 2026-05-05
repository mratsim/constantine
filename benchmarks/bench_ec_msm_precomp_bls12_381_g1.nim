# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  constantine/named/algebras,
  constantine/math/ec_shortweierstrass,
  ./bench_elliptic_template

const Iters = 1000
const benchSizes = [64, 128, 256] # 4096

# Based on H23/H24 research papers:
# - Small windows (t=1, b=2..16) for fine-grained memory/performance tradeoff
# - Large windows (b=16, various t) for Pippenger-style precomputation
const precompConfigs = [
    # t=1
    (1, 2), (1, 3), (1, 4), (1, 5), (1, 6), (1, 7), (1, 8),
    # t=64
    (64, 8), (64, 10), (64, 12), (64, 16),
    # t=128
    (128, 8), (128, 10), (128, 12), (128, 16),
    # t=256
    (256, 8), (256, 10), (256, 12), (256, 16)
]

runPrecompMSMBench(EC_ShortW_Jac[Fp[BLS12_381], G1], benchSizes, precompConfigs, Iters)
