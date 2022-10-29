# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  ../../platforms/abstractions,
  ../config/curves,
  ../arithmetic,
  ../extension_fields,
  ../io/[io_fields, io_extfields],
  ../constants/zoo_constants

# No exceptions allowed
{.push raises: [].}

# ############################################################
#
#             Elliptic Curve in Short Weierstrass form
#                 with Affine Coordinates
#
# ############################################################

type
  Subgroup* = enum
    G1
    G2

  ECP_ShortW_Aff*[F; G: static Subgroup] = object
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

func setInf*(P: var ECP_ShortW_Aff) =
  ## Set P to the infinity point
  P.x.setZero()
  P.y.setZero()

func ccopy*(P: var ECP_ShortW_Aff, Q: ECP_ShortW_Aff, ctl: SecretBool) {.inline.} =
  ## Constant-time conditional copy
  ## If ctl is true: Q is copied into P
  ## if ctl is false: Q is not copied and P is unmodified
  ## Time and memory accesses are the same whether a copy occurs or not
  for fP, fQ in fields(P, Q):
    ccopy(fP, fQ, ctl)

func curve_eq_rhs*[F](y2: var F, x: F, G: static Subgroup) =
  ## Compute the curve equation right-hand-side from field element `x`
  ## i.e.  `y²` in `y² = x³ + a x + b`
  ## or on sextic twists for pairing curves `y² = x³ + b/µ` or `y² = x³ + µ b`
  ## with µ the chosen sextic non-residue

  var t{.noInit.}: F
  t.square(x)
  when F.C.getCoefA() != 0:
    t += F.C.getCoefA()
  t *= x

  when G == G1:
    when F.C.getCoefB() >= 0:
      y2.fromUint uint F.C.getCoefB()
      y2 += t
    else:
      y2.fromUint uint -F.C.getCoefB()
      y2.diff(t, y2)
  else:
    y2.sum(F.C.getCoefB_G2(), t)

func isOnCurve*[F](x, y: F, G: static Subgroup): SecretBool =
  ## Returns true if the (x, y) coordinates
  ## represents a point of the elliptic curve

  var y2 {.noInit.}, rhs {.noInit.}: F
  y2.square(y)
  rhs.curve_eq_rhs(x, G)

  return y2 == rhs

func trySetFromCoordX*[F, G](
       P: var ECP_ShortW_Aff[F, G],
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
  P.y.curve_eq_rhs(x, G)
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
