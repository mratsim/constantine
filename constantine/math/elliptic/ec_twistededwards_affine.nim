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
  ../extension_fields,
  ../io/[io_fields, io_extfields]

# ############################################################
#
#             Elliptic Curve in Twisted Edwards form
#                 with Affine Coordinates
#
# ############################################################

type ECP_TwEdwards_Aff*[F] = object
  ## Elliptic curve point for a curve in Twisted Edwards form
  ##   ax²+y²=1+dx²y²
  ## with a, d ≠ 0 and a ≠ d
  ##
  ## over a field F
  x*, y*: F

func `==`*(P, Q: ECP_TwEdwards_Aff): SecretBool =
  ## Constant-time equality check
  result = P.x == Q.x
  result = result and (P.y == Q.y)


func isInf*(P: ECP_TwEdwards_Aff): SecretBool =
  ## Returns true if P is an infinity point
  ## and false otherwise
  result = P.x.isZero() and P.y.isOne()


func isOnCurve*[F](x, y: F): SecretBool =
  ## Returns true if the (x, y) coordinates
  ## represents a point of the Twisted Edwards elliptic curve
  ## with equation ax²+y²=1+dx²y²
  var t0{.noInit.}, t1{.noInit.}, t2{.noInit.}: F
  t0.square(x)
  t1.square(y)
  
  # ax²+y²
  when F.C.getCoefA() is int:
    when F.C.getCoefA() == -1:
      t2.diff(t1, t0)
    else:
      t2.prod(t0, F.C.getCoefA())
      t2 += t1
  else:
    t2.prod(F.C.getCoefA(), t0)
    t2 += t1

  # dx²y²
  t0 *= t1
  when F.C.getCoefD() is int:
    when F.C.getCoefD >= 0:
      t1.fromUint uint F.C.getCoefD()
      t0 *= t1
    else:
      t1.fromUint uint F.C.getCoefD()
      t0 *= t1
      t0.neg()
  else:
    t0 *= F.C.getCoefD()

  # ax²+y² - dx²y² =? 1
  t2 -= t0
  return t2.isOne()

func trySetFromCoordY*[F](P: var ECP_TwEdwards_Aff[F], y: F): SecretBool =
  ## Try to create a point the elliptic curve
  ##   ax²+y²=1+dx²y²    (affine coordinate)
  ##
  ##
  ## return true and update `P` if `y` leads to a valid point
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

  # https://eprint.iacr.org/2015/677.pdf
  # p2: Encoding and parsing curve points.
  # x² = (y² − 1)/(dy² − a)
  var t {.noInit.}: F
  t.square(y)

  # (dy² − a)
  when F.C.getCoefD() is int:
    when F.C.getCoefD() >= 0:
      P.y.fromUint uint F.C.getCoefD()
    else:
      P.y.fromUint uint -F.C.getCoefD()
      P.y.neg()
  else:
    P.y = F.C.getCoefD()
  P.y *= t
  when F.C.getCoefA() is int:
    when F.C.getCoefA == -1:
      P.x.setOne()
      P.y += P.x
    elif F.C.getCoefA >= 0:
      P.x.fromUint uint F.C.getCoefA()
      P.y -= P.x
    else:
      P.x.fromUint uint -F.C.getCoefA()
      P.y += P.x
  else:
    P.y -= F.C.getCoefA()

  # y² − 1
  P.x.setMinusOne()
  P.x += t

  # √((y² − 1)/(dy² − a))
  result = sqrt_ratio_if_square(t, P.x, P.y)
  P.x = t
  P.y = y

func neg*(P: var ECP_TwEdwards_Aff, Q: ECP_TwEdwards_Aff) =
  ## Negate ``P``
  P.x.neg(Q.x)
  P.y = Q.y

func neg*(P: var ECP_TwEdwards_Aff) =
  ## Negate ``P``
  P.x.neg()

func cneg*(P: var ECP_TwEdwards_Aff, ctl: CTBool) =
  ## Conditional negation.
  ## Negate if ``ctl`` is true
  P.x.cneg(ctl)
