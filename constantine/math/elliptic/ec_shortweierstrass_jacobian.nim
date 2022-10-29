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
#                 with Jacobian Coordinates
#
# ############################################################

type ECP_ShortW_Jac*[F; G: static Subgroup] = object
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

template affine*[F, G](_: type ECP_ShortW_Jac[F, G]): typedesc =
  ## Returns the affine type that corresponds to the Jacobian type input
  ECP_ShortW_Aff[F, G]

func `==`*(P, Q: ECP_ShortW_Jac): SecretBool =
  ## Constant-time equality check
  ## This is a costly operation
  # Reminder: the representation is not unique
  type F = ECP_ShortW_Jac.F

  var z1z1 {.noInit.}, z2z2 {.noInit.}: F
  var a{.noInit.}, b{.noInit.}: F

  z1z1.square(P.z, skipFinalSub = true)
  z2z2.square(Q.z, skipFinalSub = true)

  a.prod(P.x, z2z2)
  b.prod(Q.x, z1z1)
  result = a == b

  a.prod(P.y, Q.z, skipFinalSub = true)
  b.prod(Q.y, P.z, skipFinalSub = true)
  a *= z2z2
  b *= z1z1
  result = result and a == b

func isInf*(P: ECP_ShortW_Jac): SecretBool {.inline.} =
  ## Returns true if P is an infinity point
  ## and false otherwise
  ##
  ## Note: the jacobian coordinates equation is
  ##       Y² = X³ + aXZ⁴ + bZ⁶
  ## A "zero" point is any point with coordinates X and Z = 0
  ## Y can be anything
  result = P.z.isZero()

func setInf*(P: var ECP_ShortW_Jac) {.inline.} =
  ## Set ``P`` to infinity
  P.x.setOne()
  P.y.setOne()
  P.z.setZero()

func ccopy*(P: var ECP_ShortW_Jac, Q: ECP_ShortW_Jac, ctl: SecretBool) {.inline.} =
  ## Constant-time conditional copy
  ## If ctl is true: Q is copied into P
  ## if ctl is false: Q is not copied and P is unmodified
  ## Time and memory accesses are the same whether a copy occurs or not
  for fP, fQ in fields(P, Q):
    ccopy(fP, fQ, ctl)

func trySetFromCoordsXandZ*[F; G](
       P: var ECP_ShortW_Jac[F, G],
       x, z: F): SecretBool =
  ## Try to create a point the elliptic curve
  ## Y² = X³ + aXZ⁴ + bZ⁶  (Jacobian coordinates)
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

  var z2 {.noInit.}: F
  z2.square(z, skipFinalSub = true)
  P.x.prod(x, z2)
  P.y.prod(P.y, z2, skipFinalSub = true)
  P.y *= z
  P.z = z

func trySetFromCoordX*[F; G](
       P: var ECP_ShortW_Jac[F, G],
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

func neg*(P: var ECP_ShortW_Jac, Q: ECP_ShortW_Jac) {.inline.} =
  ## Negate ``P``
  P.x = Q.x
  P.y.neg(Q.y)
  P.z = Q.z

func neg*(P: var ECP_ShortW_Jac) {.inline.} =
  ## Negate ``P``
  P.y.neg()

func cneg*(P: var ECP_ShortW_Jac, ctl: CTBool)  {.inline.} =
  ## Conditional negation.
  ## Negate if ``ctl`` is true
  P.y.cneg(ctl)

template sumImpl[F; G: static Subgroup](
       r: var ECP_ShortW_Jac[F, G],
       P, Q: ECP_ShortW_Jac[F, G],
       CoefA: typed
     ) {.dirty.} =
  ## Elliptic curve point addition for Short Weierstrass curves in Jacobian coordinates
  ## with the curve ``a`` being a parameter for summing on isogenous curves.
  ##
  ##   R = P + Q
  ##
  ## Short Weierstrass curves have the following equation in Jacobian coordinates
  ##   Y² = X³ + aXZ⁴ + bZ⁶
  ## from the affine equation
  ##   y² = x³ + a x + b
  ##
  ## ``r`` is initialized/overwritten with the sum
  ## ``CoefA`` allows fast path for curve with a == 0 or a == -3
  ##            and also allows summing on curve isogenies.
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
  # |  Addition, Cohen et al, 1998  |      Doubling, Cohen et al, 1998         |   Doubling = -3   | Doubling a = 0 |
  # |  12M + 4S + 6add + 1*2        | 3M + 6S + 1*a + 4add + 1*2 + 1*3 + 1half |                   |                |
  # | ----------------------------- | -----------------------------------------| ----------------- | -------------- |
  # | Z₁Z₁ = Z₁²                    | Z₁Z₁ = Z₁²                               |                   |                |
  # | Z₂Z₂ = Z₂²                    |                                          |                   |                |
  # |                               |                                          |                   |                |
  # | U₁ = X₁*Z₂Z₂                  |                                          |                   |                |
  # | U₂ = X₂*Z₁Z₁                  |                                          |                   |                |
  # | S₁ = Y₁*Z₂*Z₂Z₂               |                                          |                   |                |
  # | S₂ = Y₂*Z₁*Z₁Z₁               |                                          |                   |                |
  # | H  = U₂-U₁ # P=-Q, P=Inf, P=Q |                                          |                   |                |
  # | R  = S₂-S₁ # Q=Inf            |                                          |                   |                |
  # |                               |                                          |                   |                |
  # | HH  = H²                      | YY = Y₁²                                 |                   |                |
  # | V   = U₁*HH                   | S  = X₁*YY                               |                   |                |
  # | HHH = H*HH                    | M  = (3*X₁²+a*ZZ²)/2                     | 3(X₁-ZZ)(X₁+ZZ)/2 | 3X₁²/2         |
  # |                               |                                          |                   |                |
  # | X₃ = R²-HHH-2*V               | X₃ = M²-2*S                              |                   |                |
  # | Y₃ = R*(V-X₃)-S₁*HHH          | Y₃ = M*(S-X₃)-YY*YY                      |                   |                |
  # | Z₃ = Z₁*Z₂*H                  | Z₃ = Y₁*Z₁                               |                   |                |

  var Z1Z1 {.noInit.}, U1 {.noInit.}, S1 {.noInit.}, H {.noInit.}, R {.noinit.}: F

  block: # Addition-only, check for exceptional cases
    var Z2Z2 {.noInit.}, U2 {.noInit.}, S2 {.noInit.}: F
    Z2Z2.square(Q.z, skipFinalSub = true)
    S1.prod(Q.z, Z2Z2, skipFinalSub = true)
    S1 *= P.y           # S₁ = Y₁*Z₂³
    U1.prod(P.x, Z2Z2)  # U₁ = X₁*Z₂²

    Z1Z1.square(P.z, skipFinalSub = true)
    S2.prod(P.z, Z1Z1, skipFinalSub = true)
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
  template R_or_M: untyped = R
  template H_or_Y: untyped = H
  template V_or_S: untyped = U1
  var HH_or_YY {.noInit.}: F
  var HHH_or_Mpre {.noInit.}: F

  H_or_Y.ccopy(P.y, isDbl) # H         (add) or Y₁        (dbl)
  HH_or_YY.square(H_or_Y)  # H²        (add) or Y₁²       (dbl)

  V_or_S.ccopy(P.x, isDbl) # U₁        (add) or X₁        (dbl)
  V_or_S *= HH_or_YY       # V = U₁*HH (add) or S = X₁*YY (dbl)

  block: # Compute M for doubling
    # "when" static evaluation doesn't shortcut booleans :/
    # which causes issues when CoefA isn't an int but Fp or Fp2
    when CoefA is int:
      const CoefA_eq_zero = CoefA == 0
      const CoefA_eq_minus3 {.used.} = CoefA == -3
    else:
      const CoefA_eq_zero = false
      const CoefA_eq_minus3 = false

    when CoefA_eq_zero:
      var a {.noInit.} = H
      var b {.noInit.} = HH_or_YY
      a.ccopy(P.x, isDbl)           # H or X₁
      b.ccopy(P.x, isDbl)           # HH or X₁
      HHH_or_Mpre.prod(a, b)        # HHH or X₁²

      var M{.noInit.} = HHH_or_Mpre # Assuming on doubling path
      M.div2()                      #  X₁²/2
      M += HHH_or_Mpre              # 3X₁²/2
      R_or_M.ccopy(M, isDbl)

    elif CoefA_eq_minus3:
      var a{.noInit.}, b{.noInit.}: F
      a.sum(P.x, Z1Z1)
      b.diff(P.z, Z1Z1)
      a.ccopy(H_or_Y, not isDbl)    # H   or X₁+ZZ
      b.ccopy(HH_or_YY, not isDbl)  # HH  or X₁-ZZ
      HHH_or_Mpre.prod(a, b)        # HHH or X₁²-ZZ²

      var M{.noInit.} = HHH_or_Mpre # Assuming on doubling path
      M.div2()                      # (X₁²-ZZ²)/2
      M += HHH_or_Mpre              # 3(X₁²-ZZ²)/2
      R_or_M.ccopy(M, isDbl)

    else:
      # TODO: Costly `a` coefficients can be computed
      # by merging their computation with Z₃ = Z₁*Z₂*H (add) or Z₃ = Y₁*Z₁ (dbl)
      var a{.noInit.} = H
      var b{.noInit.} = HH_or_YY
      a.ccopy(P.x, isDbl)
      b.ccopy(P.x, isDbl)
      HHH_or_Mpre.prod(a, b, true)  # HHH or X₁²

      # Assuming doubling path
      a.square(HHH_or_Mpre, skipFinalSub = true)
      a *= HHH_or_Mpre              # a = 3X₁²
      b.square(Z1Z1)
      # b.mulCheckSparse(CoefA)     # TODO: broken static compile-time type inference
      b *= CoefA                    # b = αZZ, with α the "a" coefficient of the curve

      a += b
      a.div2()
      R_or_M.ccopy(a, isDbl)        # (3X₁² - αZZ)/2

  # Let's count our horses, at this point:
  # - R_or_M is set with R (add) or M (dbl)
  # - HHH_or_Mpre contains HHH (add) or garbage precomputation (dbl)
  # - V_or_S is set with V = U₁*HH (add) or S = X₁*YY (dbl)
  block: # Finishing line
    # we can start using r, while carefully handling r and P or Q aliasing
    var t {.noInit.}: F
    t.double(V_or_S)
    r.x.square(R_or_M)
    r.x -= t                           # X₃ = R²-2*V (add) or M²-2*S (dbl)
    r.x.csub(HHH_or_Mpre, not isDbl)   # X₃ = R²-HHH-2*V (add) or M²-2*S (dbl)

    V_or_S -= r.x                      # V-X₃ (add) or S-X₃ (dbl)
    r.y.prod(R_or_M, V_or_S)           # Y₃ = R(V-X₃) (add) or M(S-X₃) (dbl)
    HHH_or_Mpre.ccopy(HH_or_YY, isDbl) # HHH (add) or YY (dbl)
    S1.ccopy(HH_or_YY, isDbl)          # S1 (add) or YY (dbl)
    HHH_or_Mpre *= S1                  # HHH*S1 (add) or YY² (dbl)
    r.y -= HHH_or_Mpre                 # Y₃ = R(V-X₃)-S₁*HHH (add) or M(S-X₃)-YY² (dbl)

    t = Q.z
    t.ccopy(H_or_Y, isDbl)             # Z₂ (add) or Y₁ (dbl)
    t.prod(t, P.z, true)               # Z₁Z₂ (add) or Y₁Z₁ (dbl)
    r.z.prod(t, H_or_Y)                # Z₁Z₂H (add) or garbage (dbl)
    r.z.ccopy(t, isDbl)                # Z₁Z₂H (add) or Y₁Z₁ (dbl)

  # if P or R were infinity points they would have spread 0 with Z₁Z₂
  block: # Infinity points
    r.ccopy(Q, P.isInf())
    r.ccopy(P, Q.isInf())

func sum*[F; G: static Subgroup](
       r: var ECP_ShortW_Jac[F, G],
       P, Q: ECP_ShortW_Jac[F, G],
       CoefA: static F
     ) =
  ## Elliptic curve point addition for Short Weierstrass curves in Jacobian coordinates
  ## with the curve ``a`` being a parameter for summing on isogenous curves.
  ##
  ##   R = P + Q
  ##
  ## Short Weierstrass curves have the following equation in Jacobian coordinates
  ##   Y² = X³ + aXZ⁴ + bZ⁶
  ## from the affine equation
  ##   y² = x³ + a x + b
  ##
  ## ``r`` is initialized/overwritten with the sum
  ## ``CoefA`` allows fast path for curve with a == 0 or a == -3
  ##            and also allows summing on curve isogenies.
  ##
  ## Implementation is constant-time, in particular it will not expose
  ## that P == Q or P == -Q or P or Q are the infinity points
  ## to simple side-channel attacks (SCA)
  ## This is done by using a "complete" or "exception-free" addition law.
  r.sumImpl(P, Q, CoefA)

func sum*[F; G: static Subgroup](
       r: var ECP_ShortW_Jac[F, G],
       P, Q: ECP_ShortW_Jac[F, G]
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
  r.sumImpl(P, Q, F.C.getCoefA())

func madd*[F; G: static Subgroup](
       r: var ECP_ShortW_Jac[F, G],
       P: ECP_ShortW_Jac[F, G],
       Q: ECP_ShortW_Aff[F, G]
     ) =
  ## Elliptic curve mixed addition for Short Weierstrass curves
  ## with p in Jacobian coordinates and Q in affine coordinates
  ##
  ##   R = P + Q
  ## 
  ## TODO: ⚠️ cannot handle P == Q
  # "madd-2007-bl" mixed addition formula - https://hyperelliptic.org/EFD/g1p/auto-shortw-jacobian-0.html#addition-madd-2007-bl
  # with conditional copies to handle infinity points
  #  Assumptions: Z2=1.
  #  Cost: 7M + 4S + 9add + 3*2 + 1*4.
  #  Source: 2007 Bernstein–Lange.
  #  Explicit formulas:
  #
  #        Z1Z1 = Z1²
  #        U2 = X2*Z1Z1
  #        S2 = Y2*Z1*Z1Z1
  #        H = U2-X1
  #        HH = H2
  #        I = 4*HH
  #        J = H*I
  #        r = 2*(S2-Y1)
  #        V = X1*I
  #        X3 = r²-J-2*V
  #        Y3 = r*(V-X3)-2*Y1*J
  #        Z3 = (Z1+H)²-Z1Z1-HH
  var Z1Z1 {.noInit.}, H {.noInit.}, HH {.noInit.}, I{.noInit.}, J {.noInit.}: F

  # Preload P and Q in cache
  let pIsInf = P.isInf()
  let qIsInf = Q.isInf()

  Z1Z1.square(P.z)          # Z₁Z₁ = Z₁²
  r.z.prod(P.z, Z1Z1, true) #               P.Z is hot in cache, keep it in same register.
  r.z *= Q.y                # S₂ = Y₂Z₁Z₁Z₁         -- r.z used as S₂

  H.prod(Q.x, Z1Z1)         # U₂ = X₂Z₁Z₁
  H -= P.x                  # H = U₂ - X₁

  HH.square(H)              # HH = H²

  I.double(HH)
  I.double()                # I = 4HH

  J.prod(H, I)              # J = H*I
  r.y.prod(P.x, I)          # V = X₁*I              -- r.y used as V

  r.z -= P.y                #
  r.z.double()              # r = 2*(S₂-Y₁)         -- r.z used as r

  r.x.square(r.z)           # r²
  r.x -= J
  r.x -= r.y
  r.x -= r.y                # X₃ = r²-J-2*V         -- r.x computed

  r.y -= r.x                # V-X₃
  r.y *= r.z                # r*(V-X₃)

  J *= P.y                  # Y₁J                   -- J reused as Y₁J
  r.y -= J
  r.y -= J                  # Y₃ = r*(V-X₃) - 2*Y₁J -- r.y computed

  r.z.sum(P.z, H)           # Z₁ + H
  r.z.square()
  r.z -= Z1Z1
  r.z -= HH                 # Z₃ = (Z1+H)²-Z1Z1-HH

  # Now handle points at infinity
  proc one(): F =
    result.setOne()

  r.x.ccopy(Q.x, pIsInf)
  r.y.ccopy(Q.y, pIsInf)
  r.z.ccopy(static(one()), pIsInf)

  r.ccopy(P, qIsInf)

func double*[F; G: static Subgroup](
       r: var ECP_ShortW_Jac[F, G],
       P: ECP_ShortW_Jac[F, G]
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
  when F.C.getCoefA() == 0:
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
    var A {.noInit.}, B{.noInit.}, C {.noInit.}: F
    A.square(P.x)
    B.square(P.y)
    C.square(B)
    B += P.x
    # aliasing: we don't use P.x anymore

    B.square()
    B -= A
    B -= C
    B.double()         # D = 2*((X₁+B)²-A-C)
    A *= 3             # E = 3*A
    r.x.square(A)      # F = E²

    r.x -= B
    r.x -= B           # X₃ = F-2*D

    B -= r.x           # (D-X₃)
    A *= B             # E*(D-X₃)
    C *= 8

    r.z.prod(P.z, P.y)
    r.z.double()       # Z₃ = 2*Y₁*Z₁
    # aliasing: we don't use P.y, P.z anymore

    r.y.diff(A, C)     # Y₃ = E*(D-X₃)-8*C

  else:
    {.error: "Not implemented.".}

func `+=`*(P: var ECP_ShortW_Jac, Q: ECP_ShortW_Jac) {.inline.} =
  ## In-place point addition
  P.sum(P, Q)

func `+=`*(P: var ECP_ShortW_Jac, Q: ECP_ShortW_Aff) {.inline.} =
  ## In-place mixed point addition
  ## 
  ## TODO: ⚠️ cannot handle P == Q
  var t{.noInit.}: typeof(P)
  t.madd(P, Q)
  P = t

func double*(P: var ECP_ShortW_Jac) {.inline.} =
  ## In-place point doubling
  P.double(P)

func diff*(r: var ECP_ShortW_Jac,
           P, Q: ECP_ShortW_Jac
     ) {.inline.} =
  ## r = P - Q
  var nQ {.noInit.}: typeof(Q)
  nQ.neg(Q)
  r.sum(P, nQ)

func affine*[F; G](
       aff: var ECP_ShortW_Aff[F, G],
       jac: ECP_ShortW_Jac[F, G]) =
  var invZ {.noInit.}, invZ2{.noInit.}: F
  invZ.inv(jac.z)
  invZ2.square(invZ, skipFinalSub = true)

  aff.x.prod(jac.x, invZ2)
  invZ.prod(invZ, invZ2, skipFinalSub = true)
  aff.y.prod(jac.y, invZ)

func fromAffine*[F; G](
       jac: var ECP_ShortW_Jac[F, G],
       aff: ECP_ShortW_Aff[F, G]) {.inline.} =
  jac.x = aff.x
  jac.y = aff.y
  jac.z.setOne()

func batchAffine*[N: static int, F, G](
       affs: var array[N, ECP_ShortW_Aff[F, G]],
       jacs: array[N, ECP_ShortW_Jac[F, G]]) =
  # Algorithm: Montgomery's batch inversion
  # - Speeding the Pollard and Elliptic Curve Methods of Factorization
  #   Section 10.3.1
  #   Peter L. Montgomery
  #   https://www.ams.org/journals/mcom/1987-48-177/S0025-5718-1987-0866113-7/S0025-5718-1987-0866113-7.pdf
  # - Modern Computer Arithmetic
  #   Section 2.5.1 Several inversions at once
  #   Richard P. Brent and Paul Zimmermann
  #   https://members.loria.fr/PZimmermann/mca/mca-cup-0.5.9.pdf

  # To avoid temporaries, we store partial accumulations
  # in affs[i].x and whether z == 0 in affs[i].y
  var zeroes: array[N, SecretBool]
  affs[0].x  = jacs[0].z
  zeroes[0] = affs[0].x.isZero()
  affs[0].x.csetOne(zeroes[0])

  for i in 1 ..< N:
    # Skip zero z-coordinates (infinity points)
    var z = jacs[i].z
    zeroes[i] = z.isZero()
    z.csetOne(zeroes[i])

    if i != N-1:
      affs[i].x.prod(affs[i-1].x, z, skipFinalSub = true)
    else:
      affs[i].x.prod(affs[i-1].x, z, skipFinalSub = false)
  
  var accInv {.noInit.}: F
  accInv.inv(affs[N-1].x)

  for i in countdown(N-1, 1):
    # Skip zero z-coordinates (infinity points)
    var z = affs[i].x

    # Extract 1/Pᵢ
    var invi {.noInit.}: F
    invi.prod(accInv, affs[i-1].x, skipFinalSub = true)
    invi.csetZero(zeroes[i])

    # Now convert Pᵢ to affine
    var invi2 {.noinit.}: F
    invi2.square(invi, skipFinalSub = true)
    affs[i].x.prod(jacs[i].x, invi2)
    invi.prod(invi, invi2, skipFinalSub = true)
    affs[i].y.prod(jacs[i].y, invi)

    # next iteration
    invi = jacs[i].z
    invi.csetOne(zeroes[i])
    accInv.prod(accInv, invi, skipFinalSub = true)

  block: # tail
    var invi2 {.noinit.}: F
    accInv.csetZero(zeroes[0])
    invi2.square(accInv, skipFinalSub = true)
    affs[0].x.prod(jacs[0].x, invi2)
    accInv.prod(accInv, invi2, skipFinalSub = true)
    affs[0].y.prod(jacs[0].y, accInv)

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
