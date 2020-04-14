# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  ../arithmetic,
  ../primitives,
  ./tower_common

# Commutative ring implementation for Cubic Extension Fields
# -------------------------------------------------------------------

func square*(r: var CubicExt, a: CubicExt) =
  ## Returns r = a²
  # Algorithm is Chung-Hasan Squaring SQR2
  # http://cacr.uwaterloo.ca/techreports/2006/cacr2006-24.pdf
  # https://www.lirmm.fr/arith18/papers/Chung-Squaring.pdf
  #
  # Cost in base field operation
  # M -> Mul, S -> Square, B -> Bitshift (doubling/div2), A -> Add
  #
  # SQR1:        3M + 2S + 5B + 9A
  # SQR2:        2M + 3S + 5B + 11A
  # SQR3:        1M + 4S + 6B + 15A
  # Schoolbook:  3S + 3M + 6B + 2A
  #
  # TODO: Implement all variants, bench and select one depending on number of limbs and extension degree.
  mixin prod, square, sum
  var v3{.noInit.}, v4{.noInit.}, v5{.noInit.}: typeof(r.c0)

  v4.prod(a.c0, a.c1)
  v4.double()
  v5.square(a.c2)
  r.c1 = β * v5
  r.c1 += v4
  r.c2.diff(v4, v5)
  v3.square(a.c0)
  v4.diff(a.c0, a.c1)
  v4 += a.c2
  v5.prod(a.c1, a.c2)
  v5.double()
  v4.square()
  r.c0 = β * v5
  r.c0 += v3
  r.c2 += v4
  r.c2 += v5
  r.c2 -= v3

func prod*(r: var CubicExt, a, b: CubicExt) =
  ## Returns r = a * b
  ##
  ## r MUST not share a buffer with a
  # Algorithm is Karatsuba
  var v0{.noInit.}, v1{.noInit.}, v2{.noInit.}, t{.noInit.}: typeof(r.c0)

  v0.prod(a.c0, b.c0)
  v1.prod(a.c1, b.c1)
  v2.prod(a.c2, b.c2)

  # r.c0 = β ((a.c1 + a.c2) * (b.c1 + b.c2) - v1 - v2) + v0
  r.c0.sum(a.c1, a.c2)
  t.sum(b.c1, b.c2)
  r.c0 *= t
  r.c0 -= v1
  r.c0 -= v2
  r.c0 *= β
  r.c0 += v0

  # r.c1 = (a.c0 + a.c1) * (b.c0 + b.c1) - v0 - v1 + β v2
  r.c1.sum(a.c0, a.c1)
  t.sum(b.c0, b.c1)
  r.c1 *= t
  r.c1 -= v0
  r.c1 -= v1
  r.c1 += β * v2

  # r.c2 = (a.c0 + a.c2) * (b.c0 + b.c2) - v0 - v2 + v1
  r.c2.sum(a.c0, a.c2)
  t.sum(b.c0, b.c2)
  r.c2 *= t
  r.c2 -= v0
  r.c2 -= v2
  r.c2 += v1

func inv*(r: var CubicExt, a: CubicExt) =
  ## Compute the multiplicative inverse of ``a``
  ##
  ## The inverse of 0 is 0.
  ## Incidentally this avoids extra check
  ## to convert Jacobian and Projective coordinates
  ## to affine for elliptic curve
  #
  # Algorithm 5.23
  #
  # Arithmetic of Finite Fields
  # Chapter 5 of Guide to Pairing-Based Cryptography
  # Jean Luc Beuchat, Luis J. Dominguez Perez, Sylvain Duquesne, Nadia El Mrabet, Laura Fuentes-Castañeda, Francisco Rodríguez-Henríquez, 2017\
  # https://www.researchgate.net/publication/319538235_Arithmetic_of_Finite_Fields
  #
  # We optimize for stack usage and use 4 temporaries (+r as temporary)
  # instead of 9, because 5 * 2 (𝔽p2) * Bitsize would be:
  # - ~2540 bits for BN254
  # - ~3810 bits for BLS12-381
  var v1 {.noInit.}, v2 {.noInit.}, v3 {.noInit.}: typeof(r.c0)

  # A in r0
  # A <- a0² - β a1 a2
  r.c0.square(a.c0)
  v1.prod(a.c1, a.c2)
  v1 *= β
  r.c0 -= v1

  # B in v1
  # B <- β a2² - a0 a1
  v1.square(a.c2)
  v1 *= β
  v2.prod(a.c0, a.c1)
  v1 -= v2

  # C in v2
  # C <- a1² - a0 a2
  v2.square(a.c1)
  v3.prod(a.c0, a.c2)
  v2 -= v3

  # F in v3
  # F <- β a1 C + a0 A + β a2 B
  r.c1.prod(v1, β * a.c2)
  r.c2.prod(v2, β * a.c1)
  v3.prod(r.c0, a.c0)
  v3 += r.c1
  v3 += r.c2

  v3.inv(v3)

  # (a0 + a1 v + a2 v²)^-1 = (A + B v + C v²) / F
  r.c0 *= v3
  r.c1.prod(v1, v3)
  r.c2.prod(v2, v3)

func `*=`*(a: var CubicExt, b: CubicExt) {.inline.} =
  ## In-place multiplication
  # On higher extension field like 𝔽p6,
  # if `prod` is called on shared in and out buffer, the result is wrong
  let t = a
  a.prod(t, b)
