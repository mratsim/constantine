# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  ../primitives,
  ../config/[common, curves],
  ../arithmetic,
  ../towers,
  ./lines_projective

# ############################################################
#
#                 Sparse Multiplication
#                and cyclotomic squaring
#              for elements of Gₜ = E(Fp¹²)
#
# ############################################################

# - Pairing Implementation Revisited
#   Michael Scott, 2019
#   https://eprint.iacr.org/2019/077
#
# - Efficient Implementation of Bilinear Pairings on ARM Processors
#   Gurleen Grewal, Reza Azarderakhsh,
#   Patrick Longa, Shi Hu, and David Jao, 2012
#   https://eprint.iacr.org/2012/408.pdf
#
# - High-Speed Software Implementation of the Optimal Ate Pairing over Barreto-Naehrig Curves\
#   Jean-Luc Beuchat and Jorge Enrique González Díaz and Shigeo Mitsunari and Eiji Okamoto and Francisco Rodríguez-Henríquez and Tadanori Teruya, 2010\
#   https://eprint.iacr.org/2010/354
#
# - Faster Pairing Computations on Curves with High-Degree Twists
#   Craig Costello, Tanja Lange, and Michael Naehrig, 2009
#   https://eprint.iacr.org/2009/615.pdf

# TODO: we assume an embedding degree k of 12 and a sextic twist.
#       -> Generalize to KSS (k=18), BLS24 and BLS48 curves
#
# TODO: we assume a 2-3-2 towering scheme
#
# TODO: merge that in the quadratic/cubic files

# 𝔽p12 - Sparse functions
# ----------------------------------------------------------------

func mul_sparse_by_0y0*[C: static Curve](r: var Fp6[C], a: Fp6[C], b: Fp2[C]) =
  ## Sparse multiplication of an Fp6 element
  ## with coordinates (a₀, a₁, a₂) by (0, b₁, 0)
  # TODO: make generic and move to tower_field_extensions

  # v0 = a0 b0 = 0
  # v1 = a1 b1
  # v2 = a2 b2 = 0
  #
  # r0 = ξ ((a1 + a2) * (b1 + b2) - v1 - v2) + v0
  #    = ξ (a1 b1 + a2 b1 - v1)
  #    = ξ a2 b1
  # r1 = (a0 + a1) * (b0 + b1) - v0 - v1 + β v2
  #    = a0 b1 + a1 b1 - v1
  #    = a0 b1
  # r2 = (a0 + a2) * (b0 + b2) - v0 - v2 + v1
  #    = v1
  #    = a1 b1

  r.c0.prod(a.c2, b)
  r.c0 *= ξ
  r.c1.prod(a.c0, b)
  r.c2.prod(a.c1, b)

func mul_by_line_xy0*[C: static Curve, twist: static SexticTwist](
       r: var Fp6[C],
       a: Fp6[C],
       b: Line[Fp2[C], twist]) =
  ## Sparse multiplication of an Fp6
  ## with coordinates (a₀, a₁, a₂) by a line (x, y, 0)
  ## The z coordinates in the line will be ignored.
  ## `r` and `a` must not alias
  var
    v0 {.noInit.}: Fp2[C]
    v1 {.noInit.}: Fp2[C]

  v0.prod(a.c0, b.x)
  v1.prod(a.c1, b.y)
  r.c0.prod(a.c2, b.y)
  r.c0 *= ξ
  r.c0 += v0

  r.c1.sum(a.c0, a.c1) # Error when r and a alias as r.c0 was updated
  r.c2.sum(b.x, b.y)
  r.c1 *= r.c2
  r.c1 -= v0
  r.c1 -= v1

  r.c2.prod(a.c2, b.x)
  r.c2 += v1

func mul_sparse_by_line*[C: static Curve](f: var FP12[C], l: Line[Fp2[C], M_Twist]) =
  ## Sparse multiplication of an FP12 element
  ## by a sparse FP12 element coming from an M-Twist line function.
  ## The sparse element is represented by a packed Line type
  ## with coordinate (x,y,z) matching Fp12 coordinates xy00z0

  var
    v0 {.noInit.}: Fp6[C]
    v1 {.noInit.}: Fp6[C]
    v2 {.noInit.}: Line[Fp2[C], M_Twist]
    v3 {.noInit.}: Fp6[C]

  v0.mul_by_line_xy0(f.c0, l)
  v1.mul_sparse_by_0y0(f.c1, l.z)

  v2.x = l.x
  v2.y.sum(l.y, l.z)
  f.c1 += f.c0
  v3.mul_by_line_xy0(f.c1, v2)
  v3 -= v0
  v3 -= v1
  f.c1 = v3

  v3.c0 = ξ * v1.c2
  v3.c0 += v0.c0
  v3.c1.sum(v0.c1, v1.c0)
  v3.c2.sum(v0.c2, v1.c1)
  f.c0 = v3

# Gₜ = 𝔽p12 - Cyclotomic functions
# ----------------------------------------------------------------
# A cyclotomic group is a subgroup of Fp^n defined by
#
# GΦₙ(p) = {α ∈ Fpⁿ : α^Φₙ(p) = 1}
#
# The result of any pairing is in a cyclotomic subgroup
