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
  Banderwagon_TonelliShanks_exponent* = BigInt[222].fromHex"0x39f6d3a994cebea4199cec0404d0ec02a9ded2017fff2dff7fffffff"
  Banderwagon_TonelliShanks_twoAdicity* = 32
  Banderwagon_TonelliShanks_root_of_unity* = Fp[Banderwagon].fromHex"0x212d79e5b416b6f0fd56dc8d168d6c0c4024ff270b3e0941b788f500b912f1f"
