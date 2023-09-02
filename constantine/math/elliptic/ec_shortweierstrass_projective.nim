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
  ./ec_shortweierstrass_affine

export Subgroup

# No exceptions allowed
{.push raises: [].}

# ############################################################
#
#             Elliptic Curve in Short Weierstrass form
#                 with Projective Coordinates
#
# ############################################################

type ECP_ShortW_Prj*[F; G: static Subgroup] = object
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

func isInf*(P: ECP_ShortW_Prj): SecretBool {.inline.} =
  ## Returns true if P is an infinity point
  ## and false otherwise
  ##
  ## Note: the projective coordinates equation is
  ##       Y²Z = X³ + aXZ² + bZ³
  ## A "zero" point is any point with coordinates X and Z = 0
  ## Y can be anything
  result = P.x.isZero() and P.z.isZero()

func setInf*(P: var ECP_ShortW_Prj) {.inline.} =
  ## Set ``P`` to infinity
  P.x.setZero()
  P.y.setOne()
  P.z.setZero()

func `==`*(P, Q: ECP_ShortW_Prj): SecretBool =
  ## Constant-time equality check
  ## This is a costly operation
  # Reminder: the representation is not unique
  type F = ECP_ShortW_Prj.F

  var a{.noInit.}, b{.noInit.}: F

  a.prod(P.x, Q.z)
  b.prod(Q.x, P.z)
  result = a == b

  a.prod(P.y, Q.z)
  b.prod(Q.y, P.z)
  result = result and a == b

  # Ensure a zero-init point doesn't propagate 0s and match any
  result = result and not(P.isInf() xor Q.isInf())

func ccopy*(P: var ECP_ShortW_Prj, Q: ECP_ShortW_Prj, ctl: SecretBool) {.inline.} =
  ## Constant-time conditional copy
  ## If ctl is true: Q is copied into P
  ## if ctl is false: Q is not copied and P is unmodified
  ## Time and memory accesses are the same whether a copy occurs or not
  for fP, fQ in fields(P, Q):
    ccopy(fP, fQ, ctl)

func trySetFromCoordsXandZ*[F; G](
       P: var ECP_ShortW_Prj[F, G],
       x, z: F): SecretBool =
  ## Try to create a point the elliptic curve
  ## Y²Z = X³ + aXZ² + bZ³ (projective coordinates)
  ## y² = x³ + a x + b     (affine coordinate)
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

  P.x.prod(x, z)
  P.y *= z
  P.z = z

func trySetFromCoordX*[F; G](
       P: var ECP_ShortW_Prj[F, G],
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
  P.z.setOne()

func neg*(P: var ECP_ShortW_Prj, Q: ECP_ShortW_Prj) {.inline.} =
  ## Negate ``P``
  P.x = Q.x
  P.y.neg(Q.y)
  P.z = Q.z

func neg*(P: var ECP_ShortW_Prj) {.inline.} =
  ## Negate ``P``
  P.y.neg()

func cneg*(P: var ECP_ShortW_Prj, ctl: CTBool) {.inline.} =
  ## Conditional negation.
  ## Negate if ``ctl`` is true
  P.y.cneg(ctl)

func sum*[F; G: static Subgroup](
       r: var ECP_ShortW_Prj[F, G],
       P, Q: ECP_ShortW_Prj[F, G]
     ) {.meter.} =
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
  ## ``r`` may alias P
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

  when F.C.getCoefA() == 0:
    var t0 {.noInit.}, t1 {.noInit.}, t2 {.noInit.}, t3 {.noInit.}, t4 {.noInit.}: F
    var x3 {.noInit.}, y3 {.noInit.}, z3 {.noInit.}: F
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
    when G == G2 and F.C.getSexticTwist() == D_Twist:
      t3 *= SexticNonResidue
    t4.sum(P.y, P.z)          # 9.  t₄ <- Y₁ + Z₁
    x3.sum(Q.y, Q.z)          # 10. X₃ <- Y₂ + Z₂
    t4 *= x3                  # 11. t₄ <- t₄ X₃
    x3.sum(t1, t2)            # 12. X₃ <- t₁ + t₂   X₃ = Y₁Y₂ + Z₁Z₂
    t4 -= x3                  # 13. t₄ <- t₄ - X₃   t₄ = (Y₁ + Z₁)(Y₂ + Z₂) - (Y₁Y₂ + Z₁Z₂) = Y₁Z₂ + Y₂Z₁
    when G == G2 and F.C.getSexticTwist() == D_Twist:
      t4 *= SexticNonResidue
    x3.sum(P.x, P.z)          # 14. X₃ <- X₁ + Z₁
    y3.sum(Q.x, Q.z)          # 15. Y₃ <- X₂ + Z₂
    x3 *= y3                  # 16. X₃ <- X₃ Y₃     X₃ = (X₁+Z₁)(X₂+Z₂)
    y3.sum(t0, t2)            # 17. Y₃ <- t₀ + t₂   Y₃ = X₁ X₂ + Z₁ Z₂
    y3.diff(x3, y3)           # 18. Y₃ <- X₃ - Y₃   Y₃ = (X₁ + Z₁)(X₂ + Z₂) - (X₁ X₂ + Z₁ Z₂) = X₁Z₂ + X₂Z₁
    when G == G2 and F.C.getSexticTwist() == D_Twist:
      t0 *= SexticNonResidue
      t1 *= SexticNonResidue
    x3.double(t0)             # 19. X₃ <- t₀ + t₀   X₃ = 2 X₁X₂
    t0 += x3                  # 20. t₀ <- X₃ + t₀   t₀ = 3 X₁X₂
    t2 *= b3                  # 21. t₂ <- 3b t₂     t₂ = 3bZ₁Z₂
    when G == G2 and F.C.getSexticTwist() == M_Twist:
      t2 *= SexticNonResidue
    z3.sum(t1, t2)            # 22. Z₃ <- t₁ + t₂   Z₃ = Y₁Y₂ + 3bZ₁Z₂
    t1 -= t2                  # 23. t₁ <- t₁ - t₂   t₁ = Y₁Y₂ - 3bZ₁Z₂
    y3 *= b3                  # 24. Y₃ <- 3b Y₃     Y₃ = 3b(X₁Z₂ + X₂Z₁)
    when G == G2 and F.C.getSexticTwist() == M_Twist:
      y3 *= SexticNonResidue
    x3.prod(t4, y3)           # 25. X₃ <- t₄ Y₃     X₃ = 3b(Y₁Z₂ + Y₂Z₁)(X₁Z₂ + X₂Z₁)
    t2.prod(t3, t1)           # 26. t₂ <- t₃ t₁     t₂ = (X₁Y₂ + X₂Y₁) (Y₁Y₂ - 3bZ₁Z₂)
    r.x.diff(t2, x3)          # 27. X₃ <- t₂ - X₃   X₃ = (X₁Y₂ + X₂Y₁) (Y₁Y₂ - 3bZ₁Z₂) - 3b(Y₁Z₂ + Y₂Z₁)(X₁Z₂ + X₂Z₁)
    y3 *= t0                  # 28. Y₃ <- Y₃ t₀     Y₃ = 9bX₁X₂ (X₁Z₂ + X₂Z₁)
    t1 *= z3                  # 29. t₁ <- t₁ Z₃     t₁ = (Y₁Y₂ - 3bZ₁Z₂)(Y₁Y₂ + 3bZ₁Z₂)
    r.y.sum(y3, t1)           # 30. Y₃ <- t₁ + Y₃   Y₃ = (Y₁Y₂ + 3bZ₁Z₂)(Y₁Y₂ - 3bZ₁Z₂) + 9bX₁X₂ (X₁Z₂ + X₂Z₁)
    t0 *= t3                  # 31. t₀ <- t₀ t₃     t₀ = 3X₁X₂ (X₁Y₂ + X₂Y₁)
    z3 *= t4                  # 32. Z₃ <- Z₃ t₄     Z₃ = (Y₁Y₂ + 3bZ₁Z₂)(Y₁Z₂ + Y₂Z₁)
    r.z.sum(z3, t0)           # 33. Z₃ <- Z₃ + t₀   Z₃ = (Y₁Z₂ + Y₂Z₁)(Y₁Y₂ + 3bZ₁Z₂) + 3X₁X₂ (X₁Y₂ + X₂Y₁)
  else:
    {.error: "Not implemented.".}

func madd*[F; G: static Subgroup](
       r: var ECP_ShortW_Prj[F, G],
       P: ECP_ShortW_Prj[F, G],
       Q: ECP_ShortW_Aff[F, G]
     ) {.meter.} =
  ## Elliptic curve mixed addition for Short Weierstrass curves
  ## with p in Projective coordinates and Q in affine coordinates
  ##
  ##   R = P + Q
  ##
  ## ``r`` may alias P

  when F.C.getCoefA() == 0:
    var t0 {.noInit.}, t1 {.noInit.}, t2 {.noInit.}, t3 {.noInit.}, t4 {.noInit.}: F
    var x3 {.noInit.}, y3 {.noInit.}, z3 {.noInit.}: F
    const b3 = 3 * F.C.getCoefB()

    # Algorithm 8 for curves: y² = x³ + b
    # X₃ = (X₁Y₂ + X₂Y₁)(Y₁Y₂ − 3bZ₁)
    #     − 3b(Y₁ + Y₂Z₁)(X₁ + X₂Z₁)
    # Y₃ = (Y₁Y₂ + 3bZ₁)(Y₁Y₂ − 3bZ₁)
    #     + 9bX₁X₂ (X₁ + X₂Z₁)
    # Z₃= (Y₁ + Y₂Z₁)(Y₁Y₂ + 3bZ₁) + 3 X₁X₂ (X₁Y₂ + X₂Y₁)
    #
    # Note¹⁰ mentions that due to Qz = 1, cannot be
    # the point at infinity.
    # We solve that by conditional copies.
    t0.prod(P.x, Q.x)         # 1.  t₀ <- X₁ X₂
    t1.prod(P.y, Q.y)         # 2.  t₁ <- Y₁ Y₂
    t3.sum(P.x, P.y)          # 3.  t₃ <- X₁ + Y₁ ! error in paper
    t4.sum(Q.x, Q.y)          # 4.  t₄ <- X₂ + Y₂ ! error in paper
    t3 *= t4                  # 5.  t₃ <- t₃ * t₄
    t4.sum(t0, t1)            # 6.  t₄ <- t₀ + t₁
    t3 -= t4                  # 7.  t₃ <- t₃ - t₄, t₃ = (X₁ + Y₁)(X₂ + Y₂) - (X₁ X₂ + Y₁ Y₂) = X₁Y₂ + X₂Y₁
    when G == G2 and F.C.getSexticTwist() == D_Twist:
      t3 *= SexticNonResidue
    t4.prod(Q.y, P.z)         # 8.  t₄ <- Y₂ Z₁
    t4 += P.y                 # 9.  t₄ <- t₄ + Y₁, t₄ = Y₁+Y₂Z₁
    when G == G2 and F.C.getSexticTwist() == D_Twist:
      t4 *= SexticNonResidue
    y3.prod(Q.x, P.z)         # 10. Y₃ <- X₂ Z₁
    y3 += P.x                 # 11. Y₃ <- Y₃ + X₁, Y₃ = X₁ + X₂Z₁
    when G == G2 and F.C.getSexticTwist() == D_Twist:
      t0 *= SexticNonResidue
      t1 *= SexticNonResidue
    x3.double(t0)             # 12. X₃ <- t₀ + t₀
    t0 += x3                  # 13. t₀ <- X₃ + t₀, t₀ = 3X₁X₂
    t2 = P.z
    t2 *= b3                  # 14. t₂ <- 3bZ₁
    when G == G2 and F.C.getSexticTwist() == M_Twist:
      t2 *= SexticNonResidue
    z3.sum(t1, t2)            # 15. Z₃ <- t₁ + t₂, Z₃ = Y₁Y₂ + 3bZ₁
    t1 -= t2                  # 16. t₁ <- t₁ - t₂, t₁ = Y₁Y₂ - 3bZ₁
    y3 *= b3                  # 17. Y₃ <- 3bY₃,    Y₃ = 3b(X₁ + X₂Z₁)
    when G == G2 and F.C.getSexticTwist() == M_Twist:
      y3 *= SexticNonResidue
    x3.prod(t4, y3)           # 18. X₃ <- t₄ Y₃,   X₃ = (Y₁ + Y₂Z₁) 3b(X₁ + X₂Z₁)
    t2.prod(t3, t1)           # 19. t₂ <- t₃ t₁,   t₂ = (X₁Y₂ + X₂Y₁)(Y₁Y₂ - 3bZ₁)
    x3.diff(t2, x3)           # 20. X₃ <- t₂ - X₃, X₃ = (X₁Y₂ + X₂Y₁)(Y₁Y₂ - 3bZ₁) - 3b(Y₁ + Y₂Z₁)(X₁ + X₂Z₁)
    y3 *= t0                  # 21. Y₃ <- Y₃ t₀,   Y₃ = 9bX₁X₂ (X₁ + X₂Z₁)
    t1 *= z3                  # 22. t₁ <- t₁ Z₃,   t₁ = (Y₁Y₂ - 3bZ₁)(Y₁Y₂ + 3bZ₁)
    y3 += t1                  # 23. Y₃ <- t₁ + Y₃, Y₃ = (Y₁Y₂ + 3bZ₁)(Y₁Y₂ - 3bZ₁) + 9bX₁X₂ (X₁ + X₂Z₁)
    t0 *= t3                  # 31. t₀ <- t₀ t₃,   t₀ = 3X₁X₂ (X₁Y₂ + X₂Y₁)
    z3 *= t4                  # 32. Z₃ <- Z₃ t₄,   Z₃ = (Y₁Y₂ + 3bZ₁)(Y₁ + Y₂Z₁)
    z3 += t0                  # 33. Z₃ <- Z₃ + t₀, Z₃ = (Y₁ + Y₂Z₁)(Y₁Y₂ + 3bZ₁) + 3X₁X₂ (X₁Y₂ + X₂Y₁)

    # Deal with infinity point. r and P might alias.
    let inf = Q.isInf()
    x3.ccopy(P.x, inf)
    y3.ccopy(P.y, inf)
    z3.ccopy(P.z, inf)

    r.x = x3
    r.y = y3
    r.z = z3

  else:
    {.error: "Not implemented.".}

func double*[F; G: static Subgroup](
       r: var ECP_ShortW_Prj[F, G],
       P: ECP_ShortW_Prj[F, G]
     ) {.meter.} =
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
  ## ``r`` may alias P
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
    var t0 {.noInit.}, t1 {.noInit.}, t2 {.noInit.}: F
    var x3 {.noInit.}, y3 {.noInit.}, z3 {.noInit.}: F
    const b3 = 3 * F.C.getCoefB()

    # Algorithm 9 for curves:
    # 6M + 2S + 1 mul(3b) + 9a
    #
    # X₃ = 2XY(Y² - 9bZ²)
    # Y₃ = (Y² - 9bZ²)(Y² + 3bZ²) + 24bY²Z²
    # Z₃ = 8Y³Z
    when G == G2 and F.C.getSexticTwist() == D_Twist:
      var snrY {.noInit.}: F
      snrY.prod(P.y, SexticNonResidue)
      t0.square(P.y)
      t0 *= SexticNonResidue
    else:
      template snrY: untyped = P.y
      t0.square(P.y)          # 1.  t₀ <- Y Y
    z3.double(t0)             # 2.  Z₃ <- t₀ + t₀
    z3.double()               # 3.  Z₃ <- Z₃ + Z₃
    z3.double()               # 4.  Z₃ <- Z₃ + Z₃   Z₃ = 8Y²
    t1.prod(snrY, P.z)        # 5.  t₁ <- Y Z
    t2.square(P.z)            # 6.  t₂ <- Z Z
    t2 *= b3                  # 7.  t₂ <- 3b t₂
    when G == G2 and F.C.getSexticTwist() == M_Twist:
      t2 *= SexticNonResidue
    x3.prod(t2, z3)           # 8.  X₃ <- t₂ Z₃
    y3.sum(t0, t2)            # 9.  Y₃ <- t₀ + t₂
    r.z.prod(z3, t1)          # 10. Z₃ <- t₁ Z₃
    t1.double(t2)             # 11. t₁ <- t₂ + t₂
    t2 += t1                  # 12. t₂ <- t₁ + t₂
    t0 -= t2                  # 13. t₀ <- t₀ - t₂
    y3 *= t0                  # 14. Y₃ <- t₀ Y₃
    t1.prod(P.x, snrY)        # 16. t₁ <- X Y     - snrY aliases P.y on Fp
    r.y.sum(y3, x3)           # 15. Y₃ <- X₃ + Y₃
    x3.prod(t0, t1)           # 17. X₃ <- t₀ t₁
    r.x.double(x3)            # 18. X₃ <- X₃ + X₃
  else:
    {.error: "Not implemented.".}

func `+=`*(P: var ECP_ShortW_Prj, Q: ECP_ShortW_Prj) {.inline.} =
  ## In-place point addition
  P.sum(P, Q)

func `+=`*(P: var ECP_ShortW_Prj, Q: ECP_ShortW_Aff) {.inline.} =
  ## In-place mixed point addition
  P.madd(P, Q)

func double*(P: var ECP_ShortW_Prj) {.inline.} =
  ## In-place EC doubling
  P.double(P)

func diff*(r: var ECP_ShortW_Prj, P, Q: ECP_ShortW_Prj) {.inline.} =
  ## r = P - Q
  ## Can handle r and Q aliasing
  var nQ {.noInit.}: typeof(Q)
  nQ.neg(Q)
  r.sum(P, nQ)

func `-=`*(P: var ECP_ShortW_Prj, Q: ECP_ShortW_Prj) {.inline.} =
  ## In-place point substraction
  var nQ {.noInit.}: typeof(Q)
  nQ.neg(Q)
  P.sum(P, nQ)

func `-=`*(P: var ECP_ShortW_Prj, Q: ECP_ShortW_Aff) {.inline.} =
  ## In-place point substraction
  var nQ {.noInit.}: typeof(Q)
  nQ.neg(Q)
  P.madd(P, nQ)

template affine*[F, G](_: type ECP_ShortW_Prj[F, G]): typedesc =
  ## Returns the affine type that corresponds to the Jacobian type input
  ECP_ShortW_Aff[F, G]

template projective*[F, G](_: type ECP_ShortW_Aff[F, G]): typedesc =
  ## Returns the projective type that corresponds to the affine type input
  ECP_ShortW_Prj[F, G]


func affine*[F, G](
       aff: var ECP_ShortW_Aff[F, G],
       proj: ECP_ShortW_Prj[F, G]) {.meter.} =
  var invZ {.noInit.}: F
  invZ.inv(proj.z)

  aff.x.prod(proj.x, invZ)
  aff.y.prod(proj.y, invZ)

func fromAffine*[F, G](
       proj: var ECP_ShortW_Prj[F, G],
       aff: ECP_ShortW_Aff[F, G]) {.inline.} =
  proj.x = aff.x
  proj.y = aff.y
  proj.z.setOne()

  let inf = aff.isInf()
  proj.x.csetZero(inf)
  proj.y.csetOne(inf)
  proj.z.csetZero(inf)

# Variable-time
# -------------

# In some primitives like FFTs, the extra work done for constant-time
# is amplified by O(n log n) which may result in extra tens of minutes
# to hours of computations. Those primitives do not need constant-timeness.

func sum_vartime*[F; G: static Subgroup](
       r: var ECP_ShortW_Prj[F, G],
       p, q: ECP_ShortW_Prj[F, G])
       {.tags:[VarTime], meter.} =
  ## **Variable-time** homogeneous projective addition
  ##
  ## This MUST NOT be used with secret data.
  ##
  ## This is highly VULNERABLE to timing attacks and power analysis attacks.

  if p.isInf().bool:
    r = q
    return
  if q.isInf().bool:
    r = p
    return

  # Accelerate mixed additions
  let isPz1 = p.z.isOne().bool
  let isQz1 = q.z.isOne().bool

  # Addition, Cohen et al, 1998
  # General case:            12M + 4S + 6add + 1*2
  # https://hyperelliptic.org/EFD/g1p/auto-shortw-projective.html#addition-add-1998-cmo-2
  #
  # Y₁Z₂ = Y₁*Z₂
  # X₁Z₂ = X₁*Z₂
  # Z₁Z₂ = Z₁*Z₂
  # u = Y₂*Z₁-Y₁Z₂
  # uu = u²
  # v = X₂*Z₁-X₁Z₂
  # vv = v²
  # vvv = v*vv
  # R = vv*X₁Z₂
  # A = uu*Z₁Z₂-vvv-2*R
  # X₃ = v*A
  # Y₃ = u*(R-A)-vvv*Y₁Z₂
  # Z₃ = vvv*Z₁Z₂

  var Y1Z2 {.noInit.}, R {.noInit.}: F
  var U {.noInit.}, V {.noInit.}: F

  if isQz1:
    R = p.x
    Y1Z2 = p.y
  else:
    R.prod(p.x, q.z)     # X₁Z₂
    Y1Z2.prod(p.y, q.z)
  if isPz1:
    U = q.y
    V = q.x
  else:
    U.prod(q.y, p.z)
    V.prod(q.x, p.z)
  V -= R

  if V.isZero().bool:    # Same x coordinate
    if bool(U == Y1Z2):  # case P = Q
      r.double(p)
      return
    else:
      r.setInf()         # case P = -Q
      return

  var VVV{.noInit.}: F

  VVV.square(V, skipFinalSub = true)
  R *= VVV
  VVV *= V

  r.y.diff(U, Y1Z2)      # u = Y₂*Z₁-Y₁Z₂
  U.square(r.y)          # uu = u²

  # A and Z₃ depend on Z₁Z₂
  template A:untyped = U
  if isQz1:
    if isPz1:
      r.z = VVV
    else:
      A.prod(U, p.z)
      r.z.prod(VVV, p.z)
  else:
    if isPz1:
      A.prod(U, q.z)
      r.z.prod(VVV, q.z)
    else:
      r.z.prod(p.z, q.z, skipFinalSub = true)
      A.prod(U, r.z)
      r.z *= VVV

  A -= VVV
  A -= R
  A -= R                  # A = uu*Z₁Z₂-vvv-2*R

  r.x.prod(V, A)

  R -= A
  Y1Z2 *= VVV
  r.y *= R
  r.y -= Y1Z2

func madd_vartime*[F; G: static Subgroup](
       r: var ECP_ShortW_Prj[F, G],
       p: ECP_ShortW_Prj[F, G],
       q: ECP_ShortW_Aff[F, G])
       {.tags:[VarTime], meter.} =
  ## **Variable-time** homogeneous projective mixed addition
  ##
  ## This MUST NOT be used with secret data.
  ##
  ## This is highly VULNERABLE to timing attacks and power analysis attacks.

  if p.isInf().bool:
    r.fromAffine(q)
    return
  if q.isInf().bool:
    r = p
    return

  # Accelerate mixed additions
  let isPz1 = p.z.isOne().bool

  # Addition, Cohen et al, 1998
  # General case:            12M + 4S + 6add + 1*2
  # https://hyperelliptic.org/EFD/g1p/auto-shortw-projective.html#addition-add-1998-cmo-2
  #
  # Y₁Z₂ = Y₁*Z₂
  # X₁Z₂ = X₁*Z₂
  # Z₁Z₂ = Z₁*Z₂
  # u = Y₂*Z₁-Y₁Z₂
  # uu = u²
  # v = X₂*Z₁-X₁Z₂
  # vv = v²
  # vvv = v*vv
  # R = vv*X₁Z₂
  # A = uu*Z₁Z₂-vvv-2*R
  # X₃ = v*A
  # Y₃ = u*(R-A)-vvv*Y₁Z₂
  # Z₃ = vvv*Z₁Z₂

  var Y1Z2 {.noInit.}, R {.noInit.}: F
  var U {.noInit.}, V {.noInit.}: F

  R = p.x
  Y1Z2 = p.y

  if isPz1:
    U = q.y
    V = q.x
  else:
    U.prod(q.y, p.z)
    V.prod(q.x, p.z)
  V -= R

  if V.isZero().bool:    # Same x coordinate
    if bool(U == Y1Z2):  # case P = Q
      r.double(p)
      return
    else:
      r.setInf()         # case P = -Q
      return

  var VVV{.noInit.}: F

  VVV.square(V, skipFinalSub = true)
  R *= VVV
  VVV *= V

  r.y.diff(U, Y1Z2)      # u = Y₂*Z₁-Y₁Z₂
  U.square(r.y)          # uu = u²

  # A and Z₃ depend on Z₁Z₂
  template A:untyped = U
  if isPz1:
    r.z = VVV
  else:
    A.prod(U, p.z)
    r.z.prod(VVV, p.z)

  A -= VVV
  A -= R
  A -= R                  # A = uu*Z₁Z₂-vvv-2*R

  r.x.prod(V, A)

  R -= A
  Y1Z2 *= VVV
  r.y *= R
  r.y -= Y1Z2

func diff_vartime*(r: var ECP_ShortW_Prj, P, Q: ECP_ShortW_Prj) {.inline.} =
  ## r = P - Q
  ##
  ## This MUST NOT be used with secret data.
  ##
  ## This is highly VULNERABLE to timing attacks and power analysis attacks.
  var nQ {.noInit.}: typeof(Q)
  nQ.neg(Q)
  r.sum_vartime(P, nQ)

func msub_vartime*(r: var ECP_ShortW_Prj, P: ECP_ShortW_Prj, Q: ECP_ShortW_Aff) {.inline.} =
  ## r = P - Q
  ##
  ## This MUST NOT be used with secret data.
  ##
  ## This is highly VULNERABLE to timing attacks and power analysis attacks.
  var nQ {.noInit.}: typeof(Q)
  nQ.neg(Q)
  r.madd_vartime(P, nQ)