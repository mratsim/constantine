# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  ../primitives,
  ../config/[common, curves]

# ############################################################
#
#             Elliptic Curve in Weierstrass form
#                 with Projective Coordinates
#
# ############################################################

type ECP_ShortWei_Proj[F; Twist: static TwistKind] = object
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

func `==`*[F](P, Q: ECP_ShortWei_Proj[F]): CTBool[Word] =
  ## Constant-time equality check
  # Reminder: the representation is not unique

  var a{.noInit.}, b{.noInit.}: F

  a.prod(P.x, Q.z)
  b.prod(Q.x, P.z)
  result = a == b

  a.prod(P.y, Q.z)
  b.prod(Q.y, P.z)
  result = result and a == b

func setInf*(P: var ECP_ShortWei_Proj) =
  ## Set ``P`` to infinity
  P.x.setZero()
  P.y.setOne()
  P.z.setZero()

func neg*(P: var ECP_ShortWei_Proj) =
  ## Negate ``P``
  P.y.neg(P.y)

func sum[F; Twist: static TwistKind](
       r: var ECP_ShortWei_Proj[F, Twist],
       P, Q: ECP_ShortWei_Proj[F, Twist]
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
  var t0 {.noInit.}, t1 {.noInit.}, t2 {.noInit.}, t3 {.noInit.}, t4 {.noInit.}
  let b3 = 3 * F.C.get_B_coef()

  when F.C.get_A_coef() == 0:
    # Algorithm 7 for curves: y² = x³ + b
    # 12M + 2 mul(3b) + 19A
    t0.prod(P.x, Q.x)         # 1.  t0 <- X1 X2
    t1.prod(P.y, Q.y)         # 2.  t1 <- Y1 Y2
    t2.prod(P.z, Q.z)         # 3.  t2 <- Z1 Z2
    t3.sum(P.x, P.y)          # 4.  t3 <- X1 + Y1
    t4.sum(Q.x, Q.y)          # 5.  t4 <- X2 + Y2
    t3 *= t4                  # 6.  t3 <- t3 * t4
    t4.sum(t0, t1)            # 7.  t4 <- t0 + t1
    t3 -= t4                  # 8.  t3 <- t3 - t4
    t4.sum(P.y, P.z)          # 9.  t4 <- Y1 + Z1
    r.x.sum(Q.y, Q.z)         # 10. X3 <- Y2 + Z2
    t4 *= r.x                 # 11. t4 <- t4 X3
    r.x.sum(t1, t2)           # 12. X3 <- t1 + t2
    t4 -= r.x                 # 13. t4 <- t4 - X3
    r.x.sum(P.x, P.z)         # 14. X3 <- X1 + Z1
    r.y.sum(Q.x, Q.Z)         # 15. Y3 <- X2 + Z2
    r.x *= r.y                # 16. X3 <- X3 Y3
    r.y.sum(t0, t2)           # 17. Y3 <- t0 + t2
    r.y.diff(r.x, r.y)        # 18. Y3 <- X3 - Y3
    r.x.double(t0)            # 19. X3 <- t0 + t0
    t0 += r.x                 # 20. t0 <- X3 + t0
    t2 *= b3                  # 21. t2 <- b3 t2
    r.z.sum(t1, t2)           # 22. Z3 <- t1 + t2
    t1 -= t2                  # 23. t1 <- t1 - t2
    r.y *= b3                 # 24. Y3 <- b3 Y3
    r.x.prod(t4, r.y)         # 25. X3 <- t4 Y3
    t2.prod(t3, t1)           # 26. t2 <- t3 t1
    r.x.diff(t2, r.x)         # 27. X3 <- t2 - X3
    r.y *= t0                 # 28. Y3 <- Y3 t0
    t1 *= r.z                 # 29. t1 <- t1 Z3
    r.y += t1                 # 30. Y3 <- t1 + Y3
    t0 *= t3                  # 31. t0 <- t0 t3
    r.z *= t4                 # 32. Z3 <- Z3 t4
    r.z += t0                 # 33. Z3 <- Z3 + t0
  else:
    {.error: "Not implemented.".}
