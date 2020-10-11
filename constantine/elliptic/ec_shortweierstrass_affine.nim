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
  ../io/[io_fields, io_towers]

# ############################################################
#
#             Elliptic Curve in Short Weierstrass form
#                 with Projective Coordinates
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

func curve_eq_rhs*[F](y2: var F, x: F, Tw: static Twisted) =
  ## Compute the curve equation right-hand-side from field element `x`
  ## i.e.  `y²` in `y² = x³ + a x + b`
  ## or on sextic twists for pairing curves `y² = x³ + b/µ` or `y² = x³ + µ b`
  ## with µ the chosen sextic non-residue

  var t{.noInit.}: F
  t.square(x)
  t *= x

  # This procedure is not use in perf critical situation like signing/verification
  # but for testing to quickly create points on a curve.
  # That said D-Twists require an inversion
  # and we could avoid doing `b/µ` or `µ*b` at runtime on 𝔽p²
  # which would accelerate random point generation
  #
  # This is preferred to generating random point
  # via random scalar multiplication of the curve generator
  # as the latter assumes:
  # - point addition, doubling work
  # - scalar multiplication works
  # - a generator point is defined
  # i.e. you can't test unless everything is already working
  #
  # TODO: precomputation needed when deserializing points
  #       to check if a point is on-curve and prevent denial-of-service
  #       using slow inversion.
  when F.C.getCoefB() >= 0:
    y2.fromInt F.C.getCoefB()
    when Tw == OnTwist:
      when F.C.getSexticTwist() == D_Twist:
        y2 /= SexticNonResidue
      elif F.C.getSexticTwist() == M_Twist:
        y2 *= SexticNonResidue
      else:
        {.error: "Only twisted curves are supported on extension field 𝔽p²".}

    y2 += t
  else:
    y2.fromInt -F.C.getCoefB()
    when Tw == OnTwist:
      when F.C.getSexticTwist() == D_Twist:
        y2 /= SexticNonResidue
      elif F.C.getSexticTwist() == M_Twist:
        y2 *= SexticNonResidue
      else:
        {.error: "Only twisted curves are supported on extension field 𝔽p²".}

    y2.diffAlias(t, y2)

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
  ## The `Z` coordinates is set to 1
  ##
  ## return true and update `P` if `x` leads to a valid point
  ## return false otherwise, in that case `P` is undefined.
  ##
  ## Note: Dedicated robust procedures for hashing-to-curve
  ##       will be provided, this is intended for testing purposes.
  P.y.curve_eq_rhs(x, Tw)
  result = sqrt_if_square(P.y)

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
