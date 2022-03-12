# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  # Internals
  ../platforms/abstractions,
  ../math/[arithmetic, extension_fields],
  ../math/curves/zoo_hash_to_curve,
  ../math/elliptic/[
    ec_shortweierstrass_projective,
    ec_shortweierstrass_jacobian,
  ]

# ############################################################
#
#          Mapping from isogenous curve E' to E
#
# ############################################################

# No exceptions allowed
{.push raises: [].}

func poly_eval_horner[F](r: var F, x: F, poly: openarray[F]) =
  ## Fast polynomial evaluation using Horner's rule
  ## The polynomial k₀ + k₁ x + k₂ x² + k₃ x³ + ... + kₙ xⁿ
  ## MUST be stored in order
  ## [k₀, k₁, k₂, k₃, ..., kₙ]
  ##
  ## Assuming a degree n = 3 polynomial
  ## Horner's rule rewrites its evaluation as
  ## ((k₃ x + k₂)x + k₁) x + k₀
  ## which is n additions and n multiplications,
  ## the lowest complexity of general polynomial evaluation algorithm.
  r = poly[^1] # TODO: optim when poly[^1] == 1
  for i in countdown(poly.len-2, 0):
    r *= x
    r += poly[i]

func poly_eval_horner_scaled[F; D, N: static int](
       r: var F, xn: F,
       xd_pow: array[D, F], poly: array[N, F]) =
  ## Fast polynomial evaluation using Horner's rule
  ## Result is scaled by xd^N with N the polynomial degree
  ## to avoid finite field division
  ##
  ## The array of xd powers xd^e has e in [1, N],
  ## for example [xd, xd², xd³]
  ##
  ## The polynomial k₀ + k₁ xn/xd + k₂ (xn/xd)² + k₃ (xn/xd)³ + ... + kₙ (xn/xd)ⁿ
  ## MUST be stored in order
  ## [k₀, k₁, k₂, k₃, ..., kₙ]
  ##
  ## Assuming a degree n = 3 polynomial
  ## Horner's rule rewrites its evaluation as
  ## ((k₃ (xn/xd) + k₂)(xn/xd) + k₁) (xn/xd) + k₀
  ## which is n additions and n multiplications,
  ## the lowest complexity of general polynomial evaluation algorithm.
  ##
  ## By scaling by xd³
  ## we get
  ## ((k₃ xn + k₂ xd) xn + k₁ xd²) xn + k₀ xd³
  ##
  ## avoiding expensive divisions
  r = poly[^1] # TODO: optim when poly[^1] == 1
  for i in countdown(N-2, 0):
    var t: F
    r *= xn
    t.prod(poly[i], xd_pow[N-2-i])
    r += t

  const
    poly_degree = N-1 # [1, x, x², x³] of length 4
    isodegree = D     # Isogeny degree

  static: doAssert isodegree - poly_degree >= 0
  when isodegree - poly_degree > 0:
    # Missing scaling factor
    r *= xd_pow[isodegree - poly_degree - 1]

func h2c_isogeny_map[F](
       rxn, rxd, ryn, ryd: var F,
       xn, xd, yn: F, isodegree: static int) =
  ## Given G2, the target prime order subgroup of E2,
  ## this function maps an element of
  ## E'2 a curve isogenous to E2
  ## to E2.
  ##
  ## The E'2 input is represented as
  ## (x', y') with x' = xn/xd and y' = yn/yd
  ##
  ## yd is assumed to be 1 hence y' == yn
  ##
  ## The E2 output is represented as
  ## (rx, ry) with rx = rxn/rxd and ry = ryn/ryd

  # xd^e with e in [1, N], for example [xd, xd², xd³]
  static: doAssert isodegree >= 2
  var xd_pow{.noInit.}: array[isodegree, F]
  xd_pow[0] = xd
  xd_pow[1].square(xd_pow[0])
  for i in 2 ..< xd_pow.len:
    xd_pow[i].prod(xd_pow[i-1], xd_pow[0])

  rxn.poly_eval_horner_scaled(
    xn, xd_pow,
    h2cIsomapPoly(F.C, G2, isodegree, xnum)
  )
  rxd.poly_eval_horner_scaled(
    xn, xd_pow,
    h2cIsomapPoly(F.C, G2, isodegree, xden)
  )

  ryn.poly_eval_horner_scaled(
    xn, xd_pow,
    h2cIsomapPoly(F.C, G2, isodegree, ynum)
  )
  ryd.poly_eval_horner_scaled(
    xn, xd_pow,
    h2cIsomapPoly(F.C, G2, isodegree, yden)
  )

  # y coordinate is y' * poly_yNum(x)
  ryn *= yn

func h2c_isogeny_map*[F; G: static Subgroup](
       r: var ECP_ShortW_Prj[F, G],
       xn, xd, yn: F, isodegree: static int) =
  ## Given G2, the target prime order subgroup of E2,
  ## this function maps an element of
  ## E'2 a curve isogenous to E2
  ## to E2.
  ##
  ## The E'2 input is represented as
  ## (x', y') with x' = xn/xd and y' = yn/yd
  ##
  ## yd is assumed to be 1 hence y' == yn
  ##
  ## Reference:
  ## - https://datatracker.ietf.org/doc/html/draft-irtf-cfrg-hash-to-curve-11#section-6.6.3
  ## - https://github.com/cfrg/draft-irtf-cfrg-hash-to-curve

  var t{.noInit.}: F

  h2c_isogeny_map(
    rxn = r.x,
    rxd = r.z,
    ryn = r.y,
    ryd = t,
    xn, xd, yn, isodegree
  )

  # Now convert to projective coordinates
  # (x, y) => (xnum/xden, ynum/yden)
  #       <=> (xnum*yden, ynum*xden, xden*yden)
  r.y *= r.z
  r.x *= t
  r.z *= t

func h2c_isogeny_map*[F; G: static Subgroup](
       r: var ECP_ShortW_Jac[F, G],
       xn, xd, yn: F, isodegree: static int) =
  ## Given G2, the target prime order subgroup of E2,
  ## this function maps an element of
  ## E'2 a curve isogenous to E2
  ## to E2.
  ##
  ## The E'2 input is represented as
  ## (x', y') with x' = xn/xd and y' = yn/yd
  ##
  ## yd is assumed to be 1 hence y' == yn
  ##
  ## Reference:
  ## - https://datatracker.ietf.org/doc/html/draft-irtf-cfrg-hash-to-curve-11#section-6.6.3
  ## - https://github.com/cfrg/draft-irtf-cfrg-hash-to-curve

  var rxn{.noInit.}, rxd{.noInit.}: F
  var ryn{.noInit.}, ryd{.noInit.}: F

  h2c_isogeny_map(
    rxn, rxd,
    ryn, ryd,
    xn, xd, yn, isodegree
  )

  # Now convert to jacobian coordinates
  # (x, y) => (xnum/xden, ynum/yden)
  #       <=> (xZ², yZ³, Z)
  #       <=> (xnum*xden*yden², ynum*yden²*xden³, xden*yden)
  r.z.prod(rxd, ryd) # Z = xn * xd
  r.x.prod(rxn, ryd) # X = xn * yd
  r.x *= r.z         # X = xn * xd * yd²
  r.y.square(r.z)    # Y = xd² * yd²
  r.y *= rxd         # Y = yd² * xd³
  r.y *= ryn         # Y = yn * yd² * xd³

func h2c_isogeny_map*[F; G: static Subgroup](
       r: var ECP_ShortW_Jac[F, G],
       P: ECP_ShortW_Jac[F, G],
       isodegree: static int) =
  ## Map P in isogenous curve E'2
  ## to r in E2
  ##
  ## r and P are NOT on the same curve.
  #
  # We have in affine <=> jacobian representation
  # (x, y) <=> (xn/xd, yn/yd)
  #        <=> (xZ², yZ³, Z)
  #
  # We scale the isogeny coefficients by powers
  # of Z²

  var xn{.noInit.}, xd{.noInit.}: F
  var yn{.noInit.}, yd{.noInit.}: F

  # Z²^e with e in [1, N], for example [Z², Z⁴, Z⁶]
  static: doAssert isodegree >= 2
  var ZZpow{.noInit.}: array[isodegree, F]
  ZZpow[0].square(P.z)
  ZZpow[1].square(ZZpow[0])
  for i in 2 ..< ZZpow.len:
    ZZpow[i].prod(ZZpow[i-1], ZZpow[0])

  xn.poly_eval_horner_scaled(
    P.x, ZZpow,
    h2cIsomapPoly(F.C, G2, isodegree, xnum)
  )
  xd.poly_eval_horner_scaled(
    P.x, ZZpow,
    h2cIsomapPoly(F.C, G2, isodegree, xden)
  )

  yn.poly_eval_horner_scaled(
    P.x, ZZpow,
    h2cIsomapPoly(F.C, G2, isodegree, ynum)
  )
  yd.poly_eval_horner_scaled(
    P.x, ZZpow,
    h2cIsomapPoly(F.C, G2, isodegree, yden)
  )

  # yn = y' * poly_yNum(x) = yZ³ * poly_yNum(x)
  yn *= P.y

  # Scale yd by Z³
  yd *= P.z
  yd *= ZZpow[0]

  # Now convert to jacobian coordinates
  # (x, y) => (xnum/xden, ynum/yden)
  #       <=> (xZ², yZ³, Z)
  #       <=> (xnum*xden*yden², ynum*yden²*xden³, xden*yden)
  r.z.prod(xd, yd) # Z = xn * xd
  r.x.prod(xn, yd) # X = xn * yd
  r.x *= r.z       # X = xn * xd * yd²
  r.y.square(r.z)  # Y = xd² * yd²
  r.y *= xd        # Y = yd² * xd³
  r.y *= yn        # Y = yn * yd² * xd³
