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

# No exceptions allowed
{.push raises: [].}

# ############################################################
#
#                 Sparse Multiplication
#             by lines for embedding degree 12
#                   and sextic twist
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

# ############################################################
#
#            𝔽p12 by line - 𝔽p12 quadratic over 𝔽p6
#
# ############################################################

# D-Twist
# ------------------------------------------------------------

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
    doAssert f.c0 is Fp6, "This assumes 𝔽p12 as a quadratic extension of 𝔽p6"

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
  f.c1.diff(v3, v1)

  v3.c0.prod(v1.c2, SexticNonResidue)
  v3.c0 += v0.c0
  v3.c1.sum(v0.c1, v1.c0)
  v3.c2.sum(v0.c2, v1.c1)
  f.c0 = v3

# ############################################################
#
#            𝔽p12 by line - 𝔽p12 cubic over 𝔽p4
#
# ############################################################

# D-Twist
# ------------------------------------------------------------

func mul_sparse_by_line_xyz000*[C: static Curve](
       f: var Fp12[C], l: Line[Fp2[C]]) =
  ## Sparse multiplication of an 𝔽p12 element
  ## by a sparse 𝔽p12 element coming from an D-Twist line function.
  ## The sparse element is represented by a packed Line type
  ## with coordinates (x,y,z) matching 𝔽p12 coordinates xyz000

  static:
    doAssert C.getSexticTwist() == D_Twist
    doAssert f.c0 is Fp4, "This assumes 𝔽p12 as a cubic extension of 𝔽p4"

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

  when false:
    var b0 {.noInit.}, v0{.noInit.}, v1{.noInit.}, t{.noInit.}: Fp4[C]

    b0.c0 = l.x
    b0.c1 = l.y

    v0.prod(f.c0, b0)
    v1.mul_sparse_by_x0(f.c1, l.z)

    # r1 = (a0 + a1) * (b0 + b1) - v0 - v1
    f.c1 += f.c0 # r1 = a0 + a1
    t = b0
    t.c0 += l.z  # t = b0 + b1
    f.c1 *= t    # r2 = (a0 + a1)(b0 + b1)
    f.c1 -= v0
    f.c1 -= v1   # r2 = (a0 + a1)(b0 + b1) - v0 - v1

    # r0 = ξ a2 b1 + v0
    f.c0.mul_sparse_by_x0(f.c2, l.z)
    f.c0 *= SexticNonResidue
    f.c0 += v0

    # r2 = a2 b0 + v1
    f.c2 *= b0
    f.c2 += v1

  else: # Lazy reduction
    var V0{.noInit.}, V1{.noInit.}, f2x{.noInit.}: doublePrec(Fp4[C])
    var t{.noInit.}: Fp2[C]

    V0.prod2x_disjoint(f.c0, l.x, l.y)
    V1.mul2x_sparse_by_x0(f.c1, l.z)

    # r1 = (a0 + a1) * (b0 + b1) - v0 - v1
    when false:                       # TODO: what's the condition?
      f.c1.sumUnr(f.c1, f.c0)
      t.sumUnr(l.x, l.z)              # b0 is (x, y)
    else:
      f.c1.sum(f.c1, f.c0)
      t.sum(l.x, l.z)                 # b0 is (x, y)
    f2x.prod2x_disjoint(f.c1, t, l.y) # b1 is (z, 0)
    f2x.diff2xMod(f2x, V0)
    f2x.diff2xMod(f2x, V1)
    f.c1.redc2x(f2x)

    # r0 = ξ a2 b1 + v0
    f2x.mul2x_sparse_by_x0(f.c2, l.z)
    f2x.prod2x(f2x, SexticNonResidue)
    f2x.sum2xMod(f2x, V0)
    f.c0.redc2x(f2x)

    # r2 = a2 b0 + v1
    f2x.prod2x_disjoint(f.c2, l.x, l.y)
    f2x.sum2xMod(f2x, V1)
    f.c2.redc2x(f2x)

func prod_xyz000_xyz000_into_abcdefghij00*[C: static Curve](f: var Fp12[C], l0, l1: Line[Fp2[C]]) =
  ## Multiply 2 lines together
  ## The result is sparse in f.c1.c1
  # In the following equations (taken from cubic extension implementation)
  # a0 = (x0, y0)
  # a1 = (z0,  0)
  # a2 = ( 0,  0)
  # b0 = (x1, y1)
  # b1 = (z1,  0)
  # b2 = ( 0,  0)
  #
  # v0 = a0 b0 = (x0, y0).(x1, y1)
  # v1 = a1 b1 = (z0,  0).(z1,  0)
  # v2 = a2 b2 = ( 0,  0).( 0,  0)
  #
  # r0 = ξ ((a1 + a2) * (b1 + b2) - v1 - v2) + v0
  #    = ξ (a1 b1 + a2 b1 - v1) + v0
  #    = v0
  # r1 = (a0 + a1) * (b0 + b1) - v0 - v1 + ξ v2
  #    = (a0 + a1) * (b0 + b1) - v0 - v1
  # r2 = (a0 + a2) * (b0 + b2) - v0 - v2 + v1
  #    = a0 b0 - v0 + v1
  #    = v1

  static:
    doAssert C.getSexticTwist() == D_Twist
    doAssert f.c0 is Fp4, "This assumes 𝔽p12 as a cubic extension of 𝔽p4"

  var V0{.noInit.}, f2x{.noInit.}: doublePrec(Fp4[C])
  var V1{.noInit.}: doublePrec(Fp2[C])

  V0.prod2x_disjoint(l0.x, l0.y, l1.x, l1.y) # a0 b0 = (x0, y0).(x1, y1)
  V1.prod2x(l0.z, l1.z)                      # a1 b1 = (z0,  0).(z1,  0)

  # r1 = (a0 + a1) * (b0 + b1) - v0 - v1
  f.c1.c0.sum(l0.x, l0.z)                           # x0 + z0
  f.c1.c1.sum(l1.x, l1.z)                           # x1 + z1
  f2x.prod2x_disjoint(f.c1.c0, l0.y, f.c1.c1, l1.y) # (x0 + z0, y0)(x1 + z1, y1) = (a0 + a1) * (b0 + b1)
  f2x.diff2xMod(f2x, V0)
  f2x.c0.diff2xMod(f2x.c0, V1)
  f.c1.redc2x(f2x)

  # r0 = v0
  f.c0.redc2x(V0)

  # r2 = v1
  f.c2.c0.redc2x(V1)
  f.c2.c1.setZero()

func mul_sparse_by_abcdefghij00*[C: static Curve](
       a: var Fp12[C], b: Fp12[C]) =
  ## Sparse multiplication of an 𝔽p12 element
  ## by a sparse 𝔽p12 element abcdefghij00
  ## with each representing 𝔽p2 coordinate

  static:
    doAssert C.getSexticTwist() == D_Twist
    doAssert a.c0 is Fp4, "This assumes 𝔽p12 as a cubic extension of 𝔽p4"

  # In the following equations (taken from cubic extension implementation)
  # b0 = (b00, b01)
  # b1 = (b10, b11)
  # b2 = (b20,   0)
  #
  # v0 = a0 b0 = (f00, f01).(b00, b01)
  # v1 = a1 b1 = (f10, f11).(b10, b11)
  # v2 = a2 b2 = (f20, f21).(b20,   0)
  #
  # r₀ = ξ ((a₁ + a₂)(b₁ + b₂) - v₁ - v₂) + v₀
  # r₁ = (a₀ + a₁) * (b₀ + b₁) - v₀ - v₁ + β v₂
  # r₂ = (a₀ + a₂) * (b₀ + b₂) - v₀ - v₂ + v₁

  var V0 {.noInit.}, V1 {.noInit.}, V2 {.noinit.}: doublePrec(Fp4[C])
  var t0 {.noInit.}, t1 {.noInit.}: Fp4[C]
  var f2x{.noInit.}, g2x {.noinit.}: doublePrec(Fp4[C])

  V0.prod2x(a.c0, b.c0)
  V1.prod2x(a.c1, b.c1)
  V2.mul2x_sparse_by_x0(a.c2, b.c2)

  # r₀ = ξ ((a₁ + a₂)(b₁ + b₂) - v₁ - v₂) + v₀
  t0.sum(a.c1, a.c2)
  t1.c0.sum(b.c1.c0, b.c2.c0)             # b₂ = (b20,   0)
  f2x.prod2x_disjoint(t0, t1.c0, b.c1.c1) # (a₁ + a₂).(b₁ + b₂)
  f2x.diff2xMod(f2x, V1)
  f2x.diff2xMod(f2x, V2)
  f2x.prod2x(f2x, NonResidue)
  f2x.sum2xMod(f2x, V0)

  # r₁ = (a₀ + a₁) * (b₀ + b₁) - v₀ - v₁
  t0.sum(a.c0, a.c1)
  t1.sum(b.c0, b.c1)
  g2x.prod2x(t0, t1)
  g2x.diff2xMod(g2x, V0)
  g2x.diff2xMod(g2x, V1)

  # r₂ = (a₀ + a₂) and (b₀ + b₂)
  t0.sum(a.c0, a.c2)
  t1.c0.sum(b.c0.c0, b.c2.c0)             # b₂ = (b20,   0)

  # Now we are aliasing free

  # r₀ = ξ ((a₁ + a₂)(b₁ + b₂) - v₁ - v₂) + v₀
  a.c0.redc2x(f2x)

  # r₁ = (a₀ + a₁) * (b₀ + b₁) - v₀ - v₁ + β v₂
  f2x.prod2x(V2, NonResidue)
  g2x.sum2xMod(g2x, f2x)
  a.c1.redc2x(g2x)

  # r₂ = (a₀ + a₂) * (b₀ + b₂) - v₀ - v₂ + v₁
  f2x.prod2x_disjoint(t0, t1.c0, b.c0.c1)
  f2x.diff2xMod(f2x, V0)
  f2x.diff2xMod(f2x, V2)
  f2x.sum2xMod(f2x, V1)
  a.c2.redc2x(f2x)

# M-Twist
# ------------------------------------------------------------

func mul_sparse_by_line_xy000z*[C: static Curve](
       f: var Fp12[C], l: Line[Fp2[C]]) =

  static:
    doAssert C.getSexticTwist() == M_Twist
    doAssert f.c0 is Fp4, "This assumes 𝔽p12 as a cubic extension of 𝔽p4"

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

  when false:
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

  else: # Lazy reduction
    var V0{.noInit.}, V2{.noInit.}, f2x{.noInit.}: doublePrec(Fp4[C])
    var t{.noInit.}: Fp2[C]

    V0.prod2x_disjoint(f.c0, l.x, l.y)
    V2.mul2x_sparse_by_0y(f.c2, l.z)

    # r2 = (a0 + a2) * (b0 + b2) - v0 - v2
    when false:                       # TODO: what's the condition
      f.c2.sumUnr(f.c2, f.c0)
      t.sumUnr(l.y, l.z)              # b0 is (x, y)
    else:
      f.c2.sum(f.c2, f.c0)
      t.sum(l.y, l.z)                 # b0 is (x, y)
    f2x.prod2x_disjoint(f.c2, l.x, t) # b2 is (0, z)
    f2x.diff2xMod(f2x, V0)
    f2x.diff2xMod(f2x, V2)
    f.c2.redc2x(f2x)

    # r0 = ξ a1 b2 + v0
    f2x.mul2x_sparse_by_0y(f.c1, l.z)
    f2x.prod2x(f2x, SexticNonResidue)
    f2x.sum2xMod(f2x, V0)
    f.c0.redc2x(f2x)

    # r1 = a1 b0 + ξ v2
    f2x.prod2x_disjoint(f.c1, l.x, l.y)
    V2.prod2x(V2, SexticNonResidue)
    f2x.sum2xMod(f2x, V2)
    f.c1.redc2x(f2x)

func prod_xy000z_xy000z_into_abcd00efghij*[C: static Curve](f: var Fp12[C], l0, l1: Line[Fp2[C]]) =
  ## Multiply 2 lines together
  ## The result is sparse in f.c1.c0
  # In the following equations (taken from cubic extension implementation)
  # a0 = (x0, y0)
  # a1 = ( 0,  0)
  # a2 = ( 0, z0)
  # b0 = (x1, y1)
  # b1 = ( 0,  0)
  # b2 = ( 0, z1)
  #
  # v0 = a0 b0 = (x0, y0).(x1, y1)
  # v1 = a1 b1 = ( 0,  0).( 0,  0)
  # v2 = a2 b2 = ( 0, z0).( 0, z1)
  #
  # r0 = ξ ((a1 + a2) * (b1 + b2) - v1 - v2) + v0
  #    = ξ (a1 b2 + a2 b2 - v2) + v0
  #    = v0
  # r1 = (a0 + a1) * (b0 + b1) - v0 - v1 + ξ v2
  #    = a0 b0 + a1 b0 - v0 + ξ v2
  #    = ξ v2
  # r2 = (a0 + a2) * (b0 + b2) - v0 - v2 + v1
  #    = (a0 + a2) * (b0 + b2) - v0 - v2

  static:
    doAssert C.getSexticTwist() == M_Twist
    doAssert f.c0 is Fp4, "This assumes 𝔽p12 as a cubic extension of 𝔽p4"

  var V0{.noInit.}, f2x{.noInit.}: doublePrec(Fp4[C])
  var V2{.noInit.}: doublePrec(Fp2[C])

  V0.prod2x_disjoint(l0.x, l0.y, l1.x, l1.y) # a0 b0 = (x0, y0).(x1, y1)
  V2.prod2x(l0.z, l1.z)                      # a2 b2 = ( 0, z0).( 0, z1)
  V2.prod2x(V2, NonResidue)

  # r2 = (a0 + a2) * (b0 + b2) - v0 - v2
  f.c2.c0.sum(l0.y, l0.z)                           # y0 + z0
  f.c2.c1.sum(l1.y, l1.z)                           # y1 + z1
  f2x.prod2x_disjoint(l0.x, f.c2.c0, l1.x, f.c2.c1) # (x0, y0 + z0).(x1, y1 + z1) = (a0 + a2) * (b0 + b2)
  f2x.diff2xMod(f2x, V0)                            # (a0 + a2) * (b0 + b2) - v0
  f2x.c0.diff2xMod(f2x.c0, V2)                      # (a0 + a2) * (b0 + b2) - v0 - v2
  f.c2.redc2x(f2x)

  # r1 = ξ v2
  f.c1.c1.redc2x(V2)
  f.c1.c0.setZero()

  # r0 = v0
  f.c0.redc2x(V0)

func mul_sparse_by_abcd00efghij*[C: static Curve](
       a: var Fp12[C], b: Fp12[C]) =
  ## Sparse multiplication of an 𝔽p12 element
  ## by a sparse 𝔽p12 element abcd00efghij
  ## with each representing 𝔽p2 coordinate

  static:
    doAssert C.getSexticTwist() == M_Twist
    doAssert a.c0 is Fp4, "This assumes 𝔽p12 as a cubic extension of 𝔽p4"

  # In the following equations (taken from cubic extension implementation)
  # b0 = (b00, b01)
  # b1 = (  0, b11)
  # b2 = (b20, b21)
  #
  # v0 = a0 b0 = (f00, f01).(b00, b01)
  # v1 = a1 b1 = (f10, f11).(  0, b11)
  # v2 = a2 b2 = (f20, f21).(b20, b21)
  #
  # r₀ = ξ ((a₁ + a₂)(b₁ + b₂) - v₁ - v₂) + v₀
  # r₁ = (a₀ + a₁) * (b₀ + b₁) - v₀ - v₁ + β v₂
  # r₂ = (a₀ + a₂) * (b₀ + b₂) - v₀ - v₂ + v₁

  var V0 {.noInit.}, V1 {.noInit.}, V2 {.noinit.}: doublePrec(Fp4[C])
  var t0 {.noInit.}, t1 {.noInit.}: Fp4[C]
  var f2x{.noInit.}, g2x {.noinit.}: doublePrec(Fp4[C])

  V0.prod2x(a.c0, b.c0)
  V1.mul2x_sparse_by_0y(a.c1, b.c1)
  V2.prod2x(a.c2, b.c2)

  # r₀ = ξ ((a₁ + a₂)(b₁ + b₂) - v₁ - v₂) + v₀
  t0.sum(a.c1, a.c2)
  t1.c1.sum(b.c1.c1, b.c2.c1)             # b₁ = (  0, b11)
  f2x.prod2x_disjoint(t0, b.c2.c0, t1.c1) # (a₁ + a₂).(b₁ + b₂)
  f2x.diff2xMod(f2x, V1)
  f2x.diff2xMod(f2x, V2)
  f2x.prod2x(f2x, NonResidue)
  f2x.sum2xMod(f2x, V0)

  # r₁ = (a₀ + a₁) * (b₀ + b₁) - v₀ - v₁
  t0.sum(a.c0, a.c1)
  t1.c1.sum(b.c0.c1, b.c1.c1)             # b₁ = (  0, b11)
  g2x.prod2x_disjoint(t0, b.c0.c0, t1.c1) # (a₀ + a₁).(b₀ + b₁)
  g2x.diff2xMod(g2x, V0)
  g2x.diff2xMod(g2x, V1)

  # r₂ = (a₀ + a₂) and (b₀ + b₂)
  t0.sum(a.c0, a.c2)
  t1.sum(b.c0, b.c2)

  # Now we are aliasing free

  # r₀ = ξ ((a₁ + a₂)(b₁ + b₂) - v₁ - v₂) + v₀
  a.c0.redc2x(f2x)

  # r₁ = (a₀ + a₁) * (b₀ + b₁) - v₀ - v₁ + β v₂
  f2x.prod2x(V2, NonResidue)
  g2x.sum2xMod(g2x, f2x)
  a.c1.redc2x(g2x)

  # r₂ = (a₀ + a₂) * (b₀ + b₂) - v₀ - v₂ + v₁
  f2x.prod2x(t0, t1)
  f2x.diff2xMod(f2x, V0)
  f2x.diff2xMod(f2x, V2)
  f2x.sum2xMod(f2x, V1)
  a.c2.redc2x(f2x)

# Dispatch
# ------------------------------------------------------------

func mul*[C](f: var Fp12[C], line: Line[Fp2[C]]) {.inline.} =
  ## Multiply an element of Fp12 by a sparse line function (xyz000 or xy000z)
  when C.getSexticTwist() == D_Twist:
    f.mul_sparse_by_line_xyz000(line)
  elif C.getSexticTwist() == M_Twist:
    f.mul_sparse_by_line_xy000z(line)
  else:
    {.error: "A line function assumes that the curve has a twist".}

func prod_sparse_sparse*[C](f: var Fp12[C], line0, line1: Line[Fp2[C]]) {.inline.} =
  ## Multiply 2 lines function (xyz000 or xy000z)
  ## and store the result in f
  ## f is overwritten
  when C.getSexticTwist() == D_Twist:
    f.prod_xyz000_xyz000_into_abcdefghij00(line0, line1)
  elif C.getSexticTwist() == M_Twist:
    f.prod_xy000z_xy000z_into_abcd00efghij(line0, line1)
  else:
    {.error: "A line function assumes that the curve has a twist".}

func mul_3way_sparse_sparse*[C](f: var Fp12[C], line0, line1: Line[Fp2[C]]) {.inline.} =
  ## Multiply f*line0*line1 with lines (xyz000 or xy000z)
  ## f is updated with the result
  var t{.noInit.}: typeof(f)
  when C.getSexticTwist() == D_Twist:
    t.prod_xyz000_xyz000_into_abcdefghij00(line0, line1)
    f.mul_sparse_by_abcdefghij00(t)
  elif C.getSexticTwist() == M_Twist:
    t.prod_xy000z_xy000z_into_abcd00efghij(line0, line1)
    f.mul_sparse_by_abcd00efghij(t)
  else:
    {.error: "A line function assumes that the curve has a twist".}
