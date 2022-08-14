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
  ../math/config/curves,
  ../math/[arithmetic, extension_fields],
  ../math/constants/zoo_hash_to_curve,
  ./h2c_utilities

# ############################################################
#
# Mapping to isogenous curve E'
# using:
# - Shallue-van de Woestijne method (SWU)
# - Simplified Shallue-van de Woestijne (SSWU)
# - Simplified Shallue-van de Woestijne
#   with curve equation parameters a == 0 or b == 0
#   (SSWU0)
#
# ############################################################

# No exceptions allowed
{.push raises: [].}

# Normative references
# - SWU: https://datatracker.ietf.org/doc/html/draft-irtf-cfrg-hash-to-curve-11#section-6.6.1
# - SSWU: https://datatracker.ietf.org/doc/html/draft-irtf-cfrg-hash-to-curve-11#section-6.6.2
# - SSWU0: https://datatracker.ietf.org/doc/html/draft-irtf-cfrg-hash-to-curve-11#section-6.6.3
# Optimizations
# - SSWU of GF(q) with q ≡ 9 (mod 16):
#   - https://datatracker.ietf.org/doc/html/draft-irtf-cfrg-hash-to-curve-11#appendix-G.2.3
#   - https://github.com/cfrg/draft-irtf-cfrg-hash-to-curve/blob/f7dd3761/poc/sswu_opt_9mod16.sage
# Test vector generator
# - https://github.com/cfrg/draft-irtf-cfrg-hash-to-curve/blob/f7dd3761/poc/sswu_generic.sage

func invsqrt_if_square[C: static Curve](
       r: var Fp2[C], a: Fp2[C]): SecretBool =
  ## If ``a`` is a square, compute the inverse square root of ``a``
  ## and store it in r
  ## if not, ``r`` is unmodified.
  ##
  ## The square root, if it exist is multivalued,
  ## i.e. both x² == (-x)²
  ## This procedure returns a deterministic result
  ##
  ## This is an optimized version which is
  ## requires the sqrt of sqrt of the quadratic non-residue
  ## to be in Fp2.
  ##
  ## See `sqrt_if_square_opt` in square_root_fp2.nim
  #
  # Implementation via the complex method
  # Gora Adj, Francisco Rodríguez-Henríquez, 2012, https://eprint.iacr.org/2012/685
  # Made constant-time and optimized to fuse sqrt and inverse sqrt
  # and avoid unfused isSquare tests.
  # See discussion and optimization with Andy Polyakov
  # https://github.com/supranational/blst/issues/2#issuecomment-686656784

  var t1{.noInit.}, t2{.noInit.}, t3{.noInit.}: Fp[C]
  var inp{.noInit.}: Fp2[C]

  t1.square(a.c0) #     a0²
  t2.square(a.c1) # - β a1² with β = 𝑖² in a complex extension field
  when a.fromComplexExtension():
    t1 += t2      # a0² - (-1) a1²
  else:
    t2 *= NonResidue
    t1 -= t2

  result = t3.invsqrt_if_square(t1)    # 1/sqrt(a0² - β a1²)

  # If input is not a square in Fp2, multiply by 1/Z³
  inp.prod(a, h2cConst(C, sswu, G2, inv_Z3)) # inp = a / Z³
  block: # Adjust t1 and t3 accordingly
    var t0{.noInit.}: Fp[C]
    t0.prod(t1, h2cConst(C, sswu, G2, squared_norm_inv_Z3)) # (a0² - β a1²) * ||1/Z³||²
    t1.ccopy(t0, not result)

    t0.prod(t3, h2cConst(C, sswu, G2, inv_norm_inv_Z3))     # 1/sqrt(a0² - β a1²) * 1/||1/Z³||
    t3.ccopy(t0, not result)

  inp.ccopy(a, result)

  t1 *= t3     # sqrt(a0² - β a1²)

  t2.diff(inp.c0, t1)
  t1 += inp.c0
  t1.ccopy(t2, t1.isZero())
  t1.div2()    # (a0 ± sqrt(a0² - βa1²))/2

  r.c0.invsqrt(t1)

  r.c1 = inp.c1
  r.c1.div2()
  r.c1 *= r.c0 # a1/(2*sqrt( (a0 ± sqrt(a0²+a1²))/2 ))
  r.c0 *= t1   # sqrt((a0 ± sqrt(a0²+a1²))/2)

  # Now rotate in extension field coordinate (a+βb)
  # to find the quadrant of the square root.
  discard sqrt_rotate_extension(r, r, inp)

  # Inverse the result
  r.c0 *= t3
  r.c1 *= t3
  r.c1.neg()

  # return result

func mapToIsoCurve_sswuG2_opt9mod16*[C: static Curve](
       xn, xd, yn: var Fp2[C],
       u: Fp2[C], xd3: var Fp2[C]) =
  ## Given G2, the target prime order subgroup of E2 we want to hash to,
  ## this function maps any field element of Fp2 to E'2
  ## a curve isogenous to E2 using the Simplified Shallue-van de Woestijne method.
  ##
  ## This requires p² ≡ 9 (mod 16).
  ##
  ## Input:
  ## - u, an Fp2 element
  ## Output:
  ## - (xn, xd, yn, yd) such that (x', y') = (xn/xd, yn/yd)
  ##   is a point of E'2
  ## - yd is implied to be 1
  ## Scratchspace:
  ## - xd3 is temporary scratchspace that will hold xd³
  ##   after execution (which might be useful for Jacobian coordinate conversion)
  #
  # Paper: https://eprint.iacr.org/2019/403
  # Spec: https://datatracker.ietf.org/doc/html/draft-irtf-cfrg-hash-to-curve-11#appendix-G.2.3
  # Sage: https://github.com/cfrg/draft-irtf-cfrg-hash-to-curve/blob/f7dd3761/poc/sswu_opt_9mod16.sage#L36-L118
  # BLST: https://github.com/supranational/blst/blob/v0.3.4/src/map_to_g2.c#L229-L273
  # Formal verification: https://github.com/GaloisInc/BLST-Verification/blob/8e2efde4/spec/implementation/HashToG2.cry

  var
    uu {.noInit.}, tv2 {.noInit.}: Fp2[C]
    tv4 {.noInit.}, x2n {.noInit.}, gx1 {.noInit.}: Fp2[C]
    y2 {.noInit.}: Fp2[C]
    e1, e2: SecretBool

  # Aliases
  template y: untyped = yn
  template x1n: untyped = xn
  template y1: untyped = yn
  template Zuu: untyped = x2n
  template gxd: untyped = xd3

  # x numerators
  uu.square(u)                                 # uu = u²
  Zuu.prod(uu, h2cConst(C, sswu, G2, Z))       # Zuu = Z * uu
  tv2.square(Zuu)                              # tv2 = Zuu²
  tv2 += Zuu                                   # tv2 = tv2 + Zuu
  x1n.setOne()
  x1n += tv2                                   # x1n = tv2 + 1
  x1n *= h2cConst(C, sswu, G2, Bprime_E2)      # x1n = x1n * B'
  x2n.prod(Zuu, x1n)                           # x2n = Zuu * x1n

  # x denumerator
  xd.prod(tv2, h2cConst(C, sswu, G2, minus_A)) # xd = -A * tv2
  e1 = xd.isZero()                             # e1 = xd == 0
  xd.ccopy(h2cConst(C, sswu, G2, ZmulA), e1)   # If xd == 0, set xd = Z*A

  # y numerators
  tv2.square(xd)
  gxd.prod(xd, tv2)                            # gxd = xd³
  tv2.mulCheckSparse(h2CConst(C, sswu, G2, Aprime_E2))
  gx1.square(x1n)
  gx1 += tv2                                   # x1n² + A * xd²
  gx1 *= x1n                                   # x1n³ + A * x1n * xd²
  tv2.prod(gxd, h2cConst(C, sswu, G2, Bprime_E2))
  gx1 += tv2                                   # gx1 = x1n³ + A * x1n * xd² + B * xd³
  tv4.square(gxd)                              # tv4 = gxd²
  tv2.prod(gx1, gxd)                           # tv2 = gx1 * gxd
  tv4 *= tv2                                   # tv4 = gx1 * gxd³

  # Start searching for sqrt(gx1)
  e2 = y1.invsqrt_if_square(tv4)               # y1 = tv4^c1 = (gx1 * gxd³)^((p²-9)/16)
  y1 *= tv2                                    # y1 *= gx1*gxd
  y2.prod(y1, uu)
  y2 *= u

  # Choose numerators
  xn.ccopy(x2n, not e2)                        # xn = e2 ? x1n : x2n
  yn.ccopy(y2, not e2)                         # yn = e2 ? y1 : y2

  e1 = sgn0(u)
  e2 = sgn0(y)
  y.cneg(e1 xor e2)

  # yd.setOne()

func mapToIsoCurve_sswuG1_opt3mod4*[C: static Curve](
       xn, xd, yn: var Fp[C],
       u: Fp[C], xd3: var Fp[C]) =
  ## Given G1, the target prime order subgroup of E1 we want to hash to,
  ## this function maps any field element of Fp to E'1
  ## a curve isogenous to E1 using the Simplified Shallue-van de Woestijne method.
  ##
  ## This requires p² ≡ 3 (mod 4).
  ##
  ## Input:
  ## - u, an Fp element
  ## Output:
  ## - (xn, xd, yn, yd) such that (x', y') = (xn/xd, yn/yd)
  ##   is a point of E'1
  ## - yd is implied to be 1
  ## Scratchspace:
  ## - xd3 is temporary scratchspace that will hold xd³
  ##   after execution (which might be useful for Jacobian coordinate conversion)
  #
  # Paper: https://eprint.iacr.org/2019/403
  # Spec: https://datatracker.ietf.org/doc/html/draft-irtf-cfrg-hash-to-curve-11#appendix-G.2.1
  # Sage: https://github.com/cfrg/draft-irtf-cfrg-hash-to-curve/blob/f7dd3761/poc/sswu_opt_3mod4.sage#L33-L76
  # BLST: https://github.com/supranational/blst/blob/v0.3.4/src/map_to_g1.c#L322-L365
  # Formal verification: https://github.com/GaloisInc/BLST-Verification/blob/8e2efde4/spec/implementation/HashToG1.cry

  var
    uu {.noInit.}, tv2 {.noInit.}: Fp[C]
    tv4 {.noInit.}, x2n {.noInit.}, gx1 {.noInit.}: Fp[C]
    y2 {.noInit.}: Fp[C]
    e1, e2: SecretBool

  # Aliases
  template y: untyped = yn
  template x1n: untyped = xn
  template y1: untyped = yn
  template Zuu: untyped = x2n
  template gxd: untyped = xd3

  # x numerators
  uu.square(u)                            # uu = u²
  Zuu.prod(uu, h2cConst(C, sswu, G1, Z))  # Zuu = Z * uu
  tv2.square(Zuu)                         # tv2 = Zuu²
  tv2 += Zuu                              # tv2 = tv2 + Zuu
  x1n.setOne()
  x1n += tv2                              # x1n = tv2 + 1
  x1n *= h2cConst(C, sswu, G1, Bprime_E1) # x1n = x1n * B'
  x2n.prod(Zuu, x1n)                      # x2n = Zuu * x1n

  # x denumerator
  xd.prod(tv2, h2cConst(C, sswu, G1, minus_A)) # xd = -A * tv2
  e1 = xd.isZero()                             # e1 = xd == 0
  xd.ccopy(h2cConst(C, sswu, G1, ZmulA), e1)   # If xd == 0, set xd = Z*A

  # y numerators
  tv2.square(xd)
  gxd.prod(xd, tv2)                         # gxd = xd³
  tv2 *= h2cConst(C, sswu, G1, Aprime_E1)
  gx1.square(x1n)
  gx1 += tv2                                # x1n² + A * xd²
  gx1 *= x1n                                # x1n³ + A * x1n * xd²
  tv2.prod(gxd, h2cConst(C, sswu, G1, Bprime_E1))
  gx1 += tv2                                # gx1 = x1n³ + A * x1n * xd² + B * xd³
  tv4.square(gxd)                           # tv4 = gxd²
  tv2.prod(gx1, gxd)                        # tv2 = gx1 * gxd
  tv4 *= tv2                                # tv4 = gx1 * gxd³

  # Start searching for sqrt(gx1)
  e2 = y1.invsqrt_if_square(tv4)            # y1 = tv4^c1 = (gx1 * gxd³)^((p²-9)/16)
  y1 *= tv2                                 # y1 *= gx1*gxd
  y2.prod(y1, h2cConst(C, sswu, G1, sqrt_minus_Z3))
  y2 *= uu
  y2 *= u

  # Choose numerators
  xn.ccopy(x2n, not e2)                     # xn = e2 ? x1n : x2n
  yn.ccopy(y2, not e2)                      # yn = e2 ? y1 : y2

  e1 = sgn0(u)
  e2 = sgn0(y)
  y.cneg(e1 xor e2)

  # yd.setOne()
