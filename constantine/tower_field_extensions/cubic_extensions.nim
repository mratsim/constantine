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
# Cubic extensions can use specific squaring procedures
# beyond Schoolbook and Karatsuba:
# - Chung-Hasan (3 different algorithms)
# - Toom-Cook-3x
#
# Chung-Hasan papers
# http://cacr.uwaterloo.ca/techreports/2006/cacr2006-24.pdf
# https://www.lirmm.fr/arith18/papers/Chung-Squaring.pdf
#
# The papers focus on polynomial squaring, they have been adapted
# to towered extension fields with the relevant costs in
#
# - Multiplication and Squaring on Pairing-Friendly Fields
#   Augusto Jun Devegili and Colm Ó hÉigeartaigh and Michael Scott and Ricardo Dahab, 2006
#   https://eprint.iacr.org/2006/471
#
# Costs in the underlying field
# M: Mul, S: Square, A: Add/Sub, B: Mul by non-residue
#
# | Method      | > Linear | Linear            |
# |-------------|----------|-------------------|
# | Schoolbook  | 3M + 3S  | 6A + 2B           |
# | Karatsuba   | 6S       | 13A + 2B          |
# | Tom-Cook-3x | 5S       | 33A + 2B          |
# | CH-SQR1     | 3M + 2S  | 11A + 2B          |
# | CH-SQR2     | 2M + 3S  | 10A + 2B          |
# | CH-SQR3     | 1M + 4S  | 11A + 2B + 1 Div2 |
# | CH-SQR3x    | 1M + 4S  | 14A + 2B          |

func square_Chung_Hasan_SQR2(r: var CubicExt, a: CubicExt) =
  ## Returns r = a²
  mixin prod, square, sum
  var v3{.noInit.}, v4{.noInit.}, v5{.noInit.}: typeof(r.c0)

  v4.prod(a.c0, a.c1)
  v4.double()
  v5.square(a.c2)
  r.c1 = NonResidue * v5
  r.c1 += v4
  r.c2.diff(v4, v5)
  v3.square(a.c0)
  v4.diff(a.c0, a.c1)
  v4 += a.c2
  v5.prod(a.c1, a.c2)
  v5.double()
  v4.square()
  r.c0 = NonResidue * v5
  r.c0 += v3
  r.c2 += v4
  r.c2 += v5
  r.c2 -= v3

func square_Chung_Hasan_SQR3(r: var CubicExt, a: CubicExt) =
  ## Returns r = a²
  mixin prod, square, sum
  var v0{.noInit.}, v2{.noInit.}: typeof(r.c0)

  r.c1.sum(a.c0, a.c2)    # r1 = a0 + a2
  v2.diff(r.c1, a.c1)     # v2 = a0 - a1 + a2
  r.c1 += a.c1            # r1 = a0 + a1 + a2
  r.c1.square()           # r1 = (a0 + a1 + a2)²
  v2.square()             # v2 = (a0 - a1 + a2)²

  r.c2.sum(r.c1, v2)      # r2 = (a0 + a1 + a2)² + (a0 - a1 + a2)²
  r.c2.div2()             # r2 = ((a0 + a1 + a2)² + (a0 - a1 + a2)²)/2

  r.c0.prod(a.c1, a.c2)   # r0 = a1 a2
  r.c0.double()           # r0 = 2 a1 a2

  v2.square(a.c2)         # v2 = a2²
  r.c1 += NonResidue * v2 # r1 = (a0 + a1 + a2)² + β a2²
  r.c1 -= r.c0            # r1 = (a0 + a1 + a2)² - 2 a1 a2 + β a2²
  r.c1 -= r.c2            # r1 = (a0 + a1 + a2)² - 2 a1 a2 - ((a0 + a1 + a2)² + (a0 - a1 + a2)²)/2 + β a2²

  v0.square(a.c0)         # v0 = a0²
  r.c0 *= NonResidue      # r0 = β 2 a1 a2
  r.c0 += v0              # r0 = a0² + β 2 a1 a2

  r.c2 -= v0              # r2 = ((a0 + a1 + a2)² + (a0 - a1 + a2)²)/2 - a0²
  r.c2 -= v2              # r2 = ((a0 + a1 + a2)² + (a0 - a1 + a2)²)/2 - a0² - a2²

func square*(r: var CubicExt, a: CubicExt) {.inline.} =
  ## Returns r = a²
  square_Chung_Hasan_SQR3(r, a)

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
  r.c0 *= NonResidue
  r.c0 += v0

  # r.c1 = (a.c0 + a.c1) * (b.c0 + b.c1) - v0 - v1 + β v2
  r.c1.sum(a.c0, a.c1)
  t.sum(b.c0, b.c1)
  r.c1 *= t
  r.c1 -= v0
  r.c1 -= v1
  r.c1 += NonResidue * v2

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
  v1 *= NonResidue
  r.c0 -= v1

  # B in v1
  # B <- β a2² - a0 a1
  v1.square(a.c2)
  v1 *= NonResidue
  v2.prod(a.c0, a.c1)
  v1 -= v2

  # C in v2
  # C <- a1² - a0 a2
  v2.square(a.c1)
  v3.prod(a.c0, a.c2)
  v2 -= v3

  # F in v3
  # F <- β a1 C + a0 A + β a2 B
  r.c1.prod(v1, NonResidue * a.c2)
  r.c2.prod(v2, NonResidue * a.c1)
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
