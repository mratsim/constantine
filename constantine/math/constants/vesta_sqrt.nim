# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  ../config/curves,
  ../io/[io_bigints, io_fields],
  ../arithmetic/finite_fields

const
  # with e = 2adicity
  # p == s * 2^e + 1
  # root_of_unity = smallest_quadratic_nonresidue^s
  # exponent = (p-1-2^e)/2^e / 2
  Vesta_TonelliShanks_exponent* = BigInt[222].fromHex"0x2000000000000000000000000000000011234c7e04ca546ec6237590"
  Vesta_TonelliShanks_twoAdicity* = 32
  Vesta_TonelliShanks_root_of_unity* = Fp[Vesta].fromHex"0x2de6a9b8746d3f589e5c4dfd492ae26e9bb97ea3c106f049a70e2c1102b6d05f"
