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

func invsqrt_addchain*(r: var Fp[BN254_Nogami], a: Fp[BN254_Nogami]) {.addchain.} =
  var
    x10 {.noInit.}: Fp[BN254_Nogami]
    x11 {.noInit.}: Fp[BN254_Nogami]

  x10 .square(a)
  x11 .prod(a, x10)
  # 2 operations

  var
    r10  {.noInit.}: Fp[BN254_Nogami]
    r14  {.noInit.}: Fp[BN254_Nogami]
    r15  {.noInit.}: Fp[BN254_Nogami]
    r20  {.noInit.}: Fp[BN254_Nogami]
    r23  {.noInit.}: Fp[BN254_Nogami]
    r24  {.noInit.}: Fp[BN254_Nogami]
    r25  {.noInit.}: Fp[BN254_Nogami]
    r33  {.noInit.}: Fp[BN254_Nogami]
    r35  {.noInit.}: Fp[BN254_Nogami]
    r36  {.noInit.}: Fp[BN254_Nogami]
    r37  {.noInit.}: Fp[BN254_Nogami]

  r10.square_repeated(x11, 7)
  r10 *= x11

  r14.square(r10)
  r14 *= r10
  r14.square_repeated(2)

  r15.prod(r10, r14)

  r20.square_repeated(r15, 3)
  r20 *= r15
  r20 *= r14

  r23.square_repeated(r20, 2)
  r23 *= r20

  r24.prod(r20, r23)
  r25.prod(r23, r24)

  r33.square(r25)
  r33 *= r25
  r33.square_repeated(2)
  r33 *= r25
  r33.square_repeated(3)

  r35.prod(r25, r33)
  r35 *= r24

  r36.square(r35)
  r37.prod(r35, r36)

  r.prod(r36, r37)
  r.square_repeated(3)
  r *= r37
  r.square_repeated(55)
  r *= r35

  r.square_repeated(55)
  r *= r25
  r.square_repeated(56)
  r *= r15
  r.square_repeated(52)

  r *= a
  r.square_repeated(2)

  # Total 265 operations
