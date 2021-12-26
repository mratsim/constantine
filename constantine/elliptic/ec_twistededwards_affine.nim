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
#             Elliptic Curve in Twisted Edwards form
#                 with Affine Coordinates
#
# ############################################################

type
  ECP_TwEdwards_Aff*[F] = object
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


func isOnCurve*[F](x, y: ECP_TwEdwards_Aff[F]): SecretBool =
  ## Returns true if the (x, y) coordinates
  ## represents a point of the elliptic curve
  var t0{.noInit.}, t1{.noInit.}, t2{.noInit.}: F
  t0.square(x)
  t1.square(y)
  
  # ax²+y²
  t2.fromInt F.C.getCoefA()
  t2 *= t0
  t2 += t1

  # dx²y²
  t0 *= t1
  t1.fromInt F.C.getCoefD()
  t0 *= t1

  # ax²+y² - dx²y² =? 1
  t2 -= t1
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
  P.y.fromInt F.C.getCoefD()
  P.y *= t
  P.x.fromInt F.C.getCoefA()
  P.y -= P.x
  P.y.inv()

  # y² − 1
  P.x.setMinusOne()
  P.x += t

  # √((y² − 1)/(dy² − a))
  result = sqrt_ratio_if_square(t, P.x, P.y)
  P.x = t
  P.y = y