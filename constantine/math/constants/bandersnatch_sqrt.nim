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
  Bandersnatch_TonelliShanks_exponent* = BigInt[222].fromHex"0x39f6d3a994cebea4199cec0404d0ec02a9ded2017fff2dff7fffffff"
  Bandersnatch_TonelliShanks_twoAdicity* = 32
  Bandersnatch_TonelliShanks_root_of_unity* = Fp[Bandersnatch].fromHex"0x212d79e5b416b6f0fd56dc8d168d6c0c4024ff270b3e0941b788f500b912f1f"

# ############################################################
#
#       Specialized Tonelli-Shanks for Bandersnatch
#
# ############################################################

func precompute_tonelli_shanks_addchain*(
       r: var Fp[Bandersnatch],
       a: Fp[Bandersnatch]) {.addchain.} =
  ## Does a^Bandersnatch_TonelliShanks_exponent
  ## via an addition-chain

  var
    x10       {.noInit.}: Fp[Bandersnatch]
    x100      {.noInit.}: Fp[Bandersnatch]
    x110      {.noInit.}: Fp[Bandersnatch]
    x1100     {.noInit.}: Fp[Bandersnatch]
    x10010    {.noInit.}: Fp[Bandersnatch]
    x10011    {.noInit.}: Fp[Bandersnatch]
    x10110    {.noInit.}: Fp[Bandersnatch]
    x11000    {.noInit.}: Fp[Bandersnatch]
    x11010    {.noInit.}: Fp[Bandersnatch]
    x100010   {.noInit.}: Fp[Bandersnatch]
    x110101   {.noInit.}: Fp[Bandersnatch]
    x111011   {.noInit.}: Fp[Bandersnatch]
    x1001011  {.noInit.}: Fp[Bandersnatch]
    x1001101  {.noInit.}: Fp[Bandersnatch]
    x1010101  {.noInit.}: Fp[Bandersnatch]
    x1100111  {.noInit.}: Fp[Bandersnatch]
    x1101001  {.noInit.}: Fp[Bandersnatch]
    x10000011 {.noInit.}: Fp[Bandersnatch]
    x10011001 {.noInit.}: Fp[Bandersnatch]
    x10011101 {.noInit.}: Fp[Bandersnatch]
    x10111111 {.noInit.}: Fp[Bandersnatch]
    x11010111 {.noInit.}: Fp[Bandersnatch]
    x11011011 {.noInit.}: Fp[Bandersnatch]
    x11100111 {.noInit.}: Fp[Bandersnatch]
    x11101111 {.noInit.}: Fp[Bandersnatch]
    x11111111 {.noInit.}: Fp[Bandersnatch]

  x10       .square(a)
  x100      .square(x10)
  x110      .prod(x10, x100)
  x1100     .square(x110)
  x10010    .prod(x110, x1100)
  x10011    .prod(a, x10010)
  x10110    .prod(x100, x10010)
  x11000    .prod(x10, x10110)
  x11010    .prod(x10, x11000)
  x100010   .prod(x1100, x10110)
  x110101   .prod(x10011, x100010)
  x111011   .prod(x110, x110101)
  x1001011  .prod(x10110, x110101)
  x1001101  .prod(x10, x1001011)
  x1010101  .prod(x11010, x111011)
  x1100111  .prod(x10010, x1010101)
  x1101001  .prod(x10, x1100111)
  x10000011 .prod(x11010, x1101001)
  x10011001 .prod(x10110, x10000011)
  x10011101 .prod(x100, x10011001)
  x10111111 .prod(x100010, x10011101)
  x11010111 .prod(x11000, x10111111)
  x11011011 .prod(x100, x11010111)
  x11100111 .prod(x1100, x11011011)
  x11101111 .prod(x11000, x11010111)
  x11111111 .prod(x11000, x11100111)
  # 26 operations

  let a = a # Allow aliasing between r and a

  # 26+28 = 54 operations
  r.square_repeated(x11100111, 8)
  r *= x11011011
  r.square_repeated(9)
  r *= x10011101
  r.square_repeated(9)

  # 54 + 20 = 74 operations
  r *= x10011001
  r.square_repeated(9)
  r *= x10011001
  r.square_repeated(8)
  r *= x11010111

  # 74 + 27 = 101 operations
  r.square_repeated(6)
  r *= x110101
  r.square_repeated(10)
  r *= x10000011
  r.square_repeated(9)

  # 101 + 19 = 120 operations
  r *= x1100111
  r.square_repeated(8)
  r *= x111011
  r.square_repeated(8)
  r *= a

  # 120 + 41 = 160 operations
  r.square_repeated(14)
  r *= x1001101
  r.square_repeated(10)
  r *= x111011
  r.square_repeated(15)

  # 161 + 21 = 182 operations
  r *= x1010101
  r.square_repeated(10)
  r *= x11101111
  r.square_repeated(8)
  r *= x1101001

  # 182 + 33 = 215 operations
  r.square_repeated(16)
  r *= x10111111
  r.square_repeated(8)
  r *= x11111111
  r.square_repeated(7)

  # 215 + 20 = 235 operations
  r *= x1001011
  r.square_repeated(9)
  r *= x11111111
  r.square_repeated(8)
  r *= x10111111

  # 235 + 26 = 261 operations
  r.square_repeated(8)
  r *= x11111111
  r.square_repeated(8)
  r *= x11111111
  r.square_repeated(8)

  # 261 + 3 = 264 operations
  r *= x11111111
  r.square()
  r *= a
