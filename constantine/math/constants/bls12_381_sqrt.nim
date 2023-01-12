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
#           Specialized invsqrt for BLS12-381
#
# ############################################################

func invsqrt_addchain*(r: var Fp[BLS12_381], a: Fp[BLS12_381]) {.addchain.} =
  var
    x10       {.noInit.}: Fp[BLS12_381]
    x100      {.noInit.}: Fp[BLS12_381]
    x1000     {.noInit.}: Fp[BLS12_381]
    x1001     {.noInit.}: Fp[BLS12_381]
    x1011     {.noInit.}: Fp[BLS12_381]
    x1101     {.noInit.}: Fp[BLS12_381]
    x10001    {.noInit.}: Fp[BLS12_381]
    x10100    {.noInit.}: Fp[BLS12_381]
    x10101    {.noInit.}: Fp[BLS12_381]
    x11001    {.noInit.}: Fp[BLS12_381]
    x11010    {.noInit.}: Fp[BLS12_381]
    x110100   {.noInit.}: Fp[BLS12_381]
    x110110   {.noInit.}: Fp[BLS12_381]
    x110111   {.noInit.}: Fp[BLS12_381]
    x1001101  {.noInit.}: Fp[BLS12_381]
    x1001111  {.noInit.}: Fp[BLS12_381]
    x1010101  {.noInit.}: Fp[BLS12_381]
    x1011101  {.noInit.}: Fp[BLS12_381]
    x1100111  {.noInit.}: Fp[BLS12_381]
    x1101001  {.noInit.}: Fp[BLS12_381]
    x1110111  {.noInit.}: Fp[BLS12_381]
    x1111011  {.noInit.}: Fp[BLS12_381]
    x10001001 {.noInit.}: Fp[BLS12_381]
    x10010101 {.noInit.}: Fp[BLS12_381]
    x10010111 {.noInit.}: Fp[BLS12_381]
    x10101001 {.noInit.}: Fp[BLS12_381]
    x10110001 {.noInit.}: Fp[BLS12_381]
    x10111111 {.noInit.}: Fp[BLS12_381]
    x11000011 {.noInit.}: Fp[BLS12_381]
    x11010000 {.noInit.}: Fp[BLS12_381]
    x11010111 {.noInit.}: Fp[BLS12_381]
    x11100001 {.noInit.}: Fp[BLS12_381]
    x11100101 {.noInit.}: Fp[BLS12_381]
    x11101011 {.noInit.}: Fp[BLS12_381]
    x11110101 {.noInit.}: Fp[BLS12_381]
    x11111111 {.noInit.}: Fp[BLS12_381]

  x10       .square(a)
  x100      .square(x10)
  x1000     .square(x100)
  x1001     .prod(a, x1000)
  x1011     .prod(x10, x1001)
  x1101     .prod(x10, x1011)
  x10001    .prod(x100, x1101)
  x10100    .prod(x1001, x1011)
  x10101    .prod(a, x10100)
  x11001    .prod(x100, x10101)
  x11010    .prod(a, x11001)
  x110100   .square(x11010)
  x110110   .prod(x10, x110100)
  x110111   .prod(a, x110110)
  x1001101  .prod(x11001, x110100)
  x1001111  .prod(x10, x1001101)
  x1010101  .prod(x1000, x1001101)
  x1011101  .prod(x1000, x1010101)
  x1100111  .prod(x11010, x1001101)
  x1101001  .prod(x10, x1100111)
  x1110111  .prod(x11010, x1011101)
  x1111011  .prod(x100, x1110111)
  x10001001 .prod(x110100, x1010101)
  x10010101 .prod(x11010, x1111011)
  x10010111 .prod(x10, x10010101)
  x10101001 .prod(x10100, x10010101)
  x10110001 .prod(x1000, x10101001)
  x10111111 .prod(x110110, x10001001)
  x11000011 .prod(x100, x10111111)
  x11010000 .prod(x1101, x11000011)
  x11010111 .prod(x10100, x11000011)
  x11100001 .prod(x10001, x11010000)
  x11100101 .prod(x100, x11100001)
  x11101011 .prod(x10100, x11010111)
  x11110101 .prod(x10100, x11100001)
  x11111111 .prod(x10100, x11101011)
  # 36 operations

  # 36 + 22 = 58 operations
  r.prod(x10111111, x11100001)
  r.square_repeated(8)
  r *= x10001
  r.square_repeated(11)
  r *= x11110101

  # 58 + 28 = 86 operations
  r.square_repeated(11)
  r *= x11100101
  r.square_repeated(8)
  r *= x11111111
  r.square_repeated(7)

  # 86 + 22 = 108 operations
  r *= x1001101
  r.square_repeated(9)
  r *= x1101001
  r.square_repeated(10)
  r *= x10110001

  # 108+24 = 132 operations
  r.square_repeated(7)
  r *= x1011101
  r.square_repeated(9)
  r *= x1111011
  r.square_repeated(6)

  # 132+23 = 155 operations
  r *= x11001
  r.square_repeated(11)
  r *= x1101001
  r.square_repeated(9)
  r *= x11101011

  # 155+28 = 183 operations
  r.square_repeated(10)
  r *= x11010111
  r.square_repeated(6)
  r *= x11001
  r.square_repeated(10)

  # 183+23 = 206 operations
  r *= x1110111
  r.square_repeated(9)
  r *= x10010111
  r.square_repeated(11)
  r *= x1001111

  # 206+30 = 236 operations
  r.square_repeated(10)
  r *= x11100001
  r.square_repeated(9)
  r *= x10001001
  r.square_repeated(9)

  # 236+21 = 257 operations
  r *= x10111111
  r.square_repeated(8)
  r *= x1100111
  r.square_repeated(10)
  r *= x11000011

  # 257+28 = 285 operations
  r.square_repeated(9)
  r *= x10010101
  r.square_repeated(12)
  r *= x1111011
  r.square_repeated(5)

  # 285 + 21 = 306 operations
  r *= x1011
  r.square_repeated(11)
  r *= x1111011
  r.square_repeated(7)
  r *= x1001

  # 306+32 = 338 operations
  r.square_repeated(13)
  r *= x11110101
  r.square_repeated(9)
  r *= x10111111
  r.square_repeated(8)

  # 338+22 = 360 operations
  r *= x11111111
  r.square_repeated(8)
  r *= x11101011
  r.square_repeated(11)
  r *= x10101001

  # 360+24 = 384 operations
  r.square_repeated(8)
  r *= x11111111
  r.square_repeated(8)
  r *= x11111111
  r.square_repeated(6)

  # 384+22 = 406 operations
  r *= x110111
  r.square_repeated(10)
  r *= x11111111
  r.square_repeated(9)
  r *= x11111111

  # 406+26 = 432 operations
  r.square_repeated(8)
  r *= x11111111
  r.square_repeated(8)
  r *= x11111111
  r.square_repeated(8)

  # 432+17 = 449 operations
  r *= x11111111
  r.square_repeated(7)
  r *= x1010101
  r.square_repeated(6)
  r *= x10101
  r.square()

  # Total 449 operations:
  # - 75 multiplications
  # - 374 squarings
