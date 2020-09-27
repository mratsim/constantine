# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  ../config/curves,
  ../arithmetic/finite_fields

# ############################################################
#
#           Specialized inversion for Secp256k1
#
# ############################################################

# Field-specific inversion routines
func square_repeated(r: var Fp, num: int) =
  ## Repeated squarings
  for _ in 0 ..< num:
    r.square()

func inv_addchain*(r: var Fp[Secp256k1], a: Fp[Secp256k1]) {.used.}=
  ## We invert via Little Fermat's theorem
  ## a^(-1) ≡ a^(p-2) (mod p)
  ## with p = "0xFFFFFFFF FFFFFFFF FFFFFFFF FFFFFFFF FFFFFFFF FFFFFFFF FFFFFFFE FFFFFC2F"
  ## We take advantage of the prime special form to hardcode
  ## the sequence of squarings and multiplications for the modular exponentiation
  ##
  ## See libsecp256k1
  ##
  ## The binary representation of (p - 2) has 5 blocks of 1s, with lengths in
  ## { 1, 2, 22, 223 }. Use an addition chain to calculate 2^n - 1 for each block:
  ## [1], [2], 3, 6, 9, 11, [22], 44, 88, 176, 220, [223]

  var
    x2{.noInit.}: Fp[Secp256k1]
    x3{.noInit.}: Fp[Secp256k1]
    x6{.noInit.}: Fp[Secp256k1]
    x9{.noInit.}: Fp[Secp256k1]
    x11{.noInit.}: Fp[Secp256k1]
    x22{.noInit.}: Fp[Secp256k1]
    x44{.noInit.}: Fp[Secp256k1]
    x88{.noInit.}: Fp[Secp256k1]
    x176{.noInit.}: Fp[Secp256k1]
    x220{.noInit.}: Fp[Secp256k1]
    x223{.noInit.}: Fp[Secp256k1]

  x2.square(a)
  x2 *= a

  x3.square(x2)
  x3 *= a

  x6 = x3
  x6.square_repeated(3)
  x6 *= x3

  x9 = x6
  x9.square_repeated(3)
  x9 *= x3

  x11 = x9
  x11.square_repeated(2)
  x11 *= x2

  x22 = x11
  x22.square_repeated(11)
  x22 *= x11

  x44 = x22
  x44.square_repeated(22)
  x44 *= x22

  x88 = x44
  x88.square_repeated(44)
  x88 *= x44

  x176 = x88
  x88.square_repeated(88)
  x176 *= x88

  x220 = x176
  x220.square_repeated(44)
  x220 *= x44

  x223 = x220
  x223.square_repeated(3)
  x223 *= x3

  # The final result is then assembled using a sliding window over the blocks
  r = x223
  r.square_repeated(23)
  r *= x22
  r.square_repeated(5)
  r *= a
  r.square_repeated(3)
  r *= x2
  r.square_repeated(2)
  r *= a
