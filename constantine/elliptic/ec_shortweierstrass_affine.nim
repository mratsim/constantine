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
  ../io/[io_fields, io_towers],
  ../curves/zoo_precomputed_params

# ############################################################
#
#             Elliptic Curve in Short Weierstrass form
#                 with Affine Coordinates
#
# ############################################################

type
  Twisted* = enum
    NotOnTwist
    OnTwist

  ECP_ShortW_Aff*[F; Tw: static Twisted] = object
    ## Elliptic curve point for a curve in Short Weierstrass form
    ##   y² = x³ + a x + b
    ##
    ## over a field F
    x*, y*: F

  SexticNonResidue* = NonResidue

func `==`*(P, Q: ECP_ShortW_Aff): SecretBool =
  ## Constant-time equality check
  result = P.x == Q.x
  result = result and (P.y == Q.y)

func isInf*(P: ECP_ShortW_Aff): SecretBool =
  ## Returns true if P is an infinity point
  ## and false otherwise
  result = P.x.isZero() and P.y.isZero()

func curve_eq_rhs*[F](y2: var F, x: F, Tw: static Twisted) =
  ## Compute the curve equation right-hand-side from field element `x`
  ## i.e.  `y²` in `y² = x³ + a x + b`
  ## or on sextic twists for pairing curves `y² = x³ + b/µ` or `y² = x³ + µ b`
  ## with µ the chosen sextic non-residue

  var t{.noInit.}: F
  t.square(x)
  t *= x

  when Tw == NotOnTwist:
    when F.C.getCoefB() >= 0:
      y2.fromInt F.C.getCoefB()
      y2 += t
    else:
      y2.fromInt -F.C.getCoefB()
      y2.diff(t, y2)
  else:
    y2.sum(F.C.getCoefB_G2, t)

  when F.C.getCoefA() != 0:
    t = x
    t *= F.C.getCoefA()
    y2 += t

func isOnCurve*[F](x, y: F, Tw: static Twisted): SecretBool =
  ## Returns true if the (x, y) coordinates
  ## represents a point of the elliptic curve

  var y2, rhs {.noInit.}: F
  y2.square(y)
  rhs.curve_eq_rhs(x, Tw)

  return y2 == rhs

func trySetFromCoordX*[F, Tw](
       P: var ECP_ShortW_Aff[F, Tw],
       x: F): SecretBool =
  ## Try to create a point the elliptic curve
  ## y² = x³ + a x + b     (affine coordinate)
  ##
  ##
  ## return true and update `P` if `x` leads to a valid point
  ## return false otherwise, in that case `P` is undefined.
  ##
  ## Note: Dedicated robust procedures for hashing-to-curve
  ##       will be provided, this is intended for testing purposes.
  ## 
  ##       For **test case generation only**,
  ##       this is preferred to generating random point
  ##       via random scalar multiplication of the curve generator
  ##       as the latter assumes:
  ##       - point addition, doubling work
  ##       - scalar multiplication works
  ##       - a generator point is defined
  ##       i.e. you can't test unless everything is already working
  P.y.curve_eq_rhs(x, Tw)
  result = sqrt_if_square(P.y)
  P.x = x

func neg*(P: var ECP_ShortW_Aff, Q: ECP_ShortW_Aff) =
  ## Negate ``P``
  P.x = Q.x
  P.y.neg(Q.y)

func neg*(P: var ECP_ShortW_Aff) =
  ## Negate ``P``
  P.y.neg()

func cneg*(P: var ECP_ShortW_Aff, ctl: CTBool) =
  ## Conditional negation.
  ## Negate if ``ctl`` is true
  P.y.cneg(ctl)
