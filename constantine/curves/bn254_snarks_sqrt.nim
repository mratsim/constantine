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
#           Specialized inversion for BN254-Snarks
#
# ############################################################

func invsqrt_addchain*(r: var Fp[BN254_Snarks], a: Fp[BN254_Snarks]) {.addchain.} =
  var
    x10       {.noInit.}: Fp[BN254_Snarks]
    x11       {.noInit.}: Fp[BN254_Snarks]
    x101      {.noInit.}: Fp[BN254_Snarks]
    x110      {.noInit.}: Fp[BN254_Snarks]
    x1000     {.noInit.}: Fp[BN254_Snarks]
    x1101     {.noInit.}: Fp[BN254_Snarks]
    x10010    {.noInit.}: Fp[BN254_Snarks]
    x10011    {.noInit.}: Fp[BN254_Snarks]
    x10100    {.noInit.}: Fp[BN254_Snarks]
    x10111    {.noInit.}: Fp[BN254_Snarks]
    x11100    {.noInit.}: Fp[BN254_Snarks]
    x100000   {.noInit.}: Fp[BN254_Snarks]
    x100011   {.noInit.}: Fp[BN254_Snarks]
    x101011   {.noInit.}: Fp[BN254_Snarks]
    x101111   {.noInit.}: Fp[BN254_Snarks]
    x1000001  {.noInit.}: Fp[BN254_Snarks]
    x1010011  {.noInit.}: Fp[BN254_Snarks]
    x1011011  {.noInit.}: Fp[BN254_Snarks]
    x1100001  {.noInit.}: Fp[BN254_Snarks]
    x1110101  {.noInit.}: Fp[BN254_Snarks]
    x10010001 {.noInit.}: Fp[BN254_Snarks]
    x10010101 {.noInit.}: Fp[BN254_Snarks]
    x10110101 {.noInit.}: Fp[BN254_Snarks]
    x10111011 {.noInit.}: Fp[BN254_Snarks]
    x11000001 {.noInit.}: Fp[BN254_Snarks]
    x11000011 {.noInit.}: Fp[BN254_Snarks]
    x11010011 {.noInit.}: Fp[BN254_Snarks]
    x11100001 {.noInit.}: Fp[BN254_Snarks]
    x11100011 {.noInit.}: Fp[BN254_Snarks]
    x11100111 {.noInit.}: Fp[BN254_Snarks]

  x10       .square(a)
  x11       .prod(x10, a)
  x101      .prod(x10, x11)
  x110      .prod(x101, a)
  x1000     .prod(x10, x110)
  x1101     .prod(x101, x1000)
  x10010    .prod(x101, x1101)
  x10011    .prod(x10010, a)
  x10100    .prod(x10011, a)
  x10111    .prod(x11, x10100)
  x11100    .prod(x101, x10111)
  x100000   .prod(x1101, x10011)
  x100011   .prod(x11, x100000)
  x101011   .prod(x1000, x100011)
  x101111   .prod(x10011, x11100)
  x1000001  .prod(x10010, x101111)
  x1010011  .prod(x10010, x1000001)
  x1011011  .prod(x1000, x1010011)
  x1100001  .prod(x110, x1011011)
  x1110101  .prod(x10100, x1100001)
  x10010001 .prod(x11100, x1110101)
  x10010101 .prod(x100000, x1110101)
  x10110101 .prod(x100000, x10010101)
  x10111011 .prod(x110, x10110101)
  x11000001 .prod(x110, x10111011)
  x11000011 .prod(x10, x11000001)
  x11010011 .prod(x10010, x11000001)
  x11100001 .prod(x100000, x11000001)
  x11100011 .prod(x10, x11100001)
  x11100111 .prod(x110, x11100001) # 30 operations

  # 30 + 27 = 57 operations
  r.square(x11000001)
  r.square_repeated(7)
  r *= x10010001
  r.square_repeated(10)
  r *= x11100111
  r.square_repeated(7)

  # 57 + 19 = 76 operations
  r *= x10111
  r.square_repeated(9)
  r *= x10011
  r.square_repeated(7)
  r *= x1101

  # 76 + 33 = 109 operations
  r.square_repeated(14)
  r *= x1010011
  r.square_repeated(9)
  r *= x11100001
  r.square_repeated(8)

  # 109 + 18 = 127 operations
  r *= x1000001
  r.square_repeated(10)
  r *= x1011011
  r.square_repeated(5)
  r *= x1101

  # 127 + 34 = 161 operations
  r.square_repeated(8)
  r *= x11
  r.square_repeated(12)
  r *= x101011
  r.square_repeated(12)

  # 161 + 25 = 186 operations
  r *= x10111011
  r.square_repeated(8)
  r *= x101111
  r.square_repeated(14)
  r *= x10110101

  # 186 + 28 = 214
  r.square_repeated(9)
  r *= x10010001
  r.square_repeated(5)
  r *= x1101
  r.square_repeated(12)

  # 214 + 22 = 236
  r *= x11100011
  r.square_repeated(8)
  r *= x10010101
  r.square_repeated(11)
  r *= x11010011

  # 236 + 32 = 268
  r.square_repeated(7)
  r *= x1100001
  r.square_repeated(11)
  r *= x100011
  r.square_repeated(12)

  # 268 + 20 = 288
  r *= x1011011
  r.square_repeated(9)
  r *= x11000011
  r.square_repeated(8)
  r *= x11100111

  # 288 + 13 = 301
  r.square_repeated(7)
  r *= x1110101
  r.square_repeated(4)
  r *= a
