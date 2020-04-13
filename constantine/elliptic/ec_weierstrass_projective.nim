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
  ./ec_weierstrass_affine

# ############################################################
#
#             Elliptic Curve in Weierstrass form
#                 with Projective Coordinates
#
# ############################################################

type ECP_SWei_Proj*[F] = object
  ## Elliptic curve point for a curve in Short Weierstrass form
  ##   y² = x³ + a x + b
  ##
  ## over a field F
  ##
  ## in projective coordinates (X, Y, Z)
  ## corresponding to (x, y) with X = xZ and Y = yZ
  ##
  ## Note that projective coordinates are not unique
  x, y, z: F

func `==`*[F](P, Q: ECP_SWei_Proj[F]): CTBool[Word] =
  ## Constant-time equality check
  # Reminder: the representation is not unique

  var a{.noInit.}, b{.noInit.}: F

  a.prod(P.x, Q.z)
  b.prod(Q.x, P.z)
  result = a == b

  a.prod(P.y, Q.z)
  b.prod(Q.y, P.z)
  result = result and a == b

func isInf*(P: ECP_SWei_Proj): CTBool[Word] =
  ## Returns true if P is the infinity point
  ## and false otherwise
  result = P.x.isZero() and P.y.isOne() and P.z.isZero()

func setInf*(P: var ECP_SWei_Proj) =
  ## Set ``P`` to infinity
  P.x.setZero()
  P.y.setOne()
  P.z.setZero()

func trySetFromCoordsXandZ*[F](P: var ECP_SWei_Proj[F], x, z: F): CTBool[Word] =
  ## Try to create a point the elliptic curve
  ## Y²Z = X³ + aXZ² + bZ³ (projective coordinates)
  ## y² = x³ + a x + b     (affine coordinate)
  ## return true and update `P` if `x` leads to a valid point
  ## return false otherwise, in that case `P` is undefined.
  ##
  ## Note: Dedicated robust procedures for hashing-to-curve
  ##       will be provided, this is intended for testing purposes.
  P.y.curve_eq_rhs(x)
  # TODO: supports non p ≡ 3 (mod 4) modulus like BLS12-377
  result = sqrt_if_square_p3mod4(P.y)

  P.x.prod(x, z)
  P.y *= z

func trySetFromCoordX*[F](P: var ECP_SWei_Proj[F], x: F): CTBool[Word] =
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
  P.y.curve_eq_rhs(x)
  # TODO: supports non p ≡ 3 (mod 4) modulus like BLS12-377
  result = sqrt_if_square_p3mod4(P.y)
  P.x = x


func neg*(P: var ECP_SWei_Proj) =
  ## Negate ``P``
  P.y.neg(P.y)

func sum*[F](
       r: var ECP_SWei_Proj[F],
       P, Q: ECP_SWei_Proj[F]
     ) =
  ## Elliptic curve point addition for Short Weierstrass curves in projective coordinate
  ## Short Weierstrass curves have the following equation in projective coordinates
  ##   Y²Z = X³ + aXZ² + bZ³
  ## from the affine equation
  ##   y² = x³ + a x + b
  ##
  ## ``r`` is initialized/overwritten with the sum
  ##
  ## Implementation is constant-time, in particular it will not expose
  ## that P == Q or P == -Q or P or Q are the infinity points
  ## to simple side-channel attacks (SCA)
  ## This is done by using a "complete" or "exception-free" addition law.
  ##
  ## This requires the order of the curve to be odd
  #
  # Implementation:
  # Algorithms 1 (generic case), 4 (a == -3), 7 (a == 0) of
  #   Complete addition formulas for prime order elliptic curves\
  #   Joost Renes and Craig Costello and Lejla Batina, 2015\
  #   https://eprint.iacr.org/2015/1060
  #
  # with the indices 1 corresponding to ``P``, 2 to ``Q`` and 3 to the result ``r``
  #
  # X3 = (X1 Y2 + X2 Y1)(Y1 Y2 - a(X1 Z2 + X2 Z1) - 3b Z1 Z2)
  #      - (Y1 Z2 + Y2 Z1)(a X1 X2 + 3b(X1 Z2 + X2 Z1) - a² Z1 Z2)
  # Y3 = (3 X1 X2 + a Z1 Z2)(a X1 X2 + 3b (X1 Z2 + X2 Z1) - a² Z1 Z2)
  #      + (Y1 Y2 + a (X1 Z2 + X2 Z1) + 3b Z1 Z2)(Y1 Y2 - a(X1 Z2 + X2 Z1) - 3b Z1 Z2)
  # Z3 = (Y1 Z2 + Y2 Z1)(Y1 Y2 + a(X1 Z2 + X2 Z1) + 3b Z1 Z2) + (X1 Y2 + X2 Y1)(3 X1 X2 + a Z1 Z2)

  # TODO: static doAssert odd order
  var t0 {.noInit.}, t1 {.noInit.}, t2 {.noInit.}, t3 {.noInit.}, t4 {.noInit.}: F
  const b3 = 3 * F.C.getCoefB()

  when F.C.getCoefA() == 0:
    # Algorithm 7 for curves: y² = x³ + b
    # 12M + 2 mul(3b) + 19A
    t0.prod(P.x, Q.x)         # 1.  t0 <- X1 X2
    t1.prod(P.y, Q.y)         # 2.  t1 <- Y1 Y2
    t2.prod(P.z, Q.z)         # 3.  t2 <- Z1 Z2
    t3.sum(P.x, P.y)          # 4.  t3 <- X1 + Y1
    t4.sum(Q.x, Q.y)          # 5.  t4 <- X2 + Y2
    t3 *= t4                  # 6.  t3 <- t3 * t4
    t4.sum(t0, t1)            # 7.  t4 <- t0 + t1
    t3 -= t4                  # 8.  t3 <- t3 - t4   t3 = (X1 + Y1)(X2 + Y2) - (X1 X2 + Y1 Y2) = X1.Y2 + X2.Y1
    when F is Fp2 and F.C.getSexticTwist() == D_Twist:
      t3 *= F.sexticNonResidue()
    t4.sum(P.y, P.z)          # 9.  t4 <- Y1 + Z1
    r.x.sum(Q.y, Q.z)         # 10. X3 <- Y2 + Z2
    t4 *= r.x                 # 11. t4 <- t4 X3
    r.x.sum(t1, t2)           # 12. X3 <- t1 + t2   X3 = Y1 Y2 + Z1 Z2
    t4 -= r.x                 # 13. t4 <- t4 - X3   t4 = (Y1 + Z1)(Y2 + Z2) - (Y1 Y2 + Z1 Z2) = Y1 Z2 + Y2 Z1
    when F is Fp2 and F.C.getSexticTwist() == D_Twist:
      t4 *= F.sexticNonResidue()
    r.x.sum(P.x, P.z)         # 14. X3 <- X1 + Z1
    r.y.sum(Q.x, Q.z)         # 15. Y3 <- X2 + Z2
    r.x *= r.y                # 16. X3 <- X3 Y3     X3 = (X1 Z1)(X2 Z2)
    r.y.sum(t0, t2)           # 17. Y3 <- t0 + t2   Y3 = X1 X2 + Z1 Z2
    r.y.diff(r.x, r.y)        # 18. Y3 <- X3 - Y3   Y3 = (X1 + Z1)(X2 + Z2) - (X1 X2 + Z1 Z2) = X1 Z2 + X2 Z1
    when F is Fp2 and F.C.getSexticTwist() == D_Twist:
      t0 *= F.sexticNonResidue()
      t1 *= F.sexticNonResidue()
    r.x.double(t0)            # 19. X3 <- t0 + t0   X3 = 2 X1 X2
    t0 += r.x                 # 20. t0 <- X3 + t0   t0 = 3 X1 X2
    t2 *= b3                  # 21. t2 <- b3 t2     t2 = 3b Z1 Z2
    when F is Fp2 and F.C.getSexticTwist() == M_Twist:
      t2 *= F.sexticNonResidue()
    r.z.sum(t1, t2)           # 22. Z3 <- t1 + t2   Z3 = Y1 Y2 + 3b Z1 Z2
    t1 -= t2                  # 23. t1 <- t1 - t2   t1 = Y1 Y2 - 3b Z1 Z2
    r.y *= b3                 # 24. Y3 <- b3 Y3     Y3 = 3b(X1 Z2 + X2 Z1)
    when F is Fp2 and F.C.getSexticTwist() == M_Twist:
      r.y *= F.sexticNonResidue()
    r.x.prod(t4, r.y)         # 25. X3 <- t4 Y3     X3 = 3b(Y1 Z2 + Y2 Z1)(X1 Z2 + X2 Z1)
    t2.prod(t3, t1)           # 26. t2 <- t3 t1     t2 = (X1.Y2 + X2.Y1) (Y1 Y2 - 3b Z1 Z2)
    r.x.diff(t2, r.x)         # 27. X3 <- t2 - X3   X3 = (X1.Y2 + X2.Y1) (Y1 Y2 - 3b Z1 Z2) - 3b(Y1 Z2 + Y2 Z1)(X1 Z2 + X2 Z1)
    r.y *= t0                 # 28. Y3 <- Y3 t0     Y3 = 9b X1 X2 (X1 Z2 + X2 Z1)
    t1 *= r.z                 # 29. t1 <- t1 Z3     t1 = (Y1 Y2 - 3b Z1 Z2)(Y1 Y2 + 3b Z1 Z2)
    debugEcho "t1 : ", t1
    debugEcho "r.y: ", r.y
    r.y += t1                 # 30. Y3 <- t1 + Y3   Y3 = (Y1 Y2 + 3b Z1 Z2)(Y1 Y2 - 3b Z1 Z2) + 9b X1 X2 (X1 Z2 + X2 Z1)
    t0 *= t3                  # 31. t0 <- t0 t3     t0 = 3 X1 X2 (X1.Y2 + X2.Y1)
    r.z *= t4                 # 32. Z3 <- Z3 t4     Z3 = (Y1 Y2 + 3b Z1 Z2)(Y1 Z2 + Y2 Z1)
    r.z += t0                 # 33. Z3 <- Z3 + t0   Z3 = (Y1 Z2 + Y2 Z1)(Y1 Y2 + 3b Z1 Z2) + 3 X1 X2 (X1.Y2 + X2.Y1)
  else:
    {.error: "Not implemented.".}
