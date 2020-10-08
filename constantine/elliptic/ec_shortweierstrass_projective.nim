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
  ./ec_shortweierstrass_affine

export Twisted

# ############################################################
#
#             Elliptic Curve in Short Weierstrass form
#                 with Projective Coordinates
#
# ############################################################

type ECP_ShortW_Proj*[F; Tw: static Twisted] = object
  ## Elliptic curve point for a curve in Short Weierstrass form
  ##   y² = x³ + a x + b
  ##
  ## over a field F
  ##
  ## in projective coordinates (X, Y, Z)
  ## corresponding to (x, y) with X = xZ and Y = yZ
  ##
  ## Note that projective coordinates are not unique
  x*, y*, z*: F

func `==`*(P, Q: ECP_ShortW_Proj): SecretBool =
  ## Constant-time equality check
  ## This is a costly operation
  # Reminder: the representation is not unique
  type F = ECP_ShortW_Proj.F

  var a{.noInit.}, b{.noInit.}: F

  a.prod(P.x, Q.z)
  b.prod(Q.x, P.z)
  result = a == b

  a.prod(P.y, Q.z)
  b.prod(Q.y, P.z)
  result = result and a == b

func isInf*(P: ECP_ShortW_Proj): SecretBool =
  ## Returns true if P is an infinity point
  ## and false otherwise
  ##
  ## Note: the projective coordinates equation is
  ##       Y²Z = X³ + aXZ² + bZ³
  ## A "zero" point is any point with coordinates X and Z = 0
  ## Y can be anything
  result = P.x.isZero() and P.z.isZero()

func setInf*(P: var ECP_ShortW_Proj) =
  ## Set ``P`` to infinity
  P.x.setZero()
  P.y.setOne()
  P.z.setZero()

func ccopy*(P: var ECP_ShortW_Proj, Q: ECP_ShortW_Proj, ctl: SecretBool) =
  ## Constant-time conditional copy
  ## If ctl is true: Q is copied into P
  ## if ctl is false: Q is not copied and P is unmodified
  ## Time and memory accesses are the same whether a copy occurs or not
  for fP, fQ in fields(P, Q):
    ccopy(fP, fQ, ctl)

func trySetFromCoordsXandZ*[F; Tw](
       P: var ECP_ShortW_Proj[F, Tw],
       x, z: F): SecretBool =
  ## Try to create a point the elliptic curve
  ## Y²Z = X³ + aXZ² + bZ³ (projective coordinates)
  ## y² = x³ + a x + b     (affine coordinate)
  ## return true and update `P` if `x` leads to a valid point
  ## return false otherwise, in that case `P` is undefined.
  ##
  ## Note: Dedicated robust procedures for hashing-to-curve
  ##       will be provided, this is intended for testing purposes.
  P.y.curve_eq_rhs(x, Tw)
  # TODO: supports non p ≡ 3 (mod 4) modulus like BLS12-377
  result = sqrt_if_square(P.y)

  P.x.prod(x, z)
  P.y *= z
  P.z = z

func trySetFromCoordX*[F; Tw](
       P: var ECP_ShortW_Proj[F, Tw],
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
  # TODO: supports non p ≡ 3 (mod 4) modulus like BLS12-377
  result = sqrt_if_square(P.y)
  P.x = x
  P.z.setOne()

func neg*(P: var ECP_ShortW_Proj, Q: ECP_ShortW_Proj) =
  ## Negate ``P``
  P.x = Q.x
  P.y.neg(Q.y)
  P.z = Q.z

func neg*(P: var ECP_ShortW_Proj) =
  ## Negate ``P``
  P.y.neg()

func cneg*(P: var ECP_ShortW_Proj, ctl: CTBool) =
  ## Conditional negation.
  ## Negate if ``ctl`` is true
  P.y.cneg(ctl)

func sum*[F; Tw: static Twisted](
       r: var ECP_ShortW_Proj[F, Tw],
       P, Q: ECP_ShortW_Proj[F, Tw]
     ) =
  ## Elliptic curve point addition for Short Weierstrass curves in projective coordinates
  ##
  ##   R = P + Q
  ##
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
  #   Complete addition formulas for prime order elliptic curves
  #   Joost Renes and Craig Costello and Lejla Batina, 2015
  #   https://eprint.iacr.org/2015/1060
  #
  # with the indices 1 corresponding to ``P``, 2 to ``Q`` and 3 to the result ``r``
  #
  # X₃ = (X₁Y₂ + X₂Y₁)(Y₁Y₂ - a (X₁Z₂ + X₂Z₁) - 3bZ₁Z₂)
  #      - (Y₁Z₂ + Y₂Z₁)(aX₁X₂ + 3b(X₁Z₂ + X₂Z₁) - a²Z₁Z₂)
  # Y₃ = (3X₁X₂ + aZ₁Z₂)(aX₁X₂ + 3b(X₁Z₂ + X₂Z₁) - a²Z₁Z₂)
  #      + (Y₁Y₂ + a (X₁Z₂ + X₂Z₁) + 3bZ₁Z₂)(Y₁Y₂ - a(X₁Z₂ + X₂Z₁) - 3bZ₁Z₂)
  # Z₃ = (Y₁Z₂ + Y₂Z₁)(Y₁Y₂ + a(X₁Z₂ + X₂Z₁) + 3bZ₁Z₂) + (X₁Y₂ + X₂Y₁)(3X₁X₂ + aZ₁Z₂)
  #
  # Cost: 12M + 3 mul(a) + 2 mul(3b) + 23 a

  # TODO: static doAssert odd order

  when F.C.getCoefA() == 0:
    var t0 {.noInit.}, t1 {.noInit.}, t2 {.noInit.}, t3 {.noInit.}, t4 {.noInit.}: F
    const b3 = 3 * F.C.getCoefB()

    # Algorithm 7 for curves: y² = x³ + b
    # 12M + 2 mul(3b) + 19A
    #
    # X₃ = (X₁Y₂ + X₂Y₁)(Y₁Y₂ − 3bZ₁Z₂)
    #     − 3b(Y₁Z₂ + Y₂Z₁)(X₁Z₂ + X₂Z₁)
    # Y₃ = (Y₁Y₂ + 3bZ₁Z₂)(Y₁Y₂ − 3bZ₁Z₂)
    #     + 9bX₁X₂ (X₁Z₂ + X₂Z₁)
    # Z₃= (Y₁Z₂ + Y₂Z₁)(Y₁Y₂ + 3bZ₁Z₂) + 3X₁X₂ (X₁Y₂ + X₂Y₁)
    t0.prod(P.x, Q.x)         # 1.  t₀ <- X₁X₂
    t1.prod(P.y, Q.y)         # 2.  t₁ <- Y₁Y₂
    t2.prod(P.z, Q.z)         # 3.  t₂ <- Z₁Z₂
    t3.sum(P.x, P.y)          # 4.  t₃ <- X₁ + Y₁
    t4.sum(Q.x, Q.y)          # 5.  t₄ <- X₂ + Y₂
    t3 *= t4                  # 6.  t₃ <- t₃ * t₄
    t4.sum(t0, t1)            # 7.  t₄ <- t₀ + t₁
    t3 -= t4                  # 8.  t₃ <- t₃ - t₄   t₃ = (X₁ + Y₁)(X₂ + Y₂) - (X₁X₂ + Y₁Y₂) = X₁Y₂ + X₂Y₁
    when Tw == OnTwist and F.C.getSexticTwist() == D_Twist:
      t3 *= SexticNonResidue
    t4.sum(P.y, P.z)          # 9.  t₄ <- Y₁ + Z₁
    r.x.sum(Q.y, Q.z)         # 10. X₃ <- Y₂ + Z₂
    t4 *= r.x                 # 11. t₄ <- t₄ X₃
    r.x.sum(t1, t2)           # 12. X₃ <- t₁ + t₂   X₃ = Y₁Y₂ + Z₁Z₂
    t4 -= r.x                 # 13. t₄ <- t₄ - X₃   t₄ = (Y₁ + Z₁)(Y₂ + Z₂) - (Y₁Y₂ + Z₁Z₂) = Y₁Z₂ + Y₂Z₁
    when Tw == OnTwist and F.C.getSexticTwist() == D_Twist:
      t4 *= SexticNonResidue
    r.x.sum(P.x, P.z)         # 14. X₃ <- X₁ + Z₁
    r.y.sum(Q.x, Q.z)         # 15. Y₃ <- X₂ + Z₂
    r.x *= r.y                # 16. X₃ <- X₃ Y₃     X₃ = (X₁Z₁)(X₂Z₂)
    r.y.sum(t0, t2)           # 17. Y₃ <- t₀ + t₂   Y₃ = X₁ X₂ + Z₁ Z₂
    r.y.diffAlias(r.x, r.y)   # 18. Y₃ <- X₃ - Y₃   Y₃ = (X₁ + Z₁)(X₂ + Z₂) - (X₁ X₂ + Z₁ Z₂) = X₁Z₂ + X₂Z₁
    when Tw == OnTwist and F.C.getSexticTwist() == D_Twist:
      t0 *= SexticNonResidue
      t1 *= SexticNonResidue
    r.x.double(t0)            # 19. X₃ <- t₀ + t₀   X₃ = 2 X₁X₂
    t0 += r.x                 # 20. t₀ <- X₃ + t₀   t₀ = 3 X₁X₂
    t2 *= b3                  # 21. t₂ <- 3b t₂     t₂ = 3bZ₁Z₂
    when Tw == OnTwist and F.C.getSexticTwist() == M_Twist:
      t2 *= SexticNonResidue
    r.z.sum(t1, t2)           # 22. Z₃ <- t₁ + t₂   Z₃ = Y₁Y₂ + 3bZ₁Z₂
    t1 -= t2                  # 23. t₁ <- t₁ - t₂   t₁ = Y₁Y₂ - 3bZ₁Z₂
    r.y *= b3                 # 24. Y₃ <- 3b Y₃     Y₃ = 3b(X₁Z₂ + X₂Z₁)
    when Tw == OnTwist and F.C.getSexticTwist() == M_Twist:
      r.y *= SexticNonResidue
    r.x.prod(t4, r.y)         # 25. X₃ <- t₄ Y₃     X₃ = 3b(Y₁Z₂ + Y₂Z₁)(X₁Z₂ + X₂Z₁)
    t2.prod(t3, t1)           # 26. t₂ <- t₃ t₁     t₂ = (X₁Y₂ + X₂Y₁) (Y₁Y₂ - 3bZ₁Z₂)
    r.x.diffAlias(t2, r.x)    # 27. X₃ <- t₂ - X₃   X₃ = (X₁Y₂ + X₂Y₁) (Y₁Y₂ - 3bZ₁Z₂) - 3b(Y₁Z₂ + Y₂Z₁)(X₁Z₂ + X₂Z₁)
    r.y *= t0                 # 28. Y₃ <- Y₃ t₀     Y₃ = 9bX₁X₂ (X₁Z₂ + X₂Z₁)
    t1 *= r.z                 # 29. t₁ <- t₁ Z₃     t₁ = (Y₁Y₂ - 3bZ₁Z₂)(Y₁Y₂ + 3bZ₁Z₂)
    r.y += t1                 # 30. Y₃ <- t₁ + Y₃   Y₃ = (Y₁Y₂ + 3bZ₁Z₂)(Y₁Y₂ - 3bZ₁Z₂) + 9bX₁X₂ (X₁Z₂ + X₂Z₁)
    t0 *= t3                  # 31. t₀ <- t₀ t₃     t₀ = 3X₁X₂ (X₁Y₂ + X₂Y₁)
    r.z *= t4                 # 32. Z₃ <- Z₃ t₄     Z₃ = (Y₁Y₂ + 3bZ₁Z₂)(Y₁Z₂ + Y₂Z₁)
    r.z += t0                 # 33. Z₃ <- Z₃ + t₀   Z₃ = (Y₁Z₂ + Y₂Z₁)(Y₁Y₂ + 3bZ₁Z₂) + 3X₁X₂ (X₁Y₂ + X₂Y₁)
  else:
    {.error: "Not implemented.".}

func madd*[F; Tw: static Twisted](
       r: var ECP_ShortW_Proj[F, Tw],
       P: ECP_ShortW_Proj[F, Tw],
       Q: ECP_ShortW_Aff[F, Tw]
     ) =
  ## Elliptic curve mixed addition for Short Weierstrass curves
  ## with p in Projective coordinates and Q in affine coordinates
  ##
  ##   R = P + Q

  # TODO: static doAssert odd order

  when F.C.getCoefA() == 0:
    var t0 {.noInit.}, t1 {.noInit.}, t2 {.noInit.}, t3 {.noInit.}, t4 {.noInit.}: F
    const b3 = 3 * F.C.getCoefB()

    # Algorithm 8 for curves: y² = x³ + b
    # X₃ = (X₁Y₂ + X₂Y₁)(Y₁Y₂ − 3bZ₁)
    #     − 3b(Y₁ + Y₂Z₁)(X₁ + X₂Z₁)
    # Y₃ = (Y₁Y₂ + 3bZ₁)(Y₁Y₂ − 3bZ₁)
    #     + 9bX₁X₂ (X₁ + X₂Z₁)
    # Z₃= (Y₁ + Y₂Z₁)(Y₁Y₂ + 3bZ₁) + 3 X₁X₂ (X₁Y₂ + X₂Y₁)
    t0.prod(P.x, Q.x)         # 1.  t₀ <- X₁ X₂
    t1.prod(P.y, Q.y)         # 2.  t₁ <- Y₁ Y₂
    t3.sum(P.x, P.y)          # 3.  t₃ <- X₁ + Y₁ ! error in paper
    t4.sum(Q.x, Q.y)          # 4.  t₄ <- X₂ + Y₂ ! error in paper
    t3 *= t4                  # 5.  t₃ <- t₃ * t₄
    t4.sum(t0, t1)            # 6.  t₄ <- t₀ + t₁
    t3 -= t4                  # 7.  t₃ <- t₃ - t₄, t₃ = (X₁ + Y₁)(X₂ + Y₂) - (X₁ X₂ + Y₁ Y₂) = X₁Y₂ + X₂Y₁
    when Tw == OnTwist and F.C.getSexticTwist() == D_Twist:
      t3 *= SexticNonResidue
    t4.prod(Q.y, P.z)         # 8.  t₄ <- Y₂ Z₁
    t4 += P.y                 # 9.  t₄ <- t₄ + Y₁, t₄ = Y₁+Y₂Z₁
    when Tw == OnTwist and F.C.getSexticTwist() == D_Twist:
      t4 *= SexticNonResidue
    r.y.prod(Q.x, P.z)        # 10. Y₃ <- X₂ Z₁
    r.y += P.x                # 11. Y₃ <- Y₃ + X₁, Y₃ = X₁ + X₂Z₁
    when Tw == OnTwist and F.C.getSexticTwist() == D_Twist:
      t0 *= SexticNonResidue
      t1 *= SexticNonResidue
    r.x.double(t0)            # 12. X₃ <- t₀ + t₀
    t0 += r.x                 # 13. t₀ <- X₃ + t₀, t₀ = 3X₁X₂
    t2 = P.z
    t2 *= b3                  # 14. t₂ <- 3bZ₁
    when Tw == OnTwist and F.C.getSexticTwist() == M_Twist:
      t2 *= SexticNonResidue
    r.z.sum(t1, t2)           # 15. Z₃ <- t₁ + t₂, Z₃ = Y₁Y₂ + 3bZ₁
    t1 -= t2                  # 16. t₁ <- t₁ - t₂, t₁ = Y₁Y₂ - 3bZ₁
    r.y *= b3                 # 17. Y₃ <- 3bY₃,    Y₃ = 3b(X₁ + X₂Z₁)
    when Tw == OnTwist and F.C.getSexticTwist() == M_Twist:
      r.y *= SexticNonResidue
    r.x.prod(t4, r.y)         # 18. X₃ <- t₄ Y₃,   X₃ = (Y₁ + Y₂Z₁) 3b(X₁ + X₂Z₁)
    t2.prod(t3, t1)           # 19. t₂ <- t₃ t₁,   t₂ = (X₁Y₂ + X₂Y₁)(Y₁Y₂ - 3bZ₁)
    r.x.diffAlias(t2, r.x)    # 20. X₃ <- t₂ - X₃, X₃ = (X₁Y₂ + X₂Y₁)(Y₁Y₂ - 3bZ₁) - 3b(Y₁ + Y₂Z₁)(X₁ + X₂Z₁)
    r.y *= t0                 # 21. Y₃ <- Y₃ t₀,   Y₃ = 9bX₁X₂ (X₁ + X₂Z₁)
    t1 *= r.z                 # 22. t₁ <- t₁ Z₃,   t₁ = (Y₁Y₂ - 3bZ₁)(Y₁Y₂ + 3bZ₁)
    r.y += t1                 # 23. Y₃ <- t₁ + Y₃, Y₃ = (Y₁Y₂ + 3bZ₁)(Y₁Y₂ - 3bZ₁) + 9bX₁X₂ (X₁ + X₂Z₁)
    t0 *= t3                  # 31. t₀ <- t₀ t₃,   t₀ = 3X₁X₂ (X₁Y₂ + X₂Y₁)
    r.z *= t4                 # 32. Z₃ <- Z₃ t₄,   Z₃ = (Y₁Y₂ + 3bZ₁)(Y₁ + Y₂Z₁)
    r.z += t0                 # 33. Z₃ <- Z₃ + t₀, Z₃ = (Y₁ + Y₂Z₁)(Y₁Y₂ + 3bZ₁) + 3X₁X₂ (X₁Y₂ + X₂Y₁)
  else:
    {.error: "Not implemented.".}

func double*[F; Tw: static Twisted](
       r: var ECP_ShortW_Proj[F, Tw],
       P: ECP_ShortW_Proj[F, Tw]
     ) =
  ## Elliptic curve point doubling for Short Weierstrass curves in projective coordinate
  ##
  ##   R = [2] P
  ##
  ## Short Weierstrass curves have the following equation in projective coordinates
  ##   Y²Z = X³ + aXZ² + bZ³
  ## from the affine equation
  ##   y² = x³ + a x + b
  ##
  ## ``r`` is initialized/overwritten with the sum
  ##
  ## Implementation is constant-time, in particular it will not expose
  ## that `P` is an infinity point.
  ## This is done by using a "complete" or "exception-free" addition law.
  ##
  ## This requires the order of the curve to be odd
  #
  # Implementation:
  # Algorithms 3 (generic case), 6 (a == -3), 9 (a == 0) of
  #   Complete addition formulas for prime order elliptic curves
  #   Joost Renes and Craig Costello and Lejla Batina, 2015
  #   https://eprint.iacr.org/2015/1060
  #
  # X₃ = 2XY (Y² - 2aXZ - 3bZ²)
  #      - 2YZ (aX² + 6bXZ - a²Z²)
  # Y₃ = (Y² + 2aXZ + 3bZ²)(Y² - 2aXZ - 3bZ²)
  #      + (3X² + aZ²)(aX² + 6bXZ - a²Z²)
  # Z₃ = 8Y³Z
  #
  # Cost: 8M + 3S + 3 mul(a) + 2 mul(3b) + 15a

  when F.C.getCoefA() == 0:
    var t0 {.noInit.}, t1 {.noInit.}, t2 {.noInit.}, snrY {.noInit.}: F
    const b3 = 3 * F.C.getCoefB()

    # Algorithm 9 for curves:
    # 6M + 2S + 1 mul(3b) + 9a
    #
    # X₃ = 2XY(Y² - 9bZ²)
    # Y₃ = (Y² - 9bZ²)(Y² + 3bZ²) + 24bY²Z²
    # Z₃ = 8Y³Z
    snrY = P.y
    when Tw == OnTwist and F.C.getSexticTwist() == D_Twist:
      snrY *= SexticNonResidue
      t0.square(P.y)
      t0 *= SexticNonResidue
    else:
      t0.square(P.y)          # 1.  t₀ <- Y Y
    r.z.double(t0)            # 2.  Z₃ <- t₀ + t₀
    r.z.double()              # 3.  Z₃ <- Z₃ + Z₃
    r.z.double()              # 4.  Z₃ <- Z₃ + Z₃   Z₃ = 8Y²
    t1.prod(snrY, P.z)        # 5.  t₁ <- Y Z
    t2.square(P.z)            # 6.  t₂ <- Z Z
    t2 *= b3                  # 7.  t₂ <- 3b t₂
    when Tw == OnTwist and F.C.getSexticTwist() == M_Twist:
      t2 *= SexticNonResidue
    r.x.prod(t2, r.z)         # 8.  X₃ <- t₂ Z₃
    r.y.sum(t0, t2)           # 9.  Y₃ <- t₀ + t₂
    r.z *= t1                 # 10. Z₃ <- t₁ Z₃
    t1.double(t2)             # 11. t₁ <- t₂ + t₂
    t2 += t1                  # 12. t₂ <- t₁ + t₂
    t0 -= t2                  # 13. t₀ <- t₀ - t₂
    r.y *= t0                 # 14. Y₃ <- t₀ Y₃
    r.y += r.x                # 15. Y₃ <- X₃ + Y₃
    t1.prod(P.x, snrY)        # 16. t₁ <- X Y
    r.x.prod(t0, t1)          # 17. X₃ <- t₀ t₁
    r.x.double()              # 18. X₃ <- X₃ + X₃
  else:
    {.error: "Not implemented.".}

func `+=`*(P: var ECP_ShortW_Proj, Q: ECP_ShortW_Proj) =
  ## In-place point addition
  # TODO test for aliasing support
  var tmp {.noInit.}: ECP_ShortW_Proj
  tmp.sum(P, Q)
  P = tmp

func `+=`*(P: var ECP_ShortW_Proj, Q: ECP_ShortW_Aff) =
  ## In-place mixed point addition
  # used in line_addition
  P.madd(P, Q)

func double*(P: var ECP_ShortW_Proj) =
  var tmp {.noInit.}: ECP_ShortW_Proj
  tmp.double(P)
  P = tmp

func diff*(r: var ECP_ShortW_Proj,
              P, Q: ECP_ShortW_Proj
     ) =
  ## r = P - Q
  ## Can handle r and Q aliasing
  var nQ = Q
  nQ.neg()
  r.sum(P, nQ)

func affineFromProjective*[F, Tw](
       aff: var ECP_ShortW_Aff[F, Tw],
       proj: ECP_ShortW_Proj[F, Tw]) =
  var invZ {.noInit.}: F
  invZ.inv(proj.z)

  aff.x.prod(proj.x, invZ)
  aff.y.prod(proj.y, invZ)

func projectiveFromAffine*[F, Tw](
       proj: var ECP_ShortW_Proj[F, Tw],
       aff: ECP_ShortW_Aff[F, Tw]) {.inline.} =
  proj.x = aff.x
  proj.y = aff.y
  proj.z.setOne()
