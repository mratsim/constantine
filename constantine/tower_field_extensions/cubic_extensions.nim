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

func square_Chung_Hasan_SQR2(r: var CubicExt, a: CubicExt) {.used.}=
  ## Returns r = a²
  mixin prod, square, sum
  var s0{.noInit.}, m01{.noInit.}, m12{.noInit.}: typeof(r.c0)

  # precomputations that use a
  m01.prod(a.c0, a.c1)
  m01.double()
  m12.prod(a.c1, a.c2)
  m12.double()
  s0.square(a.c2)
  # aliasing: a₂ unused

  # r₂ = (a₀ - a₁ + a₂)²
  r.c2.sum(a.c2, a.c0)
  r.c2 -= a.c1
  r.c2.square()
  # aliasing, a almost unneeded now

  # r₂ = (a₀ - a₁ + a₂)² + 2a₀a₁ + 2a₁a₂ - a₂²
  r.c2 += m01
  r.c2 += m12
  r.c2 -= s0

  # r₁ = 2a₀a₁ + β a₂²
  r.c1.prod(s0, NonResidue)
  r.c1 += m01

  # r₂ = (a₀ - a₁ + a₂)² + 2a₀a₁ + 2a₁a₂ - a₀² - a₂²
  s0.square(a.c0)
  r.c2 -= s0

  # r₀ = a₀² + β 2a₁a₂
  r.c0.prod(m12, NonResidue)
  r.c0 += s0

func square_Chung_Hasan_SQR3(r: var CubicExt, a: CubicExt) =
  ## Returns r = a²
  mixin prod, square, sum
  var s0{.noInit.}, t{.noInit.}, m12{.noInit.}: typeof(r.c0)

  # s₀ = (a₀ + a₁ + a₂)²
  # t = ((a₀ + a₁ + a₂)² + (a₀ - a₁ + a₂)²) / 2
  s0.sum(a.c0, a.c2)
  t.diff(s0, a.c1)
  s0 += a.c1
  s0.square()
  t.square()
  t += s0
  t.div2()

  # m12 = 2a₁a₂ and r₁ = a₂²
  # then a₁ and a₂ are unused for aliasing
  m12.prod(a.c1, a.c2)
  m12.double()
  r.c1.square(a.c2)       # r₁ = a₂²

  r.c2.diff(t, r.c1)      # r₂ = t - a₂²
  r.c1 *= NonResidue      # r₁ = β a₂²
  r.c1 += s0              # r₁ = (a₀ + a₁ + a₂)² + β a₂²
  r.c1 -= m12             # r₁ = (a₀ + a₁ + a₂)² - 2a₁a₂ + β a₂²
  r.c1 -= t               # r₁ = (a₀ + a₁ + a₂)² - 2a₁a₂ - t + β a₂²

  s0.square(a.c0)
  # aliasing: a₀ unused

  r.c2 -= s0
  r.c0.prod(m12, NonResidue)
  r.c0 += s0

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
  t.prod(v2, NonResidue)
  r.c1 += t

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
  v3.prod(a.c2, NonResidue)
  r.c1.prod(v1, v3)
  v3.prod(a.c1, NonResidue)
  r.c2.prod(v2, v3)
  v3.prod(r.c0, a.c0)
  v3 += r.c1
  v3 += r.c2

  let t = v3 # TODO, support aliasing in all primitives
  v3.inv(t)

  # (a0 + a1 v + a2 v²)^-1 = (A + B v + C v²) / F
  r.c0 *= v3
  r.c1.prod(v1, v3)
  r.c2.prod(v2, v3)

func inv*(a: var CubicExt) =
  ## Compute the multiplicative inverse of ``a``
  ##
  ## The inverse of 0 is 0.
  ## Incidentally this avoids extra check
  ## to convert Jacobian and Projective coordinates
  ## to affine for elliptic curve
  let t = a
  a.inv(t)

func `*=`*(a: var CubicExt, b: CubicExt) {.inline.} =
  ## In-place multiplication
  # On higher extension field like 𝔽p6,
  # if `prod` is called on shared in and out buffer, the result is wrong
  let t = a
  a.prod(t, b)

func conj*(a: var CubicExt) {.inline.} =
  ## Computes the conjugate in-place
  mixin conj, conjneg
  a.c0.conj()
  a.c1.conjneg()
  a.c2.conj()

func conj*(r: var CubicExt, a: CubicExt) {.inline.} =
  ## Computes the conjugate out-of-place
  mixin conj, conjneg
  r.c0.conj(a.c0)
  r.c1.conjneg(a.c1)
  r.c2.conj(a.c2)

func square*(a: var CubicExt) {.inline.} =
  ## In-place squaring
  a.square(a)
