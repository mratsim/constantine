# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  constantine/platforms/abstractions,
  constantine/named/algebras,
  constantine/math/arithmetic,
  constantine/math/extension_fields,
  ./ec_twistededwards_affine


# ############################################################
#
#             Elliptic Curve in Twisted Edwards form
#                 with Projective Coordinates
#
# ############################################################

type EC_TwEdw_Prj*[F] = object
  ## Elliptic curve point for a curve in Twisted Edwards form
  ##   ax²+y²=1+dx²y²
  ## with a, d ≠ 0 and a ≠ d
  ##
  ## over a field F
  ##
  ## in projective coordinate (X, Y, Z)
  ## with x = X/Z and y = Y/Z
  ## hence (aX² + Y²)Z² = Z⁴ + dX²Y²
  x*, y*, z*: F

template getName*(EC: type EC_TwEdw_Prj): untyped =
  EC.F.Name

template getScalarField*(EC: type EC_TwEdw_Prj): untyped =
  Fr[EC.F.Name]

func isNeutral*(P: EC_TwEdw_Prj): SecretBool {.inline.} =
  ## Returns true if P is the neutral element / identity element
  ## and false otherwise, i.e. ∀Q, P+Q == Q
  ## Contrary to Short Weierstrass curve, the neutral element is on the curve
  # Isogeny-based constructions to create
  # prime order curves overload this generic identity check.
  result = P.x.isZero() and (P.y == P.z)

func setNeutral*(P: var EC_TwEdw_Prj) {.inline.} =
  ## Set P to the neutral element / identity element
  ## i.e. ∀Q, P+Q == Q.
  ## Contrary to Short Weierstrass curve, the neutral element is on the curve
  P.x.setZero()
  P.y.setOne()
  P.z.setOne()

func `==`*(P, Q: EC_TwEdw_Prj): SecretBool =
  ## Constant-time equality check
  ## This is a costly operation
  # Reminder: the representation is not unique
  # Isogeny-based constructions to create
  # prime order curves overload this generic equality check.
  var a{.noInit.}, b{.noInit.}: EC_TwEdw_Prj.F

  a.prod(P.x, Q.z)
  b.prod(Q.x, P.z)
  result = a == b

  a.prod(P.y, Q.z)
  b.prod(Q.y, P.z)
  result = result and a == b

  # Ensure a zero-init point doesn't propagate 0s and match any
  result = result and not(P.isNeutral() xor Q.isNeutral())

func ccopy*(P: var EC_TwEdw_Prj, Q: EC_TwEdw_Prj, ctl: SecretBool) {.inline.} =
  ## Constant-time conditional copy
  ## If ctl is true: Q is copied into P
  ## if ctl is false: Q is not copied and P is unmodified
  ## Time and memory accesses are the same whether a copy occurs or not
  for fP, fQ in fields(P, Q):
    ccopy(fP, fQ, ctl)

func trySetFromCoordX*[F](
       P: var EC_TwEdw_Prj[F],
       x: F): SecretBool =
  ## Try to create a point on the elliptic curve from X co-ordinate
  ##   ax²+y²=1+dx²y²    (affine coordinate)
  ##
  ## The `Z` coordinates is set to 1
  ##
  ## return true and update `P` if `y` leads to a valid point
  ## return false otherwise, in that case `P` is undefined.

  var Q{.noInit.}: EC_TwEdw_Aff[F]
  result = Q.trySetFromCoordX(x)

  P.x = Q.x
  P.y = Q.y
  P.z.setOne()

func trySetFromCoordX_vartime*[F](
       P: var EC_TwEdw_Prj[F],
       x: F): SecretBool =
  ## this is not in constant time
  ## Try to create a point on the elliptic curve from X co-ordinate
  ##   ax²+y²=1+dx²y²    (affine coordinate)
  ##
  ## The `Z` coordinates is set to 1
  ##
  ## return true and update `P` if `y` leads to a valid point
  ## return false otherwise, in that case `P` is undefined.

  var Q{.noInit.}: EC_TwEdw_Aff[F]
  result = Q.trySetFromCoordX_vartime(x)

  P.x = Q.x
  P.y = Q.y
  P.z.setOne()


func trySetFromCoordY*[F](
       P: var EC_TwEdw_Prj[F],
       y: F): SecretBool =
  ## Try to create a point the elliptic curve
  ##   ax²+y²=1+dx²y²     (affine coordinate)
  ##
  ## The `Z` coordinates is set to 1
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

  var Q{.noInit.}: EC_TwEdw_Aff[F]
  result = Q.trySetFromCoordY(y)

  P.x = Q.x
  P.y = Q.y
  P.z.setOne()

func trySetFromCoordsYandZ*[F](
       P: var EC_TwEdw_Prj[F],
       y, z: F): SecretBool =
  ## Try to create a point the elliptic curve
  ##   ax²+y²=1+dx²y²     (affine coordinate)
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

  var Q{.noInit.}: EC_TwEdw_Aff[F]
  result = Q.trySetFromCoordY(y)

  P.x.prod(Q.x, z)
  P.y.prod(Q.y, z)
  P.z = z

func neg*(P: var EC_TwEdw_Prj, Q: EC_TwEdw_Prj) {.inline.} =
  ## Negate ``P``
  P.x.neg(Q.x)
  P.y = Q.y
  P.z = Q.z

func neg*(P: var EC_TwEdw_Prj) {.inline.} =
  ## Negate ``P``
  P.x.neg()

func cneg*(P: var EC_TwEdw_Prj, ctl: CTBool) {.inline.} =
  ## Conditional negation.
  ## Negate if ``ctl`` is true
  P.x.cneg(ctl)

func sum*[F](
       r: var EC_TwEdw_Prj[F],
       P, Q: EC_TwEdw_Prj[F]) =
  ## Elliptic curve point addition for Twisted Edwards curves in projective coordinates
  ##
  ##   R = P + Q
  ##
  ## Twisted Edwards curves have the following equation in projective coordinates
  ##   (aX² + Y²)Z² = Z⁴ + dX²Y²
  ## from the affine equation
  ##   ax²+y²=1+dx²y²
  ##
  ## ``r`` is initialized/overwritten with the sum
  ## ``r`` may alias P
  ##
  ## Implementation is constant-time, in particular it will not expose
  ## that P == Q or P == -Q or P or Q are the infinity points
  ## to simple side-channel attacks (SCA)
  ## This is done by using a "complete" or "exception-free" addition law.
  #
  # https://www.hyperelliptic.org/EFD/g1p/auto-twisted-projective.html#addition-add-2008-bbjlp
  # Cost: 10M + 1S + 1*a + 1*d + 7add.
  #   A = Z1*Z2
  #   B = A²
  #   C = X1*X2
  #   D = Y1*Y2
  #   E = d*C*D
  #   F = B-E
  #   G = B+E
  #   X3 = A*F*((X1+Y1)*(X2+Y2)-C-D)
  #   Y3 = A*G*(D-a*C)
  #   Z3 = F*G
  var
    A{.noInit.}, B{.noInit.}, C{.noInit.}: F
    D{.noInit.}, E{.noInit.}, F{.noInit.}: F
    G{.noInit.}: F

  A.prod(P.z, Q.z)
  B.square(A)
  C.prod(P.x, Q.x)
  D.prod(P.y, Q.y)
  E.prod(C, D)
  when F.Name.getCoefD() is int:
    # conversion at compile-time
    const coefD = block:
      var d: F
      d.fromInt F.Name.getCoefD()
      d
    E *= coefD
  else:
    E *= F.Name.getCoefD()
  F.diff(B, E)
  G.sum(B, E)

  # Aliasing: B and E are unused
  # We store (P.x+P.y)*(Q.x+Q.y)
  # so that using r.x or r.y is safe even in case of aliasing

  B.sum(P.x, P.y)
  E.sum(Q.x, Q.y)
  B *= E          # B = (X1+Y1)*(X2+Y2)
  E.sum(C, D)     # E = C+D

  # Y3 = A*G*(D-a*C)
  when F.Name.getCoefA() == -1:
    r.y = E       # (D-a*C) = D+C
  else:
    r.y.prod(C, F.Name.getCoefA())
    r.y.diff(D, r.y)
  r.y *= A
  r.y *= G

  # X3 = A*F*((X1+Y1)*(X2+Y2)-C-D)
  B -= E
  r.x.prod(A, F)
  r.x *= B

  # Z3 = F*G
  r.z.prod(F, G)

func mixedSum*[F](
       r: var EC_TwEdw_Prj[F],
       P: EC_TwEdw_Prj[F],
       Q: EC_TwEdw_Aff[F]) =
  ## Elliptic curve point mixed addition for Twisted Edwards curves in projective coordinates
  ##
  ##   R = P + Q
  ##
  ## Twisted Edwards curves have the following equation in projective coordinates
  ##   (aX² + Y²)Z² = Z⁴ + dX²Y²
  ## from the affine equation
  ##   ax²+y²=1+dx²y²
  ##
  ## ``r`` is initialized/overwritten with the sum
  ## ``r`` may alias P
  ##
  ## Implementation is constant-time, in particular it will not expose
  ## that P == Q or P == -Q or P or Q are the infinity points
  ## to simple side-channel attacks (SCA)
  ## This is done by using a "complete" or "exception-free" addition law.
  #
  # https://www.hyperelliptic.org/EFD/g1p/auto-twisted-projective.html#addition-mixedSum-2008-bbjlp
  # Cost: 9M + 1S + 1*a + 1*d + 7add.
  #   B = Z1²
  #   C = X1*X2
  #   D = Y1*Y2
  #   E = d*C*D
  #   F = B-E
  #   G = B+E
  #   X3 = Z1*F*((X1+Y1)*(X2+Y2)-C-D)
  #   Y3 = Z1*G*(D-a*C)
  #   Z3 = F*G
  var
    B{.noInit.}, C{.noInit.}: F
    D{.noInit.}, E{.noInit.}, F{.noInit.}: F
    G{.noInit.}: F

  B.square(P.z)
  C.prod(P.x, Q.x)
  D.prod(P.y, Q.y)
  E.prod(C, D)
  when F.Name.getCoefD() is int:
    # conversion at compile-time
    const coefD = block:
      var d: F
      d.fromInt F.Name.getCoefD()
      d
    E *= coefD
  else:
    E *= F.Name.getCoefD()
  F.diff(B, E)
  G.sum(B, E)

  # Aliasing: B and E are unused
  # We store (P.x+P.y)*(Q.x+Q.y)
  # so that using r.x or r.y is safe even in case of aliasing

  B.sum(P.x, P.y)
  E.sum(Q.x, Q.y)
  B *= E          # B = (X1+Y1)*(X2+Y2)
  E.sum(C, D)     # E = C+D

  # Y3 = A*G*(D-a*C)
  when F.Name.getCoefA() == -1:
    r.y = E       # (D-a*C) = D+C
  else:
    r.y.prod(C, F.Name.getCoefA())
    r.y.diff(D, r.y)
  r.y *= P.z
  r.y *= G

  # X3 = A*F*((X1+Y1)*(X2+Y2)-C-D)
  B -= E
  r.x.prod(P.z, F)
  r.x *= B

  # Z3 = F*G
  r.z.prod(F, G)

func double*[F](r: var EC_TwEdw_Prj[F], P: EC_TwEdw_Prj[F]) =
  ## Elliptic curve point doubling for Twisted Edwards curves in projective coordinates
  ##
  ##   R = [2] P
  ##
  ## Twisted Edwards curves have the following equation in projective coordinates
  ##   (aX² + Y²)Z² = Z⁴ + dX²Y²
  ## from the affine equation
  ##   ax²+y²=1+dx²y²
  ##
  ## ``r`` is initialized/overwritten with the sum
  ## ``r`` may alias P
  ##
  ## Implementation is constant-time, in particular it will not expose
  ## that P == Q or P == -Q or P or Q are the infinity points
  ## to simple side-channel attacks (SCA)
  ## This is done by using a "complete" or "exception-free" addition law.
  #
  # https://www.hyperelliptic.org/EFD/g1p/auto-twisted-projective.html#addition-add-2008-bbjlp
  # Cost: 3M + 4S + 1*a + 6add + 1*2.
  #  B = (X1+Y1)²
  #  C = X1²
  #  D = Y1²
  #  E = a*C
  #  F = E+D
  #  H = Z1²
  #  J = F-2*H
  #  X3 = (B-C-D)*J
  #  Y3 = F*(E-D)
  #  Z3 = F*J

  var
    D{.noInit.}, E{.noInit.}: F
    H{.noInit.}, J{.noInit.}: F

  # (B-C-D) => 2X1Y1, but With squaring and 2 substractions instead of mul + addition
  # In practice, squaring is not cheap enough to compasate the extra substraction cost.
  E.square(P.x)
  r.x.prod(P.x, P.y)
  r.x.double()

  D.square(P.y)
  E *= F.Name.getCoefA()

  r.y.sum(E, D)    # Ry stores F = E+D
  H.square(P.z)
  H.double()
  J.diff(r.y, H)   # J = F-2H

  r.x *= J         # X3 = (B-C-D)*J
  r.z.prod(r.y, J) # Z3 = F*J
  E -= D           # C stores E-D
  r.y *= E

func `+=`*(P: var EC_TwEdw_Prj, Q: EC_TwEdw_Prj) {.inline.} =
  ## In-place point addition
  P.sum(P, Q)

func `+=`*(P: var EC_TwEdw_Prj, Q: EC_TwEdw_Aff) {.inline.} =
  ## In-place point mixed addition
  P.mixedSum(P, Q)

func double*(P: var EC_TwEdw_Prj) {.inline.} =
  ## In-place EC doubling
  P.double(P)

func diff*(r: var EC_TwEdw_Prj, P, Q: EC_TwEdw_Prj) {.inline.} =
  ## r = P - Q
  ## Can handle r and Q aliasing
  var nQ {.noInit.}: typeof(Q)
  nQ.neg(Q)
  r.sum(P, nQ)

func mixedDiff*(r: var EC_TwEdw_Prj, P: EC_TwEdw_Prj, Q: EC_TwEdw_Aff) {.inline.} =
  ## r = P - Q
  ## Can handle r and Q aliasing
  var nQ {.noInit.}: typeof(Q)
  nQ.neg(Q)
  r.mixedSum(P, nQ)

func `-=`*(P: var EC_TwEdw_Prj, Q: EC_TwEdw_Prj) {.inline.} =
  ## In-place point substraction
  P.diff(P, Q)

func `-=`*(P: var EC_TwEdw_Prj, Q: EC_TwEdw_Aff) {.inline.} =
  ## In-place point substraction
  P.mixedDiff(P, Q)

template affine*[F](_: type EC_TwEdw_Prj[F]): untyped =
  ## Returns the affine type that corresponds to the Jacobian type input
  EC_TwEdw_Aff[F]

template projective*[F](_: type EC_TwEdw_Aff[F]): untyped =
  ## Returns the projective type that corresponds to the affine type input
  EC_TwEdw_Prj[F]

func affine*[F](
       aff: var EC_TwEdw_Aff[F],
       proj: EC_TwEdw_Prj[F]) =
  var invZ {.noInit.}: F
  invZ.inv(proj.z)

  aff.x.prod(proj.x, invZ)
  aff.y.prod(proj.y, invZ)

func fromAffine*[F](
       proj: var EC_TwEdw_Prj[F],
       aff: EC_TwEdw_Aff[F]) {.inline.} =
  proj.x = aff.x
  proj.y = aff.y
  proj.z.setOne()

  let inf = aff.isNeutral()
  proj.x.csetZero(inf)
  proj.y.csetOne(inf)
  proj.z.csetOne(inf)

# Vartime overloading
# ------------------------------------------------------------
# For generic vartime operations on both ShortWeierstrass curves and Twisted Edwards

func sum_vartime*[F](
       r: var EC_TwEdw_Prj[F],
       P, Q: EC_TwEdw_Prj[F]) {.inline.} =
  r.sum(P, Q)

func mixedSum_vartime*[F](
       r: var EC_TwEdw_Prj[F],
       P: EC_TwEdw_Prj[F],
       Q: EC_TwEdw_Aff[F]) {.inline.} =
  r.mixedSum(P, Q)

func diff_vartime*[F](
       r: var EC_TwEdw_Prj[F],
       P, Q: EC_TwEdw_Prj[F]) {.inline.} =
  r.diff(P, Q)

func mixedDiff_vartime*[F](
       r: var EC_TwEdw_Prj[F],
       P: EC_TwEdw_Prj[F],
       Q: EC_TwEdw_Aff[F]) {.inline.} =
  r.mixedDiff(P, Q)

template `~+=`*(P: var EC_TwEdw_Prj, Q: EC_TwEdw_Prj) =
  ## Variable-time in-place point addition
  P.sum_vartime(P, Q)

template `~+=`*(P: var EC_TwEdw_Prj, Q: EC_TwEdw_Aff) =
  ## Variable-time in-place point mixed addition
  P.mixedSum_vartime(P, Q)

template `~-=`*(P: var EC_TwEdw_Prj, Q: EC_TwEdw_Prj) =
  P.diff_vartime(P, Q)

template `~-=`*(P: var EC_TwEdw_Prj, Q: EC_TwEdw_Aff) =
  P.mixedDiff_vartime(P, Q)

# ############################################################
#
#              Banderwagon Specific Operations
#
# ############################################################

func `==`*(P, Q: EC_TwEdw_Prj[Fp[Banderwagon]]): SecretBool =
  ## Equality check for points in the Banderwagon Group
  ## The equality check is optimized for the quotient group
  ## This is a costly operation
  # see: https://hackmd.io/@6iQDuIePQjyYBqDChYw_jg/BJBNcv9fq#Equality-check
  var lhs{.noInit.}, rhs{.noInit.}: typeof(P).F

  # Check for the zero points
  result = not(P.x.is_zero() and P.y.is_zero())
  result = result or not(Q.x.is_zero() and Q.y.is_zero())

  ## Check for the equality of the points
  ## X1 * Y2 == X2 * Y1
  lhs.prod(P.x, Q.y)
  rhs.prod(Q.x, P.y)
  result = result and lhs == rhs

func isNeutral*(P: EC_TwEdw_Prj[Fp[Banderwagon]]): SecretBool {.inline.} =
  ## Returns true if P is the neutral/identity element
  ## in the Banderwagon group
  ## and false otherwise
  # Isogeny-based constructions to create
  # prime order curves overload this generic identity check.
  # see: https://hackmd.io/@6iQDuIePQjyYBqDChYw_jg/BJBNcv9fq#Equality-check

  # TODO: Rename the function
  result = P.x.isZero()

# ############################################################
#
#                 Out-of-Place functions
#
# ############################################################
#
# Out-of-place functions SHOULD NOT be used in performance-critical subroutines as compilers
# tend to generate useless memory moves or have difficulties to minimize stack allocation
# and our types might be large (Fp12 ...)
# See: https://github.com/mratsim/constantine/issues/145

func `+`*(a, b: EC_TwEdw_Prj): EC_TwEdw_Prj {.noInit, inline.} =
  ## Elliptic curve addition
  ##
  ## Out-of-place functions SHOULD NOT be used in performance-critical subroutines as compilers
  ## tend to generate useless memory moves or have difficulties to minimize stack allocation
  ## and our types might be large (Fp12 ...)
  ## See: https://github.com/mratsim/constantine/issues/145
  result.sum(a, b)

func `+`*(a: EC_TwEdw_Prj, b: EC_TwEdw_Aff): EC_TwEdw_Prj {.noInit, inline.} =
  ## Elliptic curve addition
  ##
  ## Out-of-place functions SHOULD NOT be used in performance-critical subroutines as compilers
  ## tend to generate useless memory moves or have difficulties to minimize stack allocation
  ## and our types might be large (Fp12 ...)
  ## See: https://github.com/mratsim/constantine/issues/145
  result.mixedSum(a, b)

func `~+`*(a, b: EC_TwEdw_Prj): EC_TwEdw_Prj {.noInit, inline.} =
  ## Elliptic curve variable-time addition
  ##
  ## This MUST NOT be used with secret data.
  ##
  ## This is highly VULNERABLE to timing attacks and power analysis attacks.
  ##
  ## Out-of-place functions SHOULD NOT be used in performance-critical subroutines as compilers
  ## tend to generate useless memory moves or have difficulties to minimize stack allocation
  ## and our types might be large (Fp12 ...)
  ## See: https://github.com/mratsim/constantine/issues/145
  result.sum_vartime(a, b)

func `~+`*(a: EC_TwEdw_Prj, b: EC_TwEdw_Aff): EC_TwEdw_Prj {.noInit, inline.} =
  ## Elliptic curve variable-time addition
  ##
  ## This MUST NOT be used with secret data.
  ##
  ## This is highly VULNERABLE to timing attacks and power analysis attacks.
  ##
  ## Out-of-place functions SHOULD NOT be used in performance-critical subroutines as compilers
  ## tend to generate useless memory moves or have difficulties to minimize stack allocation
  ## and our types might be large (Fp12 ...)
  ## See: https://github.com/mratsim/constantine/issues/145
  result.mixedSum_vartime(a, b)

func `-`*(a, b: EC_TwEdw_Prj): EC_TwEdw_Prj {.noInit, inline.} =
  ## Elliptic curve substraction
  ##
  ## Out-of-place functions SHOULD NOT be used in performance-critical subroutines as compilers
  ## tend to generate useless memory moves or have difficulties to minimize stack allocation
  ## and our types might be large (Fp12 ...)
  ## See: https://github.com/mratsim/constantine/issues/145
  result.diff(a, b)

func `-`*(a: EC_TwEdw_Prj, b: EC_TwEdw_Aff): EC_TwEdw_Prj {.noInit, inline.} =
  ## Elliptic curve substraction
  ##
  ## Out-of-place functions SHOULD NOT be used in performance-critical subroutines as compilers
  ## tend to generate useless memory moves or have difficulties to minimize stack allocation
  ## and our types might be large (Fp12 ...)
  ## See: https://github.com/mratsim/constantine/issues/145
  result.mixedDiff(a, b)

func `~-`*(a, b: EC_TwEdw_Prj): EC_TwEdw_Prj {.noInit, inline.} =
  ## Elliptic curve variable-time substraction
  ##
  ## This MUST NOT be used with secret data.
  ##
  ## This is highly VULNERABLE to timing attacks and power analysis attacks.
  ##
  ## Out-of-place functions SHOULD NOT be used in performance-critical subroutines as compilers
  ## tend to generate useless memory moves or have difficulties to minimize stack allocation
  ## and our types might be large (Fp12 ...)
  ## See: https://github.com/mratsim/constantine/issues/145
  result.diff_vartime(a, b)

func `~-`*(a: EC_TwEdw_Prj, b: EC_TwEdw_Aff): EC_TwEdw_Prj {.noInit, inline.} =
  ## Elliptic curve variable-time substraction
  ##
  ## This MUST NOT be used with secret data.
  ##
  ## This is highly VULNERABLE to timing attacks and power analysis attacks.
  ##
  ## Out-of-place functions SHOULD NOT be used in performance-critical subroutines as compilers
  ## tend to generate useless memory moves or have difficulties to minimize stack allocation
  ## and our types might be large (Fp12 ...)
  ## See: https://github.com/mratsim/constantine/issues/145
  result.mixedDiff_vartime(a, b)

func getAffine*[F](prj: EC_TwEdw_Prj[F]): EC_TwEdw_Aff[F] {.noInit, inline.} =
  ## Projective to Affine conversion
  ##
  ## Out-of-place functions SHOULD NOT be used in performance-critical subroutines as compilers
  ## tend to generate useless memory moves or have difficulties to minimize stack allocation
  ## and our types might be large (Fp12 ...)
  ## See: https://github.com/mratsim/constantine/issues/145
  result.affine(prj)

func getProjective*[F](aff: EC_TwEdw_Aff[F]): EC_TwEdw_Prj[F] {.noInit, inline.} =
  ## Affine to Projective conversion
  ##
  ## Out-of-place functions SHOULD NOT be used in performance-critical subroutines as compilers
  ## tend to generate useless memory moves or have difficulties to minimize stack allocation
  ## and our types might be large (Fp12 ...)
  ## See: https://github.com/mratsim/constantine/issues/145
  result.fromAffine(aff)
