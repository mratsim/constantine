# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  ../primitives,
  ../config/curves,
  ../arithmetic,
  ../towers,
  ./lines_projective


# ############################################################
#
#                 Sparse Multiplication
#                        by lines
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

# 𝔽p12 by line - Sparse functions
# ----------------------------------------------------------------

func mul_by_line_xy0*[C: static Curve](
       r: var Fp6[C],
       a: Fp6[C],
       b: Line[Fp2[C]]) =
  ## Sparse multiplication of an 𝔽p6
  ## with coordinates (a₀, a₁, a₂) by a line (x, y, 0)
  ## The z coordinates in the line will be ignored.
  ## `r` and `a` must not alias
  var
    v0 {.noInit.}: Fp2[C]
    v1 {.noInit.}: Fp2[C]

  v0.prod(a.c0, b.x)
  v1.prod(a.c1, b.y)
  r.c0.prod(a.c2, b.y)
  r.c0 *= SexticNonResidue
  r.c0 += v0

  r.c1.sum(a.c0, a.c1) # Error when r and a alias as r.c0 was updated
  r.c2.sum(b.x, b.y)
  r.c1 *= r.c2
  r.c1 -= v0
  r.c1 -= v1

  r.c2.prod(a.c2, b.x)
  r.c2 += v1

func mul_sparse_by_line_xy00z0*[C: static Curve](
      f: var Fp12[C], l: Line[Fp2[C]]) =
  ## Sparse multiplication of an 𝔽p12 element
  ## by a sparse 𝔽p12 element coming from an D-Twist line function.
  ## The sparse element is represented by a packed Line type
  ## with coordinate (x,y,z) matching 𝔽p12 coordinates xy00z0 (TODO: verify this)

  static:
    doAssert C.getSexticTwist() == D_Twist
    doAssert f.c0.typeof is Fp6, "This assumes 𝔽p12 as a quadratic extension of 𝔽p6"

  var
    v0 {.noInit.}: Fp6[C]
    v1 {.noInit.}: Fp6[C]
    v2 {.noInit.}: Line[Fp2[C]]
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

  v3.c0.prod(v1.c2, SexticNonResidue)
  v3.c0 += v0.c0
  v3.c1.sum(v0.c1, v1.c0)
  v3.c2.sum(v0.c2, v1.c1)
  f.c0 = v3

func mul_sparse_by_line_xyz000*[C: static Curve](
       f: var Fp12[C], l: Line[Fp2[C]]) =
  ## Sparse multiplication of an 𝔽p12 element
  ## by a sparse 𝔽p12 element coming from an D-Twist line function.
  ## The sparse element is represented by a packed Line type
  ## with coordinates (x,y,z) matching 𝔽p12 coordinates xyz000

  static:
    doAssert C.getSexticTwist() == D_Twist
    doAssert f.c0.typeof is Fp4, "This assumes 𝔽p12 as a cubic extension of 𝔽p4"

  # In the following equations (taken from cubic extension implementation)
  # a = f
  # b0 = (x, y)
  # b1 = (z, 0)
  # b2 = (0, 0)
  #
  # v0 = a0 b0 = (f00, f01).(x, y)
  # v1 = a1 b1 = (f10, f11).(z, 0)
  # v2 = a2 b2 = (f20, f21).(0, 0)
  #
  # r0 = ξ ((a1 + a2) * (b1 + b2) - v1 - v2) + v0
  #    = ξ (a1 b1 + a2 b1 - v1) + v0
  #    = ξ a2 b1 + v0
  # r1 = (a0 + a1) * (b0 + b1) - v0 - v1 + ξ v2
  #    = (a0 + a1) * (b0 + b1) - v0 - v1
  # r2 = (a0 + a2) * (b0 + b2) - v0 - v2 + v1
  #    = a0 b0 + a2 b0 - v0 + v1
  #    = a2 b0 + v1

  var b0 {.noInit.}, v0{.noInit.}, v1{.noInit.}, t{.noInit.}: Fp4[C]

  b0.c0 = l.x
  b0.c1 = l.y

  v0.prod(f.c0, b0)
  v1.mul_sparse_by_y0(f.c1, l.z)

  # r1 = (a0 + a1) * (b0 + b1) - v0 - v1
  f.c1 += f.c0 # r1 = a0 + a1
  t = b0
  t.c0 += l.z  # t = b0 + b1
  f.c1 *= t    # r2 = (a0 + a1)(b0 + b1)
  f.c1 -= v0
  f.c1 -= v1   # r2 = (a0 + a1)(b0 + b1) - v0 - v1

  # r0 = ξ a2 b1 + v0
  f.c0.mul_sparse_by_y0(f.c2, l.z)
  f.c0 *= SexticNonResidue
  f.c0 += v0

  # r2 = a2 b0 + v1
  f.c2 *= b0
  f.c2 += v1

func mul_sparse_by_line_xy000z*[C: static Curve](
       f: var Fp12[C], l: Line[Fp2[C]]) =

  static:
    doAssert C.getSexticTwist() == M_Twist
    doAssert f.c0.typeof is Fp4, "This assumes 𝔽p12 as a cubic extension of 𝔽p4"

  # In the following equations (taken from cubic extension implementation)
  # a = f
  # b0 = (x, y)
  # b1 = (0, 0)
  # b2 = (0, z)
  #
  # v0 = a0 b0 = (f00, f01).(x, y)
  # v1 = a1 b1 = (f10, f11).(0, 0)
  # v2 = a2 b2 = (f20, f21).(0, z)
  #
  # r0 = ξ ((a1 + a2) * (b1 + b2) - v1 - v2) + v0
  #    = ξ (a1 b2 + a2 b2 - v2) + v0
  #    = ξ a1 b2 + v0
  # r1 = (a0 + a1) * (b0 + b1) - v0 - v1 + ξ v2
  #    = a0 b0 + a1 b0 - v0 + ξ v2
  #    = a1 b0 + ξ v2
  # r2 = (a0 + a2) * (b0 + b2) - v0 - v2 + v1
  #    = (a0 + a2) * (b0 + b2) - v0 - v2

  var b0 {.noInit.}, v0{.noInit.}, v2{.noInit.}, t{.noInit.}: Fp4[C]

  b0.c0 = l.x
  b0.c1 = l.y

  v0.prod(f.c0, b0)
  v2.mul_sparse_by_0y(f.c2, l.z)

  # r2 = (a0 + a2) * (b0 + b2) - v0 - v2
  f.c2 += f.c0 # r2 = a0 + a2
  t = b0
  t.c1 += l.z  # t = b0 + b2
  f.c2 *= t    # r2 = (a0 + a2)(b0 + b2)
  f.c2 -= v0
  f.c2 -= v2   # r2 = (a0 + a2)(b0 + b2) - v0 - v2

  # r0 = ξ a1 b2 + v0
  f.c0.mul_sparse_by_0y(f.c1, l.z)
  f.c0 *= SexticNonResidue
  f.c0 += v0

  # r1 = a1 b0 + ξ v2
  f.c1 *= b0
  v2 *= SexticNonResidue
  f.c1 += v2

func mul*[C](f: var Fp12[C], line: Line[Fp2[C]]) {.inline.} =
  when C.getSexticTwist() == D_Twist:
    f.mul_sparse_by_line_xyz000(line)
  elif C.getSexticTwist() == M_Twist:
    f.mul_sparse_by_line_xy000z(line)
  else:
    {.error: "A line function assumes that the curve has a twist".}
