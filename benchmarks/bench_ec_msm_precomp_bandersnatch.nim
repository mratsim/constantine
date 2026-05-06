# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  constantine/named/algebras,
  constantine/math/ec_twistededwards,
  ./bench_elliptic_template

const Iters = 1000
const benchSizes = [64, 128, 256]
const precompConfigs = [(64, 8), (64, 10), (64, 12), (128, 8), (128, 10), (128, 12), (256, 8), (256, 10), (256, 12)]

runPrecompMSMBench(EC_TwEdw_Prj[Fp[Bandersnatch]], benchSizes, precompConfigs, Iters)
