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

# 𝔽p6 by line - Sparse functions
# ----------------------------------------------------------------

func mul_sparse_by_line_xyz000*[C: static Curve](
       f: var Fp6[C], l: Line[Fp[C]]) =
  ## Sparse multiplication of an 𝔽p12 element
  ## by a sparse 𝔽p12 element coming from an D-Twist line function.
  ## The sparse element is represented by a packed Line type
  ## with coordinates (x,y,z) matching 𝔽p12 coordinates xyz000

  static:
    doAssert C.getSexticTwist() == D_Twist
    doAssert f.c0.typeof is Fp2, "This assumes 𝔽p6 as a cubic extension of 𝔽p6"

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

  var b0 {.noInit.}, v0{.noInit.}, v1{.noInit.}, t{.noInit.}: Fp2[C]

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
  f.c0 *= NonResidue
  f.c0 += v0

  # r2 = a2 b0 + v1
  f.c2 *= b0
  f.c2 += v1

func mul_sparse_by_line_xy000z*[C: static Curve](
       f: var Fp6[C], l: Line[Fp[C]]) =

  static:
    doAssert C.getSexticTwist() == M_Twist
    doAssert f.c0.typeof is Fp2, "This assumes 𝔽p6 as a cubic extension of 𝔽p2"

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

  var b0 {.noInit.}, v0{.noInit.}, v2{.noInit.}, t{.noInit.}: Fp2[C]

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
  f.c0 *= NonResidue
  f.c0 += v0

  # r1 = a1 b0 + ξ v2
  f.c1 *= b0
  v2 *= NonResidue
  f.c1 += v2

func mul*[C](f: var Fp6[C], line: Line[Fp[C]]) {.inline.} =
  when C.getSexticTwist() == D_Twist:
    f.mul_sparse_by_line_xyz000(line)
  elif C.getSexticTwist() == M_Twist:
    f.mul_sparse_by_line_xy000z(line)
  else:
    {.error: "A line function assumes that the curve has a twist".}
