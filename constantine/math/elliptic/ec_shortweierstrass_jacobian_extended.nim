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
  ./ec_shortweierstrass_affine,
  ./ec_shortweierstrass_projective,
  ./ec_shortweierstrass_jacobian

export Subgroup

# No exceptions allowed
{.push raises: [].}

# ############################################################
#
#             Elliptic Curve in Short Weierstrass form
#                with Extended Jacobian Coordinates
#
# ############################################################

type ECP_ShortW_JacExt*[F; G: static Subgroup] = object
  ## Elliptic curve point for a curve in Short Weierstrass form
  ##   y² = x³ + a x + b
  ##
  ## over a field F
  ##
  ## in Extended Jacobian coordinates (X, Y, ZZ, ZZZ)
  ## corresponding to (x, y) with X = xZ² and Y = yZ³
  ##
  ## Note that extended jacobian coordinates are not unique
  x*, y*, zz*, zzz*: F

func fromAffine*[F; G](jacext: var ECP_ShortW_JacExt[F, G], aff: ECP_ShortW_Aff[F, G]) {.inline.}

func isInf*(P: ECP_ShortW_JacExt): SecretBool {.inline, meter.} =
  ## Returns true if P is an infinity point
  ## and false otherwise
  result = P.zz.isZero()

func setInf*(P: var ECP_ShortW_JacExt) {.inline.} =
  ## Set ``P`` to infinity
  P.x.setOne()
  P.y.setOne()
  P.zz.setZero()
  P.zzz.setZero()

func `==`*(P, Q: ECP_ShortW_JacExt): SecretBool {.meter.} =
  ## Constant-time equality check
  ## This is a costly operation
  # Reminder: the representation is not unique
  type F = ECP_ShortW_JacExt.F

  var a{.noInit.}, b{.noInit.}: F

  a.prod(P.x, Q.zz)
  b.prod(Q.x, P.zz)
  result = a == b

  a.prod(P.y, Q.zzz)
  b.prod(Q.y, P.zzz)
  result = result and a == b

  # Ensure a zero-init point doesn't propagate 0s and match any
  result = result and not(P.isInf() xor Q.isInf())

func trySetFromCoordsXandZ*[F; G](
       P: var ECP_ShortW_JacExt[F, G],
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

  P.zz.square(z)
  P.x.prod(x, P.zz)

  P.zzz.prod(P.zz, z)
  P.y.prod(P.y, P.zzz)

func trySetFromCoordX*[F; G](
       P: var ECP_ShortW_JacExt[F, G],
       x: F): SecretBool =
  ## Try to create a point the elliptic curve
  ## y² = x³ + a x + b     (affine coordinate)
  ##
  ## The `ZZ` and `ZZZ` coordinates are set to 1
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
  P.zz.setOne()
  P.zzz.setOne()

func neg*(P: var ECP_ShortW_JacExt, Q: ECP_ShortW_JacExt) {.inline.} =
  ## Negate ``P``
  P.x = Q.x
  P.y.neg(Q.y)
  P.zz = Q.zz
  P.zzz = Q.zzz

func neg*(P: var ECP_ShortW_JacExt) {.inline.} =
  ## Negate ``P``
  P.y.neg()

func double*[F; G: static Subgroup](r: var ECP_ShortW_JacExt[F, G], P: ECP_ShortW_JacExt[F, G]) {.meter.} =
  # http://www.hyperelliptic.org/EFD/g1p/auto-shortw-xyzz.html#doubling-dbl-2008-s-1
  var U{.noInit.}, V{.noInit.}, W{.noinit.}, S{.noInit.}, M{.noInit.}: F

  U.double(P.y)
  V.square(U)
  W.prod(U, V)
  S.prod(P.x, V)
  M.square(P.x)
  M *= 3
  when F.C.getCoefA() != 0:
    {.error: "Not implemented.".}

  # aliasing, we don't use P.x and U anymore
  r.x.square(M)
  U.double(S)
  r.x -= U
  S -= r.x
  r.y.prod(W, P.y)
  M *= S
  r.y.diff(M, r.y)
  r.zz.prod(P.zz, V)
  r.zzz.prod(P.zzz, W)

func sum_vartime*[F; G: static Subgroup](
       r: var ECP_ShortW_JacExt[F, G],
       p, q: ECP_ShortW_JacExt[F, G])
       {.tags:[VarTime], meter.} =
  ## **Variable-time** Extended Jacobian addition
  ##
  ## This MUST NOT be used with secret data.
  ##
  ## This is highly VULNERABLE to timing attacks and power analysis attacks.
  # https://www.hyperelliptic.org/EFD/g1p/auto-shortw-xyzz.html#addition-add-2008-s

  if p.isInf().bool:
    r = q
    return
  if q.isInf().bool:
    r = p
    return

  var U{.noInit.}, S{.noInit.}, P{.noInit.}, R{.noInit.}: F

  U.prod(p.x, q.zz)
  P.prod(q.x, p.zz)
  S.prod(p.y, q.zzz)
  R.prod(q.y, p.zzz)

  P -= U
  R -= S

  if P.isZero().bool:   # Same x coordinate
    if R.isZero().bool: # case P == Q
      r.double(q)
      return
    else:               # case P = -Q
      r.setInf()
      return

  var PPP{.noInit.}, Q{.noInit.}: F

  PPP.square(P)

  Q.prod(U, PPP)
  r.zz.prod(p.zz, q.zz)
  r.zz *= PPP

  PPP *= P

  r.x.square(R)
  P.double(Q)
  r.x -= PPP
  r.x -= P

  Q -= r.x
  r.y.prod(S, PPP)
  R *= Q
  r.y.diff(R, r.y)

  r.zzz.prod(p.zzz, q.zzz)
  r.zzz *= PPP

func mdouble*[F; G: static Subgroup](r: var ECP_ShortW_JacExt[F, G], P: ECP_ShortW_Aff[F, G]) {.meter.} =
  ## Mixed EC point double
  # http://www.hyperelliptic.org/EFD/g1p/auto-shortw-xyzz.html#doubling-mdbl-2008-s-1

  var U{.noInit.}, V{.noInit.}, W{.noinit.}, S{.noInit.}, M{.noInit.}: F

  U.double(P.y)
  V.square(U)
  W.prod(U, V)
  S.prod(P.x, V)
  M.square(P.x)
  M *= 3
  when F.C.getCoefA() != 0:
    {.error: "Not implemented.".}

  # aliasing, we don't use P.x and U anymore
  r.x.square(M)
  U.double(S)
  r.x -= U
  S -= r.x
  r.y.prod(W, P.y)
  M *= S
  r.y.diff(M, r.y)
  r.zz = V
  r.zzz = W

func madd_vartime*[F; G: static Subgroup](
       r: var ECP_ShortW_JacExt[F, G],
       p: ECP_ShortW_JacExt[F, G],
       q: ECP_ShortW_Aff[F, G])
       {.tags:[VarTime], meter.} =
  ## **Variable-time** Extended Jacobian mixed addition
  ##
  ## This MUST NOT be used with secret data.
  ##
  ## This is highly VULNERABLE to timing attacks and power analysis attacks.
  # https://www.hyperelliptic.org/EFD/g1p/auto-shortw-xyzz.html#addition-add-2008-s

  if p.isInf().bool:
    r.fromAffine(q)
    return
  if q.isInf().bool:
    r = p
    return

  var P{.noInit.}, R{.noInit.}: F

  P.prod(q.x, p.zz)
  R.prod(q.y, p.zzz)

  P -= p.x
  R -= p.y

  if P.isZero().bool:   # Same x coordinate
    if R.isZero().bool: # case P == Q
      r.mdouble(q)
      return
    else:               # case P = -Q
      r.setInf()
      return

  var PP{.noInit.}, PPP{.noInit.}, Q{.noInit.}: F

  PP.square(P)
  PPP.prod(PP, P)
  Q.prod(p.x, PP)

  r.x.square(R)
  P.double(Q)
  r.x -= PPP
  r.x -= P

  Q -= r.x
  r.y.prod(p.y, PPP)
  R *= Q
  r.y.diff(R, r.y)

  r.zz.prod(p.zz, PP)
  r.zzz.prod(p.zzz, PPP)

func msub_vartime*[F; G: static Subgroup](
       r: var ECP_ShortW_JacExt[F, G],
       p: ECP_ShortW_JacExt[F, G],
       q: ECP_ShortW_Aff[F, G]) {.tags:[VarTime], inline.} =
  var nQ {.noInit.}: ECP_ShortW_Aff[F, G]
  nQ.neg(q)
  r.madd_vartime(p, nQ)

# Conversions
# -----------

template affine*[F, G](_: type ECP_ShortW_JacExt[F, G]): typedesc =
  ## Returns the affine type that corresponds to the Extended Jacobian type input
  ECP_ShortW_Aff[F, G]

template jacobianExtended*[EC](_: typedesc[EC]): typedesc =
  ## Returns the affine type that corresponds to the Extended Jacobian type input
  ECP_ShortW_JacExt[EC.F, EC.G]

func affine*[F; G](
       aff: var ECP_ShortW_Aff[F, G],
       jacext: ECP_ShortW_JacExt[F, G]) {.meter.} =
  var invZZ {.noInit.}, invZZZ{.noInit.}: F
  invZZZ.inv(jacext.zzz)
  invZZ.prod(jacext.zz, invZZZ, skipFinalSub = true)
  invZZ.square(skipFinalSub = true)
  aff.x.prod(jacext.x, invZZ)
  aff.y.prod(jacext.y, invZZZ)

func fromAffine*[F; G](
       jacext: var ECP_ShortW_JacExt[F, G],
       aff: ECP_ShortW_Aff[F, G]) {.inline, meter.} =
  jacext.x = aff.x
  jacext.y = aff.y
  jacext.zz.setOne()
  jacext.zzz.setOne()

  let inf = aff.isInf()
  jacext.zz.csetZero(inf)
  jacext.zzz.csetZero(inf)

func fromJacobianExtended_vartime*[F; G](
       prj: var ECP_ShortW_Prj[F, G],
       jacext: ECP_ShortW_JacExt[F, G]) {.inline, meter, tags:[VarTime].} =
  # Affine (x, y)
  # Jacobian extended (xZ², yZ³, Z², Z³)
  # Projective        (xZ', yZ', Z')
  # We can choose Z' = Z⁵
  if jacext.isInf().bool:
    prj.setInf()
    return
  prj.z.prod(jacext.zz, jacext.zzz)
  prj.x.prod(jacext.x, jacext.zzz)
  prj.y.prod(jacext.y, jacext.zz)

func fromJacobianExtended_vartime*[F; G](
       jac: var ECP_ShortW_Jac[F, G],
       jacext: ECP_ShortW_JacExt[F, G]) {.inline, meter, tags:[VarTime].} =
  # Affine (x, y)
  # Jacobian extended (xZ²,  yZ³,  Z², Z³)
  # Jacobian          (xZ'², yZ'³, Z')
  # We can choose Z' = Z²
  if jacext.isInf().bool:
    jac.setInf()
    return
  jac.x.prod(jacext.x, jacext.zz)
  jac.y.prod(jacext.y, jacext.zzz)
  jac.z = jacext.zz