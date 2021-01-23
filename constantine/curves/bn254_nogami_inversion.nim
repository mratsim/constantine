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
#           Specialized inversion for BN254-Nogami
#
# ############################################################

func inv_addchain*(r: var Fp[BN254_Nogami], a: Fp[BN254_Nogami]) =
  var
    x100     {.noInit.}: Fp[BN254_Nogami]
    x1000    {.noInit.}: Fp[BN254_Nogami]
    x1100    {.noInit.}: Fp[BN254_Nogami]
    x1101    {.noInit.}: Fp[BN254_Nogami]
    x10001   {.noInit.}: Fp[BN254_Nogami]
    x100010  {.noInit.}: Fp[BN254_Nogami]
    x1000100 {.noInit.}: Fp[BN254_Nogami]
    x1010101 {.noInit.}: Fp[BN254_Nogami]

  x100     .square_repeated(a, 2)
  x1000    .square(x100)
  x1100    .prod(x100, x1000)
  x1101    .prod(a, x1100)
  x10001   .prod(x100, x1101)
  x100010  .square(x10001)
  x1000100 .square(x100010)
  x1010101 .prod(x10001, x1000100)
  # 9 operations

  var
    r13      {.noInit.}: Fp[BN254_Nogami]
    r17      {.noInit.}: Fp[BN254_Nogami]
    r18      {.noInit.}: Fp[BN254_Nogami]
    r23      {.noInit.}: Fp[BN254_Nogami]
    r26      {.noInit.}: Fp[BN254_Nogami]
    r27      {.noInit.}: Fp[BN254_Nogami]
    r28      {.noInit.}: Fp[BN254_Nogami]
    r36      {.noInit.}: Fp[BN254_Nogami]
    r38      {.noInit.}: Fp[BN254_Nogami]
    r39      {.noInit.}: Fp[BN254_Nogami]
    r40      {.noInit.}: Fp[BN254_Nogami]

  r13.square_repeated(x1010101, 2)
  r13 *= x100010
  r13 *= x1101

  r17.square(r13)
  r17 *= r13
  r17.square_repeated(2)

  r18.prod(r13, r17)

  r23.square_repeated(r18, 3)
  r23 *= r18
  r23 *= r17

  r26.square_repeated(r23, 2)
  r26 *= r23

  r27.prod(r23, r26)
  r28.prod(r26, r27)

  r36.square(r28)
  r36 *= r28
  r36.square_repeated(2)
  r36 *= r28
  r36.square_repeated(3)

  r38.prod(r28, r36)
  r38 *= r27
  r39.square(r38)
  r40.prod(r38, r39)

  r.prod(r39, r40)
  r.square_repeated(3)
  r *= r40
  r.square_repeated(55)
  r *= r38

  r.square_repeated(55)
  r *= r28
  r.square_repeated(56)
  r *= r18
  r.square_repeated(56)

  r *= x10001

  # Total 271 operations
