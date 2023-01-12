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
#           Specialized invsqrt for BW6-761
#
# ############################################################

func invsqrt_addchain*(r: var Fp[BW6_761], a: Fp[BW6_761]) {.addchain.} =
  var
    x10       {.noInit.}: Fp[BW6_761]
    x11       {.noInit.}: Fp[BW6_761]
    x101      {.noInit.}: Fp[BW6_761]
    x111      {.noInit.}: Fp[BW6_761]
    x1001     {.noInit.}: Fp[BW6_761]
    x1011     {.noInit.}: Fp[BW6_761]
    x1101     {.noInit.}: Fp[BW6_761]
    x1111     {.noInit.}: Fp[BW6_761]
    x10001    {.noInit.}: Fp[BW6_761]
    x10010    {.noInit.}: Fp[BW6_761]
    x10011    {.noInit.}: Fp[BW6_761]
    x10111    {.noInit.}: Fp[BW6_761]
    x11001    {.noInit.}: Fp[BW6_761]
    x11011    {.noInit.}: Fp[BW6_761]
    x11101    {.noInit.}: Fp[BW6_761]
    x11111    {.noInit.}: Fp[BW6_761]
    x100001   {.noInit.}: Fp[BW6_761]
    x100011   {.noInit.}: Fp[BW6_761]
    x100101   {.noInit.}: Fp[BW6_761]
    x100111   {.noInit.}: Fp[BW6_761]
    x101001   {.noInit.}: Fp[BW6_761]
    x101011   {.noInit.}: Fp[BW6_761]
    x101101   {.noInit.}: Fp[BW6_761]
    x101111   {.noInit.}: Fp[BW6_761]
    x110001   {.noInit.}: Fp[BW6_761]
    x110011   {.noInit.}: Fp[BW6_761]
    x110101   {.noInit.}: Fp[BW6_761]
    x110111   {.noInit.}: Fp[BW6_761]
    x111001   {.noInit.}: Fp[BW6_761]
    x111011   {.noInit.}: Fp[BW6_761]
    x111101   {.noInit.}: Fp[BW6_761]
    x1111010  {.noInit.}: Fp[BW6_761]
    x1111111  {.noInit.}: Fp[BW6_761]
    x11111110 {.noInit.}: Fp[BW6_761]
    x11111111 {.noInit.}: Fp[BW6_761]

  x10       .square(a)
  x11       .prod(a, x10)
  x101      .prod(x10, x11)
  x111      .prod(x10, x101)
  x1001     .prod(x10, x111)
  x1011     .prod(x10, x1001)
  x1101     .prod(x10, x1011)
  x1111     .prod(x10, x1101)
  x10001    .prod(x10, x1111)
  x10010    .prod(a, x10001)
  x10011    .prod(a, x10010)
  x10111    .prod(x101, x10010)
  x11001    .prod(x10, x10111)
  x11011    .prod(x10, x11001)
  x11101    .prod(x10, x11011)
  x11111    .prod(x10, x11101)
  x100001   .prod(x10, x11111)
  x100011   .prod(x10, x100001)
  x100101   .prod(x10, x100011)
  x100111   .prod(x10, x100101)
  x101001   .prod(x10, x100111)
  x101011   .prod(x10, x101001)
  x101101   .prod(x10, x101011)
  x101111   .prod(x10, x101101)
  x110001   .prod(x10, x101111)
  x110011   .prod(x10, x110001)
  x110101   .prod(x10, x110011)
  x110111   .prod(x10, x110101)
  x111001   .prod(x10, x110111)
  x111011   .prod(x10, x111001)
  x111101   .prod(x10, x111011)
  x1111010  .square(x111101)
  x1111111  .prod(x101, x1111010)
  x11111110 .square(x1111111)
  x11111111 .prod(a, x11111110)
  # 35 operations

  # 35 + 8 = 43 operations
  r.prod(x100001, x11111111)
  r.square_repeated(3)
  r *= x10111
  r.square_repeated(2)
  r *= a

  # 43 + 22 = 65 operations
  r.square_repeated(9)
  r *= x1001
  r.square_repeated(7)
  r *= x11111
  r.square_repeated(4)

  # 65 + 17 = 82 operations
  r *= x111
  r.square_repeated(9)
  r *= x1111
  r.square_repeated(5)
  r *= x111

  # 82 + 29 = 111 operations
  r.square_repeated(11)
  r *= x101011
  r.square_repeated(7)
  r *= x100011
  r.square_repeated(9)

  # 111 + 28 = 139 operations
  r *= x11111
  r.square_repeated(8)
  r *= x100101
  r.square_repeated(17)
  r *= x100111

  # 139 + 22 = 161 operations
  r.square_repeated(4)
  r *= x1101
  r.square_repeated(9)
  r *= x11111111
  r.square_repeated(7)

  # 161 + 15 = 176 operations
  r *= x11111
  r.square_repeated(6)
  r *= x10111
  r.square_repeated(6)
  r *= x1001

  # 176 + 22 = 198 operations
  r.square_repeated(4)
  r *= x11
  r.square_repeated(6)
  r *= x11
  r.square_repeated(10)

  # 198 + 16 = 214 operations
  r *= x110101
  r.square_repeated(2)
  r *= a
  r.square_repeated(11)
  r *= x11101

  # 214 + 28 = 238 operations
  r.square_repeated(6)
  r *= x101
  r.square_repeated(7)
  r *= x1101
  r.square_repeated(9)

  # 238 + 21 = 259 operations
  r *= x100001
  r.square_repeated(7)
  r *= x100101
  r.square_repeated(11)
  r *= x100111

  # 259 + 28 = 287 operations
  r.square_repeated(7)
  r *= x101111
  r.square_repeated(6)
  r *= x11111
  r.square_repeated(13)

  # 287 + 25 = 302 operations
  r *= x100001
  r.square_repeated(6)
  r *= x111011
  r.square_repeated(6)
  r *= x111001

  # 302 + 27 = 329 operations
  r.square_repeated(10)
  r *= x10111
  r.square_repeated(11)
  r *= x111101
  r.square_repeated(4)

  # 329 + 17 = 346 operations
  r *= x1101
  r.square_repeated(8)
  r *= x110001
  r.square_repeated(6)
  r *= x110001

  # 346 + 20 = 366 operations
  r.square_repeated(5)
  r *= x11001
  r.square_repeated(3)
  r *= x11
  r.square_repeated(10)

  # 366 + 16 = 382 operations
  r *= x100111
  r.square_repeated(5)
  r *= x1001
  r.square_repeated(8)
  r *= x11001

  # 382 + 25 = 407 operations
  r.square_repeated(10)
  r *= x1111
  r.square_repeated(7)
  r *= x11101
  r.square_repeated(6)

  # 407 + 20 = 427 operations
  r *= x11101
  r.square_repeated(9)
  r *= x11111111
  r.square_repeated(8)
  r *= x100101

  # 427 + 27 = 454 operations
  r.square_repeated(6)
  r *= x101101
  r.square_repeated(10)
  r *= x100011
  r.square_repeated(9)

  # 454 + 20 = 474 operations
  r *= x1001
  r.square_repeated(8)
  r *= x1101
  r.square_repeated(9)
  r *= x100111

  # 474 + 25 = 499 operations
  r.square_repeated(8)
  r *= x100011
  r.square_repeated(6)
  r *= x101101
  r.square_repeated(9)

  # 499 + 16 = 515 operations
  r *= x100101
  r.square_repeated(4)
  r *= x1111
  r.square_repeated(9)
  r *= x1111111

  # 515 + 25 = 540 operations
  r.square_repeated(6)
  r *= x11001
  r.square_repeated(8)
  r *= x111
  r.square_repeated(9)

  # 540 + 15 = 555 operations
  r *= x111011
  r.square_repeated(5)
  r *= x10011
  r.square_repeated(7)
  r *= x100111

  # 555 + 22 = 577 operations
  r.square_repeated(5)
  r *= x10111
  r.square_repeated(9)
  r *= x111001
  r.square_repeated(6)

  # 577 + 14 = 591 operations
  r *= x111101
  r.square_repeated(9)
  r *= x11111111
  r.square_repeated(2)
  r *= x11

  # 591 + 21 = 612 operations
  r.square_repeated(7)
  r *= x10111
  r.square_repeated(6)
  r *= x10011
  r.square_repeated(6)

  # 612 + 18 = 630 operations
  r *= x101
  r.square_repeated(9)
  r *= x10001
  r.square_repeated(6)
  r *= x11011

  # 630 + 27 = 657 operations
  r.square_repeated(10)
  r *= x100101
  r.square_repeated(7)
  r *= x110011
  r.square_repeated(8)

  # 657 + 13 = 670 operations
  r *= x111101
  r.square_repeated(7)
  r *= x100011
  r.square_repeated(3)
  r *= x111

  # 670 + 26 = 696 operations
  r.square_repeated(10)
  r *= x1011
  r.square_repeated(11)
  r *= x110011
  r.square_repeated(3)

  # 696 + 17 = 713 operations
  r *= x111
  r.square_repeated(9)
  r *= x101011
  r.square_repeated(5)
  r *= x10111

  # 713 + 21 = 734 operations
  r.square_repeated(7)
  r *= x101011
  r.square_repeated(2)
  r *= x11
  r.square_repeated(10)

  # 734 + 19 = 753 operations
  r *= x101001
  r.square_repeated(10)
  r *= x110111
  r.square_repeated(6)
  r *= x111001

  # 753 + 23 = 776 operations
  r.square_repeated(6)
  r *= x101001
  r.square_repeated(9)
  r *= x100111
  r.square_repeated(6)

  # 776 + 12 = 788 operations
  r *= x110011
  r.square_repeated(7)
  r *= x100001
  r.square_repeated(2)
  r *= x11

  # 788 + 39 = 827 operations
  r.square_repeated(21)
  r *= a
  r.square_repeated(11)
  r *= x101111
  r.square_repeated(5)

  # 827 + 55 = 882 operations
  r *= x1001
  r.square_repeated(7)
  r *= x11101
  r.square_repeated(45)
  r *= x10001

  # 882 + 1 = 883 operations
  r.square()
