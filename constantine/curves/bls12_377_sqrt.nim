# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  ../config/[curves, type_bigint, type_ff],
  ../io/[io_bigints, io_fields]

const
  # with e = 2adicity
  # p == s * 2^e + 1
  # root_of_unity = smallest_quadratic_nonresidue^s
  # exponent = (p-1-2^e)/2^e / 2
  BLS12_377_TonelliShanks_exponent* = BigInt[330].fromHex"0x35c748c2f8a21d58c760b80d94292763445b3e601ea271e3de6c45f741290002e16ba88600000010a11"
  BLS12_377_TonelliShanks_twoAdicity* = 46
  BLS12_377_TonelliShanks_root_of_unity* = Fp[BLS12_377].fromHex"0x382d3d99cdbc5d8fe9dee6aa914b0ad14fcaca7022110ec6eaa2bc56228ac41ea03d28cc795186ba6b5ef26b00bbe8"
