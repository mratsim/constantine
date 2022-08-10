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
  Pallas_TonelliShanks_exponent* = BigInt[222].fromHex"0x2000000000000000000000000000000011234c7e04a67c8dcc969876"
  Pallas_TonelliShanks_twoAdicity* = 32
  Pallas_TonelliShanks_root_of_unity* = Fp[Pallas].fromHex"0x2bce74deac30ebda362120830561f81aea322bf2b7bb7584bdad6fabd87ea32f"
