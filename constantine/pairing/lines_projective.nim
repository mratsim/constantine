# Constantine
# Copyright (c) 2018-2019    Status Research & Development GmbH
# Copyright (c) 2020-Present Mamy André-Ratsimbazafy
# Licensed and distributed under either of
#   * MIT license (license terms in the root directory or at http://opensource.org/licenses/MIT).
#   * Apache v2 license (license terms in the root directory or at http://www.apache.org/licenses/LICENSE-2.0).
# at your option. This file may not be copied, modified, or distributed except according to those terms.

import
  ../primitives,
  ../config/curves,
  ../arithmetic,
  ../towers,
  ../elliptic/[
    ec_shortweierstrass_affine,
    ec_shortweierstrass_projective
  ],
  ./lines_common

export lines_common

# No exceptions allowed
{.push raises: [].}

# ############################################################
#
#            Miller Loop's Line Evaluation
#             with projective coordinates
#
# ############################################################
#
# - Pairing Implementation Revisited
#   Michael Scott, 2019
#   https://eprint.iacr.org/2019/077
#
# - The Realm of the Pairings
#   Diego F. Aranha and Paulo S. L. M. Barreto
#   and Patrick Longa and Jefferson E. Ricardini, 2013
#   https://eprint.iacr.org/2013/722.pdf
#   http://sac2013.irmacs.sfu.ca/slides/s1.pdf
#
# - Efficient Implementation of Bilinear Pairings on ARM Processors
#   Gurleen Grewal, Reza Azarderakhsh,
#   Patrick Longa, Shi Hu, and David Jao, 2012
#   https://eprint.iacr.org/2012/408.pdf

# Line evaluation only
# -----------------------------------------------------------------------------

func line_eval_double[F](
       line: var Line[F],
       T: ECP_ShortW_Prj[F, OnTwist]) =
  ## Evaluate the line function for doubling
  ## i.e. the tangent at T
  ##
  ## With T in homogenous projective coordinates (X, Y, Z)
  ## And ξ the sextic non residue to construct 𝔽p4 / 𝔽p6 / 𝔽p12
  ##
  ## M-Twist:
  ##   A = -2ξ Y.Z
  ##   B = 3bξ Z² - Y²
  ##   C = 3 X²
  ##
  ## D-Twist are scaled by ξ to avoid dividing by ξ:
  ##   A = -2ξ Y.Z
  ##   B = 3b Z² - ξY²
  ##   C = 3ξ X²
  ##
  ## Instead of
  ##   - equation 10 from The Real of pairing, Aranha et al, 2013
  ##   - or chapter 3 from pairing Implementation Revisited, Scott 2019
  ##   A = -2 Y.Z
  ##   B = 3b/ξ Z² - Y²
  ##   C = 3 X²
  ##
  ## A constant factor will be wiped by the final exponentiation
  ## as for all non-zero α ∈ GF(pᵐ)
  ## with
  ## - p odd prime
  ## - and gcd(α,pᵐ) = 1 (i.e. the extension field pᵐ is using irreducible polynomials)
  ##
  ## Little Fermat holds and we have
  ## α^(pᵐ - 1) ≡ 1 (mod pᵐ)
  ##
  ## The final exponent is of the form
  ## (pᵏ-1)/r
  ##
  ## A constant factor on twisted coordinates pᵏᐟᵈ
  ## is a constant factor on pᵏ with d the twisting degree
  ## and so will be elminated. QED.
  var v {.noInit.}: F
  const b3 = 3 * F.C.getCoefB()

  template A: untyped = line.x
  template B: untyped = line.y
  template C: untyped = line.z

  A.prod(T.y, T.z)      # A = Y.Z
  C.square(T.x)         # C = X²
  v.square(T.y)         # v = Y²
  B.square(T.z)         # B = Z²

  A.double()            # A =  2 Y.Z
  A.neg()               # A = -2 Y.Z
  A *= SexticNonResidue # A = -2 ξ Y.Z

  B *= b3               # B = 3b Z²
  C *= 3                # C = 3X²
  when F.C.getSexticTwist() == M_Twist:
    B *= SexticNonResidue # B = 3b' Z² = 3bξ Z²
  elif F.C.getSexticTwist() == D_Twist:
    v *= SexticNonResidue # v =  ξ Y²
    C *= SexticNonResidue # C = 3ξ X²
  else:
    {.error: "unreachable".}

  B -= v                # B = 3bξ Z² - Y²  (M-twist)
                        # B = 3b Z² - ξ Y² (D-twist)

func line_eval_add[F](
       line: var Line[F],
       T: ECP_ShortW_Prj[F, OnTwist],
       Q: ECP_ShortW_Aff[F, OnTwist]) =
  ## Evaluate the line function for addition
  ## i.e. the line between T and Q
  ##
  ## With T in homogenous projective coordinates (X, Y, Z)
  ## And ξ the sextic non residue to construct 𝔽p4 / 𝔽p6 / 𝔽p12
  ##
  ## M-Twist:
  ##   A = ξ (X₁ - Z₁X₂)
  ##   B = (Y₁ - Z₁Y₂) X₂ - (X₁ - Z₁X₂) Y₂
  ##   C = - (Y₁ - Z₁Y₂)
  ##
  ## D-Twist:
  ##   A = X₁ - Z₁X₂
  ##   B = (Y₁ - Z₁Y₂) X₂ - (X₁ - Z₁X₂) Y₂
  ##   C = - (Y₁ - Z₁Y₂)
  ##
  ## Note: There is no need for complete formula as
  ## we have T ∉ [Q, -Q] in the Miller loop doubling-and-add
  ## i.e. the line cannot be vertical
  var v {.noInit.}: F

  template A: untyped = line.x
  template B: untyped = line.y
  template C: untyped = line.z

  v.prod(T.z, Q.y) # v = Z₁Y₂
  B.prod(T.z, Q.x) # B = Z₁X₂

  A.diff(T.x, B)   # A = X₁-Z₁X₂
  C.diff(T.y, v)   # C = Y₁-Z₁Y₂

  v.prod(A, Q.y)   # v = (X₁-Z₁X₂) Y₂
  B.prod(C, Q.x)   # B = (Y₁-Z₁Y₂) X₂
  B -= v           # B = (Y₁-Z₁Y₂) X₂ - (X₁-Z₁X₂) Y₂

  C.neg()          # C = -(Y₁-Z₁Y₂)

  when F.C.getSexticTwist() == M_Twist:
    A *= SexticNonResidue # A = ξ (X₁ - Z₁X₂)

func line_eval_fused_double[Field](
       line: var Line[Field],
       T: var ECP_ShortW_Prj[Field, OnTwist]) =
  ## Fused line evaluation and elliptic point doubling
  # Grewal et al, 2012 adapted to Scott 2019 line notation
  var A {.noInit.}, B {.noInit.}, C {.noInit.}: Field
  var E {.noInit.}, F {.noInit.}, G {.noInit.}: Field
  template H: untyped = line.x
  const b3 = 3*Field.C.getCoefB()

  var snrY = T.y
  when Field.C.getSexticTwist() == D_Twist:
    snrY *= SexticNonResidue

  A.prod(T.x, snrY)
  A.div2()          # A = XY/2
  B.square(T.y)     # B = Y²
  C.square(T.z)     # C = Z²

  var snrB = B
  when Field.C.getSexticTwist() == D_Twist:
    snrB *= SexticNonResidue

  E.prod(C, b3)
  when Field.C.getSexticTwist() == M_Twist:
    E *= SexticNonResidue # E = 3b'Z² = 3bξ Z²

  F.prod(E, 3)      # F = 3E = 9bZ²
  G.sum(snrB, F)
  G.div2()          # G = (B+F)/2
  H.sum(T.y, T.z)
  H.square()
  H -= B
  H -= C            # lx = H = (Y+Z)²-(B+C)= 2YZ

  line.z.square(T.x)
  line.z *= 3       # lz = 3X²
  when Field.C.getSexticTwist() == D_Twist:
    line.z *= SexticNonResidue

  line.y.diff(E, snrB) # ly = E-B = 3b'Z² - Y²

  # In-place modification: invalidates `T.` calls
  T.x.diff(snrB, F)
  T.x *= A          # X₃ = A(B-F) = XY/2.(Y²-9b'Z²)
                    # M-twist: XY/2.(Y²-9bξZ²)
                    # D-Twist: ξXY/2.(Y²ξ-9bZ²)

  T.y.square(G)
  E.square()
  E *= 3
  T.y -= E          # Y₃ = G² - 3E² = (Y²+9b'Z²)²/4 - 3*(3b'Z²)²
                    # M-twist: (Y²+9bξZ²)²/4 - 3*(3bξZ²)²
                    # D-Twist: (ξY²+9bZ²)²/4 - 3*(3bZ²)²

  when Field.C.getSexticTwist() == D_Twist:
    H *= SexticNonResidue
  T.z.prod(snrB, H) # Z₃ = BH = Y²((Y+Z)² - (Y²+Z²)) = 2Y³Z
                    # M-twist: 2Y³Z
                    # D-twist: 2ξ²Y³Z

  # Correction for Fp4 towering
  H.neg()           # lx = -H
  when Field.C.getSexticTwist() == M_Twist:
    H *= SexticNonResidue
    # else: the SNR is already integrated in H

func line_eval_fused_add[Field](
       line: var Line[Field],
       T: var ECP_ShortW_Prj[Field, OnTwist],
       Q: ECP_ShortW_Aff[Field, OnTwist]) =
  ## Fused line evaluation and elliptic point addition
  # Grewal et al, 2012 adapted to Scott 2019 line notation
  var
    A {.noInit.}: Field
    B {.noInit.}: Field
    C {.noInit.}: Field
    D {.noInit.}: Field
    E {.noInit.}: Field
    F {.noInit.}: Field
    G {.noInit.}: Field
    H {.noInit.}: Field
    I {.noInit.}: Field

  template lambda: untyped = line.x
  template theta: untyped = line.z
  template J: untyped = line.y

  A.prod(Q.y, T.z)
  B.prod(Q.x, T.z)
  theta.diff(T.y, A)  # θ = Y₁ - Z₁X₂
  lambda.diff(T.x, B) # λ = X₁ - Z₁X₂
  C.square(theta)
  D.square(lambda)
  E.prod(D, lambda)
  F.prod(T.z, C)
  G.prod(T.x, D)
  H.double(G)
  H.diff(F, H)
  H += E
  I.prod(T.y, E)

  T.x.prod(theta, Q.x)
  T.y.prod(lambda, Q.y)
  J.diff(T.x, T.y)

  # EC addition
  T.x.prod(lambda, H)

  T.y.diff(G, H)
  T.y *= theta
  T.y -= I

  T.z *= E

  # Line evaluation
  theta.neg()
  when Field.C.getSexticTwist() == M_Twist:
    lambda *= SexticNonResidue # A = ξ (X₁ - Z₁X₂)

# Public proc
# -----------------------------------------------------------------------------

func line_double*[F1, F2](
       line: var Line[F2],
       T: var ECP_ShortW_Prj[F2, OnTwist],
       P: ECP_ShortW_Aff[F1, NotOnTwist]) =
  ## Doubling step of the Miller loop
  ## T in G2, P in G1
  ##
  ## Compute lt,t(P)
  static: doAssert F1.C == F2.C
  when true:
    line_eval_fused_double(line, T)
    line.line_update(P)
  else:
    line_eval_double(line, T)
    line.line_update(P)
    T.double()

func line_add*[F1, F2](
       line: var Line[F2],
       T: var ECP_ShortW_Prj[F2, OnTwist],
       Q: ECP_ShortW_Aff[F2, OnTwist],
       P: ECP_ShortW_Aff[F1, NotOnTwist]) =
  ## Addition step of the Miller loop
  ## T and Q in G2, P in G1
  ##
  ## Compute lt,q(P)
  static: doAssert F1.C == F2.C
  when true:
    line_eval_fused_add(line, T, Q)
    line.line_update(P)
  else:
    line_eval_add(line, T, Q)
    line.line_update(P)
    T += Q
