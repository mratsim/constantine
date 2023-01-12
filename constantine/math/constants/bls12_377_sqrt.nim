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
  BLS12_377_TonelliShanks_exponent* = BigInt[330].fromHex"0x35c748c2f8a21d58c760b80d94292763445b3e601ea271e3de6c45f741290002e16ba88600000010a11"
  BLS12_377_TonelliShanks_twoAdicity* = 46
  BLS12_377_TonelliShanks_root_of_unity* = Fp[BLS12_377].fromHex"0x382d3d99cdbc5d8fe9dee6aa914b0ad14fcaca7022110ec6eaa2bc56228ac41ea03d28cc795186ba6b5ef26b00bbe8"

# ############################################################
#
#       Specialized Tonelli-Shanks for BLS12-377
#
# ############################################################

func precompute_tonelli_shanks_addchain*(
       r: var Fp[BLS12_377],
       a: Fp[BLS12_377]) {.addchain.} =
  ## Does a^BLS12_377_TonelliShanks_exponent
  ## via an addition-chain

  var
    x10       {.noInit.}: Fp[BLS12_377]
    x11       {.noInit.}: Fp[BLS12_377]
    x100      {.noInit.}: Fp[BLS12_377]
    x101      {.noInit.}: Fp[BLS12_377]
    x111      {.noInit.}: Fp[BLS12_377]
    x1001     {.noInit.}: Fp[BLS12_377]
    x1011     {.noInit.}: Fp[BLS12_377]
    x1111     {.noInit.}: Fp[BLS12_377]
    x10001    {.noInit.}: Fp[BLS12_377]
    x10011    {.noInit.}: Fp[BLS12_377]
    x10111    {.noInit.}: Fp[BLS12_377]
    x11011    {.noInit.}: Fp[BLS12_377]
    x11101    {.noInit.}: Fp[BLS12_377]
    x11111    {.noInit.}: Fp[BLS12_377]
    x110100   {.noInit.}: Fp[BLS12_377]
    x11010000 {.noInit.}: Fp[BLS12_377]
    x11010111 {.noInit.}: Fp[BLS12_377]

  x10       .square(a)
  x11       .prod(a, x10)
  x100      .prod(a, x11)
  x101      .prod(a, x100)
  x111      .prod(x10, x101)
  x1001     .prod(x10, x111)
  x1011     .prod(x10, x1001)
  x1111     .prod(x100, x1011)
  x10001    .prod(x10, x1111)
  x10011    .prod(x10, x10001)
  x10111    .prod(x100, x10011)
  x11011    .prod(x100, x10111)
  x11101    .prod(x10, x11011)
  x11111    .prod(x10, x11101)
  x110100   .prod(x10111, x11101)
  x11010000 .square_repeated(x110100, 2)
  x11010111 .prod(x111, x11010000)
  # 18 operations

  # 18 + 18 = 36 operations
  r.square_repeated(x11010111, 8)
  r *= x11101
  r.square_repeated(7)
  r *= x10001
  r.square()

  # 36 + 14 = 50 operations
  r *= a
  r.square_repeated(9)
  r *= x10111
  r.square_repeated(2)
  r *= x11

  # 50 + 21 = 71 operations
  r.square_repeated(6)
  r *= x101
  r.square_repeated(4)
  r *= a
  r.square_repeated(9)

  # 71 + 13 = 84 operations
  r *= x11101
  r.square_repeated(5)
  r *= x1011
  r.square_repeated(5)
  r *= x11

  # 84 + 21 = 105 operations
  r.square_repeated(8)
  r *= x11101
  r.square()
  r *= a
  r.square_repeated(10)

  # 105 + 20 = 125 operations
  r *= x10111
  r.square_repeated(12)
  r *= x11011
  r.square_repeated(5)
  r *= x101

  # 125 + 22 = 147 operations
  r.square_repeated(7)
  r *= x101
  r.square_repeated(6)
  r *= x1001
  r.square_repeated(7)

  # 147 + 11 = 158 operations
  r *= x11101
  r.square_repeated(5)
  r *= x10001
  r.square_repeated(3)
  r *= x101

  # 158 + 23 = 181 operations
  r.square_repeated(8)
  r *= x10001
  r.square_repeated(6)
  r *= x11011
  r.square_repeated(7)

  # 181 + 19 = 200 operations
  r *= x11111
  r.square_repeated(4)
  r *= x11
  r.square_repeated(12)
  r *= x1111

  # 200 + 19 = 219 operations
  r.square_repeated(4)
  r *= x101
  r.square_repeated(8)
  r *= x10011
  r.square_repeated(5)

  # 219 + 13 = 232 operations
  r *= x10001
  r.square_repeated(3)
  r *= x111
  r.square_repeated(7)
  r *= x1111

  # 232 + 22 = 254 operations
  r.square_repeated(5)
  r *= x1111
  r.square_repeated(7)
  r *= x11011
  r.square_repeated(8)

  # 254 + 13 = 269 operations
  r *= x10001
  r.square_repeated(6)
  r *= x11111
  r.square_repeated(6)
  r *= x11101

  # 269 + 35 = 304 operations
  r.square_repeated(9)
  r *= x1001
  r.square_repeated(5)
  r *= x1001
  r.square_repeated(19)

  # 304 + 17 = 321 operations
  r *= x10111
  r.square_repeated(8)
  r *= x1011
  r.square_repeated(6)
  r *= x10111

  # 321 + 16 = 337 operations
  r.square_repeated(4)
  r *= x101
  r.square_repeated(4)
  r *= a
  r.square_repeated(6)

  # 337 + 29 = 376 operations
  r *= x11
  r.square_repeated(29)
  r *= a
  r.square_repeated(7)
  r *= x101

  # 376 + 10 = 386 operations
  r.square_repeated(9)
  r *= x10001
