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
#           Specialized inversion for BLS12-381
#
# ############################################################

func inv_addchain*(r: var Fp[Curve25519], a: Fp[Curve25519]) =
  var
    x10       {.noinit.}: Fp[Curve25519]
    x1001     {.noinit.}: Fp[Curve25519]
    x1011     {.noinit.}: Fp[Curve25519]

  x10       .square(a)               # 2
  x1001     .square_repeated(x10, 2) # 8
  x1001     *= a                     # 9
  x1011     .prod(x10, x1001)        # 11
  # 5 operations

  # TODO: we can accumulate in a partially reduced
  #       doubled-size `r` to avoid the final substractions.
  #       and only reduce at the end.
  #       This requires the number of op to be less than log2(p) == 255

  template t: untyped = x10
  
  t.square(x1011)              # 22
  r.prod(t, x1001)             # 31 = 2⁵-1

  template u: untyped = x1001

  t.square_repeated(r, 5)
  r *= t                       # 2¹⁰-1
  t.square_repeated(r, 10)
  t *= r                       # 2²⁰-1

  u.square_repeated(t, 20)
  t *= u                       # 2⁴⁰-1
  t.square_repeated(10)
  t *= r                       # 2⁵⁰-1
  r.square_repeated(t, 50)
  r *= t                       # 2¹⁰⁰-1
  
  u.square_repeated(r, 100)
  r *= u                       # 2²⁰⁰-1
  r.square_repeated(50)
  r *= t                       # 2²⁵⁰-1
  r.square_repeated(5)
  r *= x1011                   # 2²⁵⁵-21 (note: 11 = 2⁵-21)
