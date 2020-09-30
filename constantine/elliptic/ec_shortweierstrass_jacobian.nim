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

import ../io/io_fields

# ############################################################
#
#             Elliptic Curve in Short Weierstrass form
#                 with Jacobian Coordinates
#
# ############################################################

type ECP_ShortW_Jac*[F] = object
  ## Elliptic curve point for a curve in Short Weierstrass form
  ##   y² = x³ + a x + b
  ##
  ## over a field F
  ##
  ## in Jacobian coordinates (X, Y, Z)
  ## corresponding to (x, y) with X = xZ² and Y = yZ³
  ##
  ## Note that jacobian coordinates are not unique
  x*, y*, z*: F

func `==`*[F](P, Q: ECP_ShortW_Jac[F]): SecretBool =
  ## Constant-time equality check
  ## This is a costly operation
  # Reminder: the representation is not unique

  var z1z1 {.noInit.}, z2z2 {.noInit.}: F
  var a{.noInit.}, b{.noInit.}: F

  z1z1.square(P.z)
  z2z2.square(Q.z)

  a.prod(P.x, z2z2)
  b.prod(Q.x, z1z1)
  result = a == b

  a.prod(P.y, Q.z)
  b.prod(Q.y, P.z)
  a *= z2z2
  b *= z1z1
  result = result and a == b

func isInf*(P: ECP_ShortW_Jac): SecretBool =
  ## Returns true if P is an infinity point
  ## and false otherwise
  ##
  ## Note: the jacobian coordinates equation is
  ##       Y² = X³ + aXZ⁴ + bZ⁶
  ## A "zero" point is any point with coordinates X and Z = 0
  ## Y can be anything
  result = P.z.isZero()

func setInf*(P: var ECP_ShortW_Jac) =
  ## Set ``P`` to infinity
  P.x.setOne()
  P.y.setOne()
  P.z.setZero()

func ccopy*(P: var ECP_ShortW_Jac, Q: ECP_ShortW_Jac, ctl: SecretBool) =
  ## Constant-time conditional copy
  ## If ctl is true: Q is copied into P
  ## if ctl is false: Q is not copied and P is unmodified
  ## Time and memory accesses are the same whether a copy occurs or not
  for fP, fQ in fields(P, Q):
    ccopy(fP, fQ, ctl)

func trySetFromCoordsXandZ*[F](P: var ECP_ShortW_Jac[F], x, z: F): SecretBool =
  ## Try to create a point the elliptic curve
  ## Y² = X³ + aXZ⁴ + bZ⁶  (Jacobian coordinates)
  ## y² = x³ + a x + b     (affine coordinate)
  ## return true and update `P` if `x` leads to a valid point
  ## return false otherwise, in that case `P` is undefined.
  ##
  ## Note: Dedicated robust procedures for hashing-to-curve
  ##       will be provided, this is intended for testing purposes.
  P.y.curve_eq_rhs(x)
  # TODO: supports non p ≡ 3 (mod 4) modulus like BLS12-377
  result = sqrt_if_square(P.y)

  var z2 {.noInit.}: F
  z2.square(z)
  P.x.prod(x, z2)
  P.y *= z2
  P.y *= z
  P.z = z

func trySetFromCoordX*[F](P: var ECP_ShortW_Jac[F], x: F): SecretBool =
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
  result = sqrt_if_square(P.y)
  P.x = x
  P.z.setOne()

func neg*(P: var ECP_ShortW_Jac, Q: ECP_ShortW_Jac) =
  ## Negate ``P``
  P.x = Q.x
  P.y.neg(Q.y)
  P.z = Q.z

func neg*(P: var ECP_ShortW_Jac) =
  ## Negate ``P``
  P.y.neg()

func cneg*(P: var ECP_ShortW_Jac, ctl: CTBool) =
  ## Conditional negation.
  ## Negate if ``ctl`` is true
  P.y.cneg(ctl)

func sum*[F](
       r: var ECP_ShortW_Jac[F],
       P, Q: ECP_ShortW_Jac[F]
     ) =
  ## Elliptic curve point addition for Short Weierstrass curves in Jacobian coordinates
  ##
  ##   R = P + Q
  ##
  ## Short Weierstrass curves have the following equation in Jacobian coordinates
  ##   Y² = X³ + aXZ⁴ + bZ⁶
  ## from the affine equation
  ##   y² = x³ + a x + b
  ##
  ## ``r`` is initialized/overwritten with the sum
  ##
  ## Implementation is constant-time, in particular it will not expose
  ## that P == Q or P == -Q or P or Q are the infinity points
  ## to simple side-channel attacks (SCA)
  ## This is done by using a "complete" or "exception-free" addition law.
  #
  # Implementation, see write-up at the bottom.
  # We fuse addition and doubling with condition copy by swapping
  # terms with the following table
  #
  # |    Addition, Cohen et al, 1998     | Doubling, modified from Lange, 2009 |
  # |       12M + 4S + 6add + 1*2        |    3M + 4S + 4add + 1*2 + 1*half    |
  # | ---------------------------------- | ----------------------------------- |
  # | Z₁Z₁ = Z₁²                         |                                     |
  # | Z₂Z₂ = Z₂²                         |                                     |
  # |                                    |                                     |
  # | U₁ = X₁*Z₂Z₂                       |                                     |
  # | U₂ = X₂*Z₁Z₁                       |                                     |
  # | S₁ = Y₁*Z₂*Z₂Z₂                    |                                     |
  # | S₂ = Y₂*Z₁*Z₁Z₁                    |                                     |
  # | H  = U₂-U₁      # P=-Q, P=Inf, P=Q |                                     |
  # | R  = S₂-S₁      # Q=Inf            |                                     |
  # |                                    |                                     |
  # | Z₃ = Z₁*Z₂*H                       | Z₃ = Y₁*Z₁                          |
  # |                                    |                                     |
  # |                                    |                                     |
  # | HH  = H²                           | B  = Y₁²                            |
  # | V   = U₁*HH                        | D  = X₁*B                           |
  # | HHH = H*HH                         | A  = X₁²                            |
  # | S₁HHH = S₁*HHH                     | C  = B²                             |
  # |                                    | E  = 3A/2                           |
  # |                                    |                                     |
  # | X₃ = R²-2*V-HHH                    | X₃ = E²-2*D                         |
  # | Y₃ = R*(V-X₃)-S₁HHH                | Y₃ = E*(D-X₃)-C                     |

  var Z1Z1 {.noInit.}, U1 {.noInit.}, S1 {.noInit.}, H {.noInit.}, R {.noinit.}: F

  block: # Addition-only, check for exceptional cases
    var Z2Z2 {.noInit.}, U2 {.noInit.}, S2 {.noInit.}: F
    Z2Z2.square(Q.z)
    S1.prod(Q.z, Z2Z2)
    S1 *= P.y           # S₁ = Y₁*Z₂³
    U1.prod(P.x, Z2Z2)  # U₁ = X₁*Z₂²

    Z1Z1.square(P.z)
    S2.prod(P.z, Z1Z1)
    S2 *= Q.y           # S₂ = Y₂*Z₁³
    U2.prod(Q.x, Z1Z1)  # U₂ = X₂*Z₁²

    H.diff(U2, U1)      # H = U₂-U₁
    R.diff(S2, S1)      # R = S₂-S₁

  # Exceptional cases
  # Expressing H as affine, if H == 0, P == Q or -Q
  # H = U₂-U₁ = X₂*Z₁² - X₁*Z₂² = x₂*Z₂²*Z₁² - x₁*Z₁²*Z₂²
  # if H == 0 && R == 0, P = Q -> doubling
  # if only H == 0, P = -Q     -> infinity, implied in Z₃ = Z₁*Z₂*H = 0
  # if only R == 0, P and Q are related by the cubic root endomorphism
  let isDbl = H.isZero() and R.isZero()

  # Rename buffers under the form (add_or_dbl)
  template H_or_Y: untyped = H
  H.ccopy(P.y, isDbl)

  block: # Z₃ = Z₁*Z₂*H
    var t{.noInit.}: F
    t.prod(P.z, H_or_Y)       #      Z₁H   (add) or Y₁Z₁ (dbl)
    r.z = t
    t *= Q.z                  #      Z₁Z₂H (add) or garbage (dbl)
    r.z.ccopy(t, not isDbl)   # Z₃ = Z₁Z₂H (add) or Y₁Z₁ (dbl)

  # Rename buffers under the form (add_or_dbl)
  template H_or_X1: untyped = H_or_Y
  template V_or_D: untyped = U1
  template HHH_or_A: untyped = H
  template S1HHH_or_C: untyped = S1
  template R_or_E: untyped = R
  block:
    var t{.noInit.}: F
    t.square(H_or_Y)             # HH  = H²   (add) or B = Y₁² (dbl)

    U1.ccopy(P.x, isDbl)         # U₁         (add) or X₁      (dbl)
    V_or_D *= t                  # V = U₁*HH  (add) or D = X₁B (dbl)

    let B = t

    HHH_or_A.ccopy(P.x, isDbl)   # H          (add) or X₁      (dbl)
    t.ccopy(P.x, isDbl)          # HH         (add) or X₁      (dbl)
    HHH_or_A *= t                # HHH = H*HH (add) or A = X₁² (dbl)

    block:
      var E = HHH_or_A
      E.div2()
      E += HHH_or_A
      R_or_E.ccopy(E, isDbl)       # R = S₂-S₁  (add) or E = 3A/2 (dbl)

    t = HHH_or_A
    t.ccopy(B, isDbl)            # HHH   (add) or B = Y₁² (dbl)
    S1HHH_or_C.ccopy(B, isDbl)   # S₁    (add) or B = Y₁² (dbl)
    S1HHH_or_C *= t              # S₁HHH (add) or C = B²  (dbl)

  block:
    r.y = V_or_D

    V_or_D *= 2
    r.x.square(R_or_E)
    r.x -= V_or_D
    r.x.csub(HHH_or_A, not isDbl) # X₃ = R²-2*V-HHH (add) or X₃ = E²-2*D (dbl)

    r.y -= r.x
    r.y *= R_or_E
    r.y -= S1HHH_or_C             # Y₃ = R*(V-X₃)-S₁HHH or Y₃ = E*(D-X₃)-C

  # if P or R were infinity points they would have spread 0 with Z₁Z₂
  block: # Infinity points
    r.ccopy(Q, P.isInf())
    r.ccopy(P, Q.isInf())

func double*[F](
       r: var ECP_ShortW_Jac[F],
       P: ECP_ShortW_Jac[F]
     ) =
  ## Elliptic curve point doubling for Short Weierstrass curves in projective coordinate
  ##
  ##   R = [2] P
  ##
  ## Short Weierstrass curves have the following equation in Jacobian coordinates
  ##   Y² = X³ + aXZ⁴ + bZ⁶
  ## from the affine equation
  ##   y² = x³ + a x + b
  ##
  ## ``r`` is initialized/overwritten with the sum
  ##
  ## Implementation is constant-time.
  # "dbl-2009-l" doubling formula - https://www.hyperelliptic.org/EFD/g1p/auto-shortw-jacobian-0.html#doubling-dbl-2009-l
  #
  #     Cost: 2M + 5S + 6add + 3*2 + 1*3 + 1*8.
  #     Source: 2009.04.01 Lange.
  #     Explicit formulas:
  #
  #           A = X₁²
  #           B = Y₁²
  #           C = B²
  #           D = 2*((X₁+B)²-A-C)
  #           E = 3*A
  #           F = E²
  #           X₃ = F-2*D
  #           Y₃ = E*(D-X₃)-8*C
  #           Z₃ = 2*Y₁*Z₁
  #
  var A {.noInit.}, B{.noInit.}, C {.noInit.}, D{.noInit.}: F
  A.square(P.x)
  B.square(P.y)
  C.square(B)
  D.sum(P.x, B)
  D.square()
  D -= A
  D -= C
  D *= 2             # D = 2*((X₁+B)²-A-C)
  A *= 3             # E = 3*A
  r.x.square(A)      # F = E²

  B.double(D)
  r.x -= B           # X₃ = F-2*D

  B.diff(D, r.x)     # (D-X₃)
  r.y.prod(A, B)     # E*(D-X₃)
  C *= 8
  r.y -= C           # Y₃ = E*(D-X₃)-8*C

  r.z.prod(P.y, P.z)
  r.z *= 2           # Z₃ = 2*Y₁*Z₁

func `+=`*(P: var ECP_ShortW_Jac, Q: ECP_ShortW_Jac) =
  ## In-place point addition
  # TODO test for aliasing support
  var tmp {.noInit.}: ECP_ShortW_Jac
  tmp.sum(P, Q)
  P = tmp

func double*(P: var ECP_ShortW_Jac) =
  var tmp {.noInit.}: ECP_ShortW_Jac
  tmp.double(P)
  P = tmp

func diff*(r: var ECP_ShortW_Jac,
           P, Q: ECP_ShortW_Jac
     ) =
  ## r = P - Q
  ## Can handle r and Q aliasing
  var nQ = Q
  nQ.neg()
  r.sum(P, nQ)

func affineFromJacobian*[F](aff: var ECP_ShortW_Aff[F], jac: ECP_ShortW_Jac) =
  var invZ {.noInit.}, invZ2: F
  invZ.inv(jac.z)
  invZ2.square(invZ)

  aff.x.prod(jac.x, invZ2)
  aff.y.prod(jac.y, invZ)
  aff.y.prod(jac.y, invZ2)

func projectiveFromJacobian*[F](jac: var ECP_ShortW_Jac, aff: ECP_ShortW_Aff[F]) {.inline.} =
  jac.x = aff.x
  jac.y = aff.y
  jac.z.setOne()

# ############################################################
#                                                            #
#      Deriving efficient and complete Jacobian formulae     #
#                                                            #
# ############################################################
#
# We are looking for a complete addition formula,
# that minimize overhead over classic addition formulae
# from the litterature
# and can handle all inputs.
#
# We recall the basic affine addition and doubling formulae
#
# ```
# P + Q = R
# (Px, Py) + (Qx, Qy) = (Rx, Ry)
#
# with
#   Rx = λ² - Px - Qx
#   Ry = λ(Px - Rx) - Py
# and
#   λadd = (Qy - Py) / (Px - Qx)
#   λdbl = (3 Px² + a) / (2 Px)
# ```
#
# Which is also called the "chord-and-tangent" group law.
# Notice that if Px == Qx, addition is undefined, this can happen in 2 cases
# - P == Q, in that case we need to double
# - P == -Q, since -(x,y) = (x,-y) for elliptic curves. In that case we need infinity.
#
# Concretely, that means that it is non-trivial to make the code constant-time
# whichever case we are.
# Furthermore, Renes et al 2015 which introduced complete addition formulae for projective coordinates
# demonstrated that such a law cannot be as efficient for the Jacobian coordinates we are interested in.
#
# Since we can't rely on math, we will need to rely on implementation "details" to achieve our goals.
# First we look back in history at Brier and Joye 2002 unified formulae which uses the same code for addition and doubling:
#
# ```
# λ = ((x₁+x₂)² - x₁x₂ + a)/(y₁+y₂)
# x₃ = λ² - (x₁+x₂)
# 2y₃= λ(x₁+x₂-2x₃) - (y₁+y₂)
# ```
#
# Alas we traded exceptions depending on the same coordinate x
# for exceptions on negated coordinate y.
# This can still happen for P=-Q but also for "unrelated" numbers.
# > We recall that curves with equation `y² = x³ + b` are chosen so that there exist a cubic root of unity modulo r the curve order.
# > Hence x³ ≡ 1 (mod r), we call that root ω
# > And so we have y² = (ωx)³ + b describing a valid point with coordinate (ωx, y)
# > Hence the unified formula cannot handle (x, y) + (ωx, -y)
# > All pairings curves and secp256k1 have that equation form.
#
# Now, all hope is not lost, we recall that unlike in math,
# in actual implementation we havean excellent tool called conditional copy
# so that we can ninja-swap our terms
# provided addition and doubling are resembling each other.
#
# So let's look at the current state of the art formulae.
# I have added the spots where we can detect special conditions like infinity points, doubling and negation,
# and reorganized doubling operations so that they match multiplication/squarings in the addition law
#
# Let's look first at Cohen et al, 1998 formulae
#
# ```
# |    Addition - Cohen et al    |         Doubling any a - Cohen et al         |  Doubling = -3  | Doubling a = 0 |
# | 12M + 4S + 6add + 1*2        | 3M + 6S + 1*a + 4add + 2*2 + 1*3 + 1*4 + 1*8 |                 |       |
# |------------------------------|----------------------------------------------|-----------------|-------|
# | Z₁Z₁ = Z₁²                   | Z₁Z₁ = Z₁²                                   |                 |       |
# | Z₂Z₂ = Z₂²                   |                                              |                 |       |
# |                              |                                              |                 |       |
# | U₁ = X₁*Z₂Z₂                 |                                              |                 |       |
# | U₂ = X₂*Z₁Z₁                 |                                              |                 |       |
# | S₁ = Y₁*Z₂*Z₂Z₂              |                                              |                 |       |
# | S₂ = Y₂*Z₁*Z₁Z₁              |                                              |                 |       |
# | H = U₂-U₁ # P=-Q, P=Inf, P=Q |                                              |                 |       |
# | F = S₂-S₁ # Q=Inf            |                                              |                 |       |
# |                              |                                              |                 |       |
# | HH = H²                      | YY = Y₁²                                     |                 |       |
# | HHH = H*HH                   | M = 3*X₁²+a*ZZ²                              | 3(X₁-Z₁)(X₁+Z₁) | 3*X₁² |
# | V = U₁*HH                    | S = 4*X₁*YY                                  |                 |       |
# |                              |                                              |                 |       |
# | X₃ = R²-HHH-2*V              | X₃ = M²-2*S                                  |                 |       |
# | Y₃ = R*(V-X₃)-S₁*HHH         | Y₃ = M*(S-X₃)-8*YY²                          |                 |       |
# | Z₃ = Z₁*Z₂*H                 | Z₃ = 2*Y₁*Z₁                                 |                 |       |
# ```
#
# This is very promising, as the expensive multiplies and squares n doubling all have a corresponding sister operation.
# Now for Bernstein et al 2007 formulae.
#
# ```
# |    Addition - Bernstein et al    |          Doubling any a - Bernstein et al           |  Doubling = -3  | Doubling a = 0 |
# | 11M + 5S + 9add + 4*2            | 1M + 8S + 1*a + 10add + 2*2 + 1*3 + 1*8             |                 |       |
# |----------------------------------|-----------------------------------------------------|-----------------|-------|
# | Z₁Z₁ = Z₁²                       | Z₁Z₁ = Z₁²                                          |                 |       |
# | Z₂Z₂ = Z₂²                       |                                                     |                 |       |
# |                                  |                                                     |                 |       |
# | U₁ = X₁*Z₂Z₂                     |                                                     |                 |       |
# | U₂ = X₂*Z₁Z₁                     |                                                     |                 |       |
# | S₁ = Y₁*Z₂*Z₂Z₂                  |                                                     |                 |       |
# | S₂ = Y₂*Z₁*Z₁Z₁                  |                                                     |                 |       |
# | H = U₂-U₁     # P=-Q, P=Inf, P=Q |                                                     |                 |       |
# | R = 2*(S₂-S₁) # Q=Inf            |                                                     |                 |       |
# |                                  |                                                     |                 |       |
# |                                  | XX = X₁² (no matching op in addition, extra square) |                 |       |
# |                                  | YYYY (no matching op in addition, extra 2 squares)  |                 |       |
# |                                  |                                                     |                 |       |
# | I = (2*H)²                       | YY = Y₁²                                            |                 |       |
# | J = H*I                          | M = 3*X₁²+a*ZZ²                                     | 3(X₁-Z₁)(X₁+Z₁) | 3*X₁² |
# | V = U₁*I                         | S = 2*((X₁+YY)²-XX-YYYY) = 4*X₁*YY                  |                 |       |
# |                                  |                                                     |                 |       |
# | X₃ = R²-J-2*V                    | X₃ = M²-2*S                                         |                 |       |
# | Y₃ = R*(V-X₃)-2*S₁*J             | Y₃ = M*(S-X₃)-8*YYYY                                |                 |       |
# | Z₃ = ((Z₁+Z₂)²-Z₁Z₁-Z₂Z₂)*H      | Z₃ = (Y₁+Z₁)² - YY - ZZ = 2*Y₁*Z₁                   |                 |       |
# ```
#
# Bernstein et al rewrites multiplication into squaring and 2 substraction.
#
# The first thing to note is that we can't use that trick to compute S in doubling
# and keep doubling resembling addition as we have not computed XX or YYYY yet
# and have no auspicious place to do so before.
#
# The second thing to note is that in the addition, they had to scale Z₃ by 2
# which scaled X₃ by 4 and Y₃ by 8, leading to the doubling in I, r coefficients
#
# Ultimately, it saves 1 mul but it costs 1S 3A 3*2. Here are some benchmarks for reference
#
# | Operation | Fp[BLS12_381] (cycles) | Fp2[BLS12_381] (cycles) | Fp4[BLS12_381] (cycles) |
# |-----------|------------------------|-------------------------|-------------------------|
# | Add       | 14                     | 24                      | 47                      |
# | Sub       | 12                     | 24                      | 46                      |
# | Ccopy     | 5                      | 10                      | 20                      |
# | Div2      | 14                     | 23                      | 42                      |
# | Mul       | 81                     | 337                     | 1229                    |
# | Sqr       | 81                     | 231                     | 939                     |
#
# On G1 this is not good enough
# On G2 it is still not good enough
# On G4 (BLS24) or G8 (BLS48) we can revisit the decision.
#
# Let's focus back to Cohen formulae
#
# ```
# |    Addition - Cohen et al    |         Doubling any a - Cohen et al         |  Doubling = -3  | Doubling a = 0 |
# | 12M + 4S + 6add + 1*2        | 3M + 6S + 1*a + 4add + 2*2 + 1*3 + 1*4 + 1*8 |                 |       |
# |------------------------------|----------------------------------------------|-----------------|-------|
# | Z₁Z₁ = Z₁²                   | Z₁Z₁ = Z₁²                                   |                 |       |
# | Z₂Z₂ = Z₂²                   |                                              |                 |       |
# |                              |                                              |                 |       |
# | U₁ = X₁*Z₂Z₂                 |                                              |                 |       |
# | U₂ = X₂*Z₁Z₁                 |                                              |                 |       |
# | S₁ = Y₁*Z₂*Z₂Z₂              |                                              |                 |       |
# | S₂ = Y₂*Z₁*Z₁Z₁              |                                              |                 |       |
# | H = U₂-U₁ # P=-Q, P=Inf, P=Q |                                              |                 |       |
# | R = S₂-S₁ # Q=Inf            |                                              |                 |       |
# |                              |                                              |                 |       |
# | HH = H²                      | YY = Y₁²                                     |                 |       |
# | HHH = H*HH                   | M = 3*X₁²+a*ZZ²                              | 3(X₁-Z₁)(X₁+Z₁) | 3*X₁² |
# | V = U₁*HH                    | S = 4*X₁*YY                                  |                 |       |
# |                              |                                              |                 |       |
# | X₃ = R²-HHH-2*V              | X₃ = M²-2*S                                  |                 |       |
# | Y₃ = R*(V-X₃)-S₁*HHH         | Y₃ = M*(S-X₃)-8*YY²                          |                 |       |
# | Z₃ = Z₁*Z₂*H                 | Z₃ = 2*Y₁*Z₁                                 |                 |       |
# ```
#
# > Reminder: Jacobian coordinates are related to affine coordinate
# >           the following way (X, Y) <-> (X Z², Y Z³, Z)
#
# The 2, 4, 8 coefficients in respectively `Z₃=2Y₁Z₁`, `S=4X₁YY` and `Y₃=M(S-X₃)-8YY²`
# are not in line with the addition.
# 2 solutions:
# - either we scale the addition Z₃ by 2, which will scale X₃ by 4 and Y₃ by 8 just like Bernstein et al.
# - or we scale the doubling Z₃ by ½, which will scale X₃ by ¼ and Y₃ by ⅛. This is what Bos et al 2014 does for a=-3 curves.
#
# We generalize their approach to all curves and obtain
#
# ```
# |    Addition (Cohen et al)     | Doubling any a (adapted Bos et al, Cohen et al) |   Doubling = -3   | Doubling a = 0 |
# |     12M + 4S + 6add + 1*2     |    3M + 6S + 1*a + 4add + 1*2 + 1*3 + 1half     |                   |                |
# | ----------------------------- | ----------------------------------------------- | ----------------- | -------------- |
# | Z₁Z₁ = Z₁²                    | Z₁Z₁ = Z₁²                                      |                   |                |
# | Z₂Z₂ = Z₂²                    |                                                 |                   |                |
# |                               |                                                 |                   |                |
# | U₁ = X₁*Z₂Z₂                  |                                                 |                   |                |
# | U₂ = X₂*Z₁Z₁                  |                                                 |                   |                |
# | S₁ = Y₁*Z₂*Z₂Z₂               |                                                 |                   |                |
# | S₂ = Y₂*Z₁*Z₁Z₁               |                                                 |                   |                |
# | H  = U₂-U₁ # P=-Q, P=Inf, P=Q |                                                 |                   |                |
# | R  = S₂-S₁ # Q=Inf            |                                                 |                   |                |
# |                               |                                                 |                   |                |
# | HH  = H²                      | YY = Y₁²                                        |                   |                |
# | HHH = H*HH                    | M  = (3*X₁²+a*ZZ²)/2                            | 3(X₁-Z₁)(X₁+Z₁)/2 | 3X₁²/2         |
# | V   = U₁*HH                   | S  = X₁*YY                                      |                   |                |
# |                               |                                                 |                   |                |
# | X₃ = R²-HHH-2*V               | X₃ = M²-2*S                                     |                   |                |
# | Y₃ = R*(V-X₃)-S₁*HHH          | Y₃ = M*(S-X₃)-YY²                               |                   |                |
# | Z₃ = Z₁*Z₂*H                  | Z₃ = Y₁*Z₁                                      |                   |                |
# ```
#
# So we actually replaced 1 doubling, 1 quadrupling, 1 octupling by 1 halving, which has the same cost as doubling/addition.
# We could use that for elliptic curve over Fp and Fp2.
# For elliptic curve over Fp4 and Fp8 (BLS24 and BLS48) the gap between multiplication and square is large enough
# that replacing a multiplication by squaring + 2 substractions and extra bookkeeping is worth it,
# we could use this formula instead:
#
# ```
# | Addition (adapted Bernstein et al) |     Doubling any a (adapted Bernstein)   |  Doubling = -3  | Doubling a = 0 |
# |       11M + 5S + 9add + 4*2        | 2M + 7S + 1*a + 7add + 2*2+1*3+1*4+1*8   |                 |                |
# | ---------------------------------- | ---------------------------------------- | --------------- | -------------- |
# | Z₁Z₁ = Z₁²                         | Z₁Z₁ = Z₁²                               |                 |                |
# | Z₂Z₂ = Z₂²                         |                                          |                 |                |
# |                                    |                                          |                 |                |
# | U₁ = X₁*Z₂Z₂                       |                                          |                 |                |
# | U₂ = X₂*Z₁Z₁                       |                                          |                 |                |
# | S₁ = Y₁*Z₂*Z₂Z₂                    |                                          |                 |                |
# | S₂ = Y₂*Z₁*Z₁Z₁                    |                                          |                 |                |
# | H = U₂-U₁     # P=-Q, P=Inf, P=Q   |                                          |                 |                |
# | R = 2*(S₂-S₁) # Q=Inf              |                                          |                 |                |
# |                                    |                                          |                 |                |
# | I = (2*H)²                         | YY = Y₁²                                 |                 |                |
# | J = H*I                            | M  = 3*X₁²+a*ZZ²                         | 3(X₁-Z₁)(X₁+Z₁) | 3*X₁²          |
# | V = U₁*I                           | S  = 4*X₁*YY                             |                 |                |
# |                                    |                                          |                 |                |
# | X₃ = R²-J-2*V                      | X₃ = M²-2*S                              |                 |                |
# | Y₃ = R*(V-X₃)-2*S₁*J               | Y₃ = M*(S-X₃)-8*YY²                      |                 |                |
# | Z₃ = ((Z₁+Z₂)²-Z₁Z₁-Z₂Z₂)*H        | Z₃ = (Y₁+Z₁)² - YY - ZZ                  |                 |                |
# ```
#
# Can we do better? Actually yes, Lange introduced a doubling formula
# in 2009 that didn't use the `a` curve coefficient and only used 2M and 5S and no more additions!
# "dbl-2009-l" doubling formula - https://www.hyperelliptic.org/EFD/g1p/auto-shortw-jacobian-0.html#doubling-dbl-2009-l
#
#     Cost: 2M + 5S + 6add + 3*2 + 1*3 + 1*8.
#     Source: 2009.04.01 Lange.
#     Explicit formulas:
#
#           A = X₁²
#           B = Y₁²
#           C = B²
#           D = 2*((X₁+B)²-A-C)
#           E = 3*A
#           F = E²
#           X₃ = F-2*D
#           Y₃ = E*(D-X₃)-8*C
#           Z₃ = 2*Y₁*Z₁
#
# We can scale Z₃ by ½ and obtain our ultimate formula with no special case depending on "a"
#
# |    Addition, Cohen et al, 1998     | Doubling, modified from Lange, 2009 |
# |       12M + 4S + 6add + 1*2        |    3M + 4S + 4add + 1*2 + 1*half    |
# | ---------------------------------- | ----------------------------------- |
# | Z₁Z₁ = Z₁²                         |                                     |
# | Z₂Z₂ = Z₂²                         |                                     |
# |                                    |                                     |
# | U₁ = X₁*Z₂Z₂                       |                                     |
# | U₂ = X₂*Z₁Z₁                       |                                     |
# | S₁ = Y₁*Z₂*Z₂Z₂                    |                                     |
# | S₂ = Y₂*Z₁*Z₁Z₁                    |                                     |
# | H  = U₂-U₁      # P=-Q, P=Inf, P=Q |                                     |
# | R  = S₂-S₁      # Q=Inf            |                                     |
# |                                    |                                     |
# | Z₃ = Z₁*Z₂*H                       | Z₃ = Y₁*Z₁                          |
# |                                    |                                     |
# |                                    |                                     |
# | HH  = H²                           | B  = Y₁²                            |
# | HHH = H*HH                         | A  = X₁²                            |
# | S₁HHH = S₁*HHH                     | C  = B²                             |
# | V   = U₁*HH                        | D  = X₁*B                           |
# |                                    | E  = 3A/2                           |
# |                                    |                                     |
# | X₃ = R²-2*V-HHH                    | X₃ = E²-2*D                         |
# | Y₃ = R*(V-X₃)-S₁HHH                | Y₃ = E*(D-X₃)-C                     |
